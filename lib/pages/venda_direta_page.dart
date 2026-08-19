import 'dart:math' as math;
import 'dart:async';
import 'dart:convert';

import 'html_helper_stub.dart' if (dart.library.html) 'html_helper_web.dart' as html_helper;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:collection/collection.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:sistema_exodo_novo/models/conta_pagar.dart';

import 'package:sistema_exodo_novo/services/data_service.dart';
import 'package:sistema_exodo_novo/services/local_storage_service.dart';
import 'package:sistema_exodo_novo/services/balanca_service.dart';
import 'package:sistema_exodo_novo/services/impressao_service.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:sistema_exodo_novo/models/produto.dart';
import 'package:sistema_exodo_novo/models/forma_venda.dart';
import 'package:sistema_exodo_novo/models/servico.dart';
import 'package:sistema_exodo_novo/models/cliente.dart';
import 'package:sistema_exodo_novo/models/pedido.dart';
import 'package:sistema_exodo_novo/models/item_pedido.dart';
import 'package:sistema_exodo_novo/models/item_servico.dart';
import 'package:sistema_exodo_novo/models/forma_pagamento.dart';
import 'package:sistema_exodo_novo/models/venda_balcao.dart';
import 'package:sistema_exodo_novo/models/empresa.dart';
import 'package:sistema_exodo_novo/utils/units.dart';
import 'package:sistema_exodo_novo/models/delivery_info.dart';
import 'package:sistema_exodo_novo/models/endereco_cliente.dart';
import 'package:sistema_exodo_novo/models/entrega.dart';
import 'package:sistema_exodo_novo/pages/historico_vendas_page.dart';
import 'package:sistema_exodo_novo/pages/pedidos_page.dart';
import 'package:sistema_exodo_novo/pages/cliente_detalhes_page.dart';
import 'package:sistema_exodo_novo/pages/pdv_page.dart';
import 'package:sistema_exodo_novo/pages/home_page.dart';
import 'package:sistema_exodo_novo/theme.dart';
import 'package:sistema_exodo_novo/widgets/historico_nfce_pdv_dialog.dart';
import 'package:sistema_exodo_novo/services/auth_service.dart';
import 'package:sistema_exodo_novo/services/supabase_service.dart';
import 'package:sistema_exodo_novo/services/nfce_service_factory.dart';
import 'package:sistema_exodo_novo/services/nfce_service.dart';
import 'package:sistema_exodo_novo/services/frete_service.dart';
import 'package:sistema_exodo_novo/services/nfce_xml_local_service.dart';
import 'package:sistema_exodo_novo/services/nfce_contingencia_service.dart';
import 'package:sistema_exodo_novo/models/nfce.dart';
import 'package:sistema_exodo_novo/models/carrinho_item.dart';
import 'package:sistema_exodo_novo/models/mesa_comanda.dart';
import 'package:sistema_exodo_novo/models/comissao_vendedor.dart';
import 'package:sistema_exodo_novo/widgets/exodo_logo.dart';
import 'package:sistema_exodo_novo/widgets/exodo_loading.dart';
import 'package:sistema_exodo_novo/widgets/exodo_error_dialog.dart';
import 'package:sistema_exodo_novo/widgets/exodo_success_dialog.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:sistema_exodo_novo/services/whatsapp_service.dart';
import 'package:sistema_exodo_novo/widgets/sync_status_widget.dart';
import 'package:sistema_exodo_novo/pages/cozinha_mesas_funcionario_page.dart';
import 'package:sistema_exodo_novo/pages/cozinha_bar_page.dart';
import 'package:sistema_exodo_novo/models/adicional_produto.dart';
import 'package:sistema_exodo_novo/services/venda_pdf_service.dart';
import 'package:printing/printing.dart';

import 'package:sistema_exodo_novo/services/pedido_pdf_service.dart';
import '../models/funcionario.dart';
import 'package:sistema_exodo_novo/models/pergunta_selecao.dart';
import '../models/taxa_entrega.dart';
import 'package:sistema_exodo_novo/widgets/popup_perguntas_combo.dart';
import 'package:sistema_exodo_novo/models/motorista.dart';

/// Item no carrinho da venda direta
class ItemCarrinho {
  final String id;
  final String nome;
  final String? descricao; // Descrição do produto/serviço
  double preco; // Preço unitário (pode ser alterado no PDV com permissão)
  final double precoOriginal; // Preço original de cadastro do produto
  double quantidade;
  final bool isServico;
  double desconto; // Desconto em valor (R$)
  final String? fornecedorNome; // Fornecedor do produto
  final String? fornecedorId; // ID do fornecedor do produto
  String? observacao;
  final List<AdicionalProduto> adicionais;
  final List<OpcaoPerguntaSelecao> opcoesCombo;
  bool isBrinde; // Identifica se o produto é vendido como brinde (grátis)
  bool baixaProporcional; // true = baixa pela conversão do saco (15 kg = 1); false = baixa a quantidade inteira no ingrediente
  // Forma de venda escolhida no PDV (unidade/caixa/pacote/saco) e sua baixa
  String? unidadeVenda;
  double? quantidadeBaixa;
  // Preço base ANTES das promoções empilhadas (usado para exibir o desconto
  // promocional por item na conferência). null = sem promoção aplicada.
  double? precoSemPromocao;
  // Preço de tabela SEM o desconto do perfil de preços (usado para exibir o
  // desconto da tabela no cupom não fiscal e na NFC-e). null = sem desconto de tabela.
  double? precoTabela;

  ItemCarrinho({
    required this.id,
    required this.nome,
    this.descricao,
    required this.preco,
    double? precoOriginal,
    this.quantidade = 1.0,
    this.isServico = false,
    this.desconto = 0.0,
    this.fornecedorNome,
    this.fornecedorId,
    this.observacao,
    List<AdicionalProduto>? adicionais,
    List<OpcaoPerguntaSelecao>? opcoesCombo,
    this.isBrinde = false,
    this.baixaProporcional = true,
    this.unidadeVenda,
    this.quantidadeBaixa,
    this.precoSemPromocao,
    this.precoTabela,
  })  : precoOriginal = precoOriginal ?? preco,
        adicionais = adicionais ?? [],
        opcoesCombo = opcoesCombo ?? [];

  /// Indica se o preço unitário foi alterado no PDV em relação ao valor original
  bool get tevePrecoAlterado => (preco - precoOriginal).abs() > 0.001;

  /// Indica se foi vendido por um valor MENOR que o preço cadastrado
  bool get foiVendidoMenor => tevePrecoAlterado && preco < precoOriginal;

  /// Indica se foi vendido por um valor MAIOR que o preço cadastrado
  bool get foiVendidoMaior => tevePrecoAlterado && preco > precoOriginal;

  /// Diferença em R$ entre o preço vendido e o preço original
  double get diferencaPreco => preco - precoOriginal;

  double get subtotal {
    if (isBrinde) return 0.0;
    final totalAdicionais = adicionais.fold(0.0, (sum, a) => sum + a.preco);
    final totalCombo = opcoesCombo.fold(0.0, (sum, o) => sum + o.precoAdicional);
    return ((preco + totalAdicionais + totalCombo) * quantidade) - desconto;
  }
  double get subtotalSemDesconto {
    if (isBrinde) return 0.0;
    final totalAdicionais = adicionais.fold(0.0, (sum, a) => sum + a.preco);
    final totalCombo = opcoesCombo.fold(0.0, (sum, o) => sum + o.precoAdicional);
    return (preco + totalAdicionais + totalCombo) * quantidade;
  }

  /// Percentual do desconto promocional aplicado no item (null se não houver).
  double? get descontoPromocionalPercent {
    if (precoSemPromocao == null || precoSemPromocao! <= preco + 0.001) {
      return null;
    }
    return (precoSemPromocao! - preco) / precoSemPromocao! * 100;
  }

  /// Valor (R\$) do desconto promocional aplicado no item (null se não houver).
  double? get descontoPromocionalValor {
    final pct = descontoPromocionalPercent;
    return pct == null ? null : precoSemPromocao! - preco;
  }

  // Serialização para persistência
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'nome': nome,
      'descricao': descricao,
      'preco': preco,
      'precoOriginal': precoOriginal,
      'quantidade': quantidade,
      'isServico': isServico,
      'desconto': desconto,
      'fornecedorNome': fornecedorNome,
      'fornecedorId': fornecedorId,
      'observacao': observacao,
      'adicionais': adicionais.map((a) => a.toMap()).toList(),
      'opcoesCombo': opcoesCombo.map((o) => o.toMap()).toList(),
      'isBrinde': isBrinde,
      'baixaProporcional': baixaProporcional,
      'unidadeVenda': unidadeVenda,
      'quantidadeBaixa': quantidadeBaixa,
      'precoSemPromocao': precoSemPromocao,
      'precoTabela': precoTabela,
    };
  }

  factory ItemCarrinho.fromMap(Map<String, dynamic> map) {
    final p = (map['preco'] ?? 0.0).toDouble();
    return ItemCarrinho(
      id: map['id'] ?? '',
      nome: map['nome'] ?? '',
      descricao: map['descricao'],
      preco: p,
      precoOriginal: map['precoOriginal'] != null ? (map['precoOriginal'] as num).toDouble() : p,
      quantidade: (map['quantidade'] ?? 1.0).toDouble(),
      isServico: map['isServico'] ?? false,
      desconto: (map['desconto'] ?? 0.0).toDouble(),
      fornecedorNome: map['fornecedorNome'],
      fornecedorId: map['fornecedorId'],
      observacao: map['observacao'],
      adicionais: (map['adicionais'] as List<dynamic>?)
          ?.map((a) => AdicionalProduto.fromMap(a as Map<String, dynamic>))
          .toList() ?? [],
      opcoesCombo: (map['opcoesCombo'] as List<dynamic>?)
          ?.map((o) => OpcaoPerguntaSelecao.fromMap(o as Map<String, dynamic>))
          .toList() ?? [],
      isBrinde: map['isBrinde'] ?? false,
      baixaProporcional: (map['baixaProporcional'] ?? true) == true,
      unidadeVenda: map['unidadeVenda'],
      quantidadeBaixa: map['quantidadeBaixa'] != null
          ? (map['quantidadeBaixa'] as num).toDouble()
          : null,
      precoSemPromocao: map['precoSemPromocao'] != null
          ? (map['precoSemPromocao'] as num).toDouble()
          : null,
      precoTabela: map['precoTabela'] != null
          ? (map['precoTabela'] as num).toDouble()
          : null,
    );
  }
}

/// Página de Venda Direta no PDV - Versão Melhorada
class VendaDiretaPage extends StatefulWidget {
  final Pedido? pedidoParaEditar; // Pedido/venda salva para continuar
  final VoidCallback? onVendaFinalizada; // Callback quando finalizar
  final Cliente? clienteInicial; // Cliente já selecionado
  final List<ItemPedido>? itensParaRepetir; // Itens para repetir venda
  final List<ItemServico>? servicosParaRepetir; // Serviços para repetir venda
  final MesaComanda? mesaComanda; // Mesa/Comanda para receber

  VendaDiretaPage({
    super.key,
    this.pedidoParaEditar,
    this.onVendaFinalizada,
    this.clienteInicial,
    this.itensParaRepetir,
    this.servicosParaRepetir,
    this.mesaComanda,
  });

  @override
  State<VendaDiretaPage> createState() => _VendaDiretaPageState();
}

enum SortOption { codigo, nome, recentes, grupo }
enum ViewMode { grid, list }

class _VendaDiretaPageState extends State<VendaDiretaPage> {
  bool get isDark => Theme.of(context).brightness == Brightness.dark;
  Color get textColor => isDark ? Colors.white : Colors.black87;
  Color get subTextColor => isDark ? Colors.white70 : Colors.black54;

  ViewMode _viewMode = ViewMode.grid;
  final _buscaController = TextEditingController();
  final _buscaFocusNode = FocusNode();
  String _termoBusca = '';
  SortOption _sortOption = SortOption.codigo;

  // Cache de performance para evitar rebuilds pesados (6k+ itens)
  bool _estaComPopupAberto = false;
  List<dynamic>? _cachedItens;
  List<String>? _cachedCategorias;
  List<Produto>? _cachedProdutosCategoria;
  String? _ultimoTermoCache;
  String? _ultimaCategoriaCache;
  DateTime? _ultimaAtualizacaoCache;
  final List<ItemCarrinho> _carrinho = [];
  final NumberFormat _formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  Cliente? _clienteSelecionado;
  String? _tabelaPrecoAtiva;
    Funcionario? _vendedorSelecionado;
  String? _categoriaAtiva;

  double _quantidadeDigitada = 1.0;
  // Forma de venda selecionada pelo diálogo (unidade/caixa/pacote/saco) antes de adicionar ao carrinho
  FormaVenda? _formaVendaPendente;
  final AudioPlayer _audioPlayerPDV = AudioPlayer();

  Future<void> _tocarSomPDV(String filename, {required String tipo}) async {
    if (!_somHabilitado) return;
    if (tipo == 'adicionar' && !_somAdicionarHabilitado) return;
    if (tipo == 'remover' && !_somRemoverHabilitado) return;
    if (tipo == 'finalizar' && !_somFinalizarHabilitado) return;

    String audioFile = filename;
    if (tipo == 'adicionar') audioFile = 'add.wav';
    if (tipo == 'remover') audioFile = 'remove.wav';
    if (tipo == 'finalizar') audioFile = 'success.wav';

    try {
      await _audioPlayerPDV.stop();
      await _audioPlayerPDV.setVolume(0.5);
      if (kIsWeb) {
        final origin = html_helper.getWindowOrigin();
        final url = '$origin/assets/sounds/$audioFile';
        await _audioPlayerPDV.play(UrlSource(url));
      } else {
        await _audioPlayerPDV.play(AssetSource('sounds/$audioFile'));
      }
    } catch (e) {
      debugPrint('>>> [Audio PDV] Erro ao tocar som: $e');
    }
  }
  Pedido? _pedidoOriginal; // Pedido original sendo editado
  List<PagamentoPedido> _pagamentosSalvos =
      []; // Pagamentos do pedido sendo editado
  double _descontoTotal = 0.0; // Desconto total da venda (R$)
  String? _observacoesVenda; // Observações da venda
  String? _cpfNfce; // CPF/CNPJ para a NFC-e (consumidor não identificado)
  String? _nomeNfce; // Nome para a NFC-e (consumidor não identificado)
  int _gridSelectedIndex = -1;
  int _cartSelectedIndex = -1;
  int _categoriaSelectedIndex = -1;
  bool _focoNoCarrinho = false; // false = grid de produtos, true = carrinho
  bool _focoNasCategorias = false;
  final FocusNode _atalhosFocusNode = FocusNode();
  MesaComanda? _mesaComandaVinculada; // Mesa ou Comanda vinculada à venda atual
  Timer? _timerFullscreen;
  int _segundosSemFullscreen = 0;
  final ScrollController _carrinhoScrollController = ScrollController();
  final ScrollController _gridScrollController = ScrollController();
  String? _ultimoItemAdicionadoId; // ID do último item adicionado (para destaque)
  bool _dialogAberto = false; // Flag para evitar duplos F9 (múltiplas telas de pagamento)
  int _itensVisiveisPDV = 500; // Aumentado de 100 para 500 para carregar um catálogo maior inicialmente
  static const int _itensPorPaginaPDV = 100;
  List<Produto> _cacheProdutosCategoria = [];
  String? _cacheCategoriaAtiva;
  SortOption _cacheSortPDV = SortOption.codigo;
  int _cacheTotalProdutosPDV = 0;
  int _cacheTotalPerguntasPDV = 0;

  // ESTADO DE DELIVERY
  bool _isDelivery = false;
  EnderecoCliente? _enderecoEntrega;
  double _taxaEntrega = 0.0;
  String? _motoristaId;
  String? _motoristaNome;
  double _valorParaTroco = 0.0; // Valor informado pelo cliente para troco
  TipoPagamento? _formaPagamentoDelivery = TipoPagamento.dinheiro; // Forma de pagamento registrada para a entrega
  String _previsaoEntrega = ''; // Previsão de entrega informada (ex: 30-45 min ou 18:30)
  String _infoCalculoTaxa = '';
  bool _calculandoTaxa = false;

  bool _estaFinalizando = false; // Flag para evitar duplos cliques e concorrência
  final LocalStorageService _storage = LocalStorageService();
  String? _empresaIdStorage; // Para isolar dados por empresa
  
  /// Retorna a chave de storage prefixada com o ID da empresa atual
  String _chavePDV(String baseKey) {
    if (_empresaIdStorage == null) return baseKey;
    return 'empresa_${_empresaIdStorage}_$baseKey';
  }
  
  static const String _keyCarrinhoPDV = 'exodo_carrinho_pdv';
  static const String _keyClientePDV = 'exodo_cliente_pdv';
  static const String _keyTabelaPrecoPDV = 'exodo_tabela_preco_pdv';
  static const String _keyCpfNfcePDV = 'exodo_cpf_nfce_pdv';
  static const String _keyNomeNfcePDV = 'exodo_nome_nfce_pdv';
  static const String _keyDescontoTotalPDV = 'exodo_desconto_total_pdv';
  static const String _keySomPDV = 'exodo_som_pdv';
  static const String _keySomAdicionar = 'exodo_som_adicionar';
  static const String _keySomRemover = 'exodo_som_remover';
  static const String _keySomFinalizar = 'exodo_som_finalizar';
  static const String _keyAlertarLimiteGaveta = 'exodo_alertar_limite_gaveta';
  static const String _keyLimiteGavetaValor = 'exodo_limite_gaveta_valor';
  bool _somHabilitado = true;
  bool _somAdicionarHabilitado = true;
  bool _somRemoverHabilitado = true;
  bool _somFinalizarHabilitado = true;
  bool _alertarLimiteGaveta = false;
  double _limiteGavetaValor = 1000.0;
  bool _mostrarBarraLegenda = false; // Controle de visibilidade da legenda (hover)
  Timer? _debounce; // Timer para suavizar a busca e evitar lag na digitação do PDV

  // Getters para facilitar identificação de Mesa/Comanda
  String get tipoNome {
    if (_mesaComandaVinculada == null) return 'Venda';
    return _mesaComandaVinculada?.tipo == TipoControle.comanda ? 'Comanda' : 'Mesa';
  }

  String? get _perfilPrecoEfetivo => _tabelaPrecoAtiva;

  List<Map<String, dynamic>> _obterTabelasPrecoEmpresa() {
    final dataService = Provider.of<DataService>(context, listen: false);
    final empresa = dataService.empresaAtual;
    if (empresa == null) return [];

    final cfg = empresa.configuracoes?['perfis_preco'];
    if (cfg is List && cfg.isNotEmpty) {
      return cfg
          .map((e) => Map<String, dynamic>.from(e as Map))
          .where((c) => (c['nome']?.toString() ?? '').isNotEmpty)
          .toList();
    }

    return empresa.perfisDePreco
        .map((nome) => {'nome': nome, 'tipo': 'fixo', 'valor': 0.0})
        .toList();
  }

  String _descricaoTipoTabelaPDV(Map<String, dynamic> config) {
    final tipo = config['tipo'] as String? ?? 'fixo';
    final valor = (config['valor'] as num?)?.toDouble() ?? 0.0;
    switch (tipo) {
      case 'desconto':
        return 'Desconto global: ${valor.toStringAsFixed(1)}%';
      case 'acrescimo':
        return 'Acréscimo global: ${valor.toStringAsFixed(1)}%';
      default:
        return 'Preço fixo por produto';
    }
  }
  String get labelOrigem {
    if (_mesaComandaVinculada == null) return '[BALCÃO]';
    return _mesaComandaVinculada?.tipo == TipoControle.comanda ? '[COMANDA]' : '[MESA]';
  }
  String? get mesaNumero => _mesaComandaVinculada?.numero;
  String? get mesaParaLimparId => _mesaComandaVinculada?.id;

  @override
  void initState() {
    super.initState();

    // Auto Fullscreen Watcher: garante que o PDV sempre volte para tela cheia após 5s se for reduzido
    _timerFullscreen = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (kIsWeb) {
        if (!html_helper.isFullscreen()) {
          _segundosSemFullscreen++;
          if (_segundosSemFullscreen >= 5) {
            _segundosSemFullscreen = 0;
            _entrarTelaCheia();
          }
        } else {
          _segundosSemFullscreen = 0;
        }
      }
    });

    // Solicitar abertura de caixa quando o PDV é aberto
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final dataService = Provider.of<DataService>(context, listen: false);
      if (!dataService.caixaAberto) {
        // Mostrar diálogo para solicitar valor de abertura
        _solicitarAberturaCaixa(context, dataService);
      }
      
      // Iniciar em tela cheia por padrão (no web)
      if (kIsWeb) {
        _entrarTelaCheia();
      }

      // Carregar configurações de visualização (Grade ou Lista)
      final empresa = dataService.empresaAtual;
      
      // Carregar empresaId para isolar preferências
      _empresaIdStorage = dataService.currentEmpresaId;
      
      // Carregar configurações de som (isoladas por empresa)
      _storage.carregar(_chavePDV(_keySomPDV)).then((value) {
        if (value != null && value is bool) {
          setState(() {
            _somHabilitado = value;
          });
        }
      });
      _storage.carregar(_chavePDV(_keySomAdicionar)).then((value) {
        if (value != null && value is bool) {
          setState(() {
            _somAdicionarHabilitado = value;
          });
        }
      });
      _storage.carregar(_chavePDV(_keySomRemover)).then((value) {
        if (value != null && value is bool) {
          setState(() {
            _somRemoverHabilitado = value;
          });
        }
      });
      _storage.carregar(_chavePDV(_keySomFinalizar)).then((value) {
        if (value != null && value is bool) {
          setState(() {
            _somFinalizarHabilitado = value;
          });
        }
      });
      _storage.carregar(_chavePDV(_keyAlertarLimiteGaveta)).then((value) {
        if (value != null && value is bool) {
          setState(() {
            _alertarLimiteGaveta = value;
          });
        }
      });
      _storage.carregar(_chavePDV(_keyLimiteGavetaValor)).then((value) {
        if (value != null) {
          final valDouble = double.tryParse(value.toString());
          if (valDouble != null) {
            setState(() {
              _limiteGavetaValor = valDouble;
            });
          }
        }
      });
      if (empresa != null && empresa.configuracoes?['venda_direta_view_mode'] != null) {
        setState(() {
          _viewMode = empresa.configuracoes!['venda_direta_view_mode'] == 'list' 
              ? ViewMode.list 
              : ViewMode.grid;
        });
      }

      // Focar automaticamente no campo de busca ao abrir o PDV
      _buscaFocusNode.requestFocus();
    });

    // Se veio um pedido para editar, carregar os itens
    if (widget.pedidoParaEditar != null) {
      _carregarPedidoParaEditar(widget.pedidoParaEditar!);
    } else if (widget.mesaComanda != null) {
      // Carregar itens da mesa/comanda
      _mesaComandaVinculada = widget.mesaComanda;
      _carrinho.clear();
      // Filtrar apenas itens que ainda não foram pagos e não foram cancelados
      final itensPendentes = widget.mesaComanda!.itens
          .where((i) => i.status != StatusItem.cancelado && !widget.mesaComanda!.itensPagos.contains(i.id))
          .toList();
          
      _carrinho.addAll(itensPendentes.map((i) => ItemCarrinho(
                id: i.itemId,
                nome: i.nome,
                preco: i.preco,
                quantidade: i.quantidade,
                isServico: i.isServico,
                observacao: i.observacao,
              )));

      // Adicionar couvert como um item se existir
      if (widget.mesaComanda!.valorCouvertCalculado > 0) {
        _carrinho.add(ItemCarrinho(
          id: 'couvert',
          nome: 'Couvert Artístico',
          quantidade: (widget.mesaComanda!.quantidadePessoasCouvert ?? 1).toDouble(),
          preco: widget.mesaComanda!.valorCouvertPorPessoa ?? 0.0,
          isServico: true,
        ));
      }

      // Adicionar taxa do garçom como um item se houver e não foi retirada
      if (!widget.mesaComanda!.garcomRetirado) {
          final vGarcom = widget.mesaComanda!.valorGarcom ?? widget.mesaComanda!.valorGarcomCalculado;
          if (vGarcom > 0.01) {
            _carrinho.add(ItemCarrinho(
              id: 'garcom',
              nome: 'Taxa de Serviço (Garçom)',
              preco: vGarcom,
              quantidade: 1,
              isServico: true,
            ));
          }
      }

      // Carregar pagamentos parciais já feitos na mesa
      final listaPagamentos = <PagamentoPedido>[];
      
      if (widget.mesaComanda!.historicoPagamentos.isNotEmpty) {
        listaPagamentos.addAll(widget.mesaComanda!.historicoPagamentos.map((rp) {
          final f = rp.formaPagamento?.toLowerCase() ?? '';
          TipoPagamento tipo;
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
            observacao: 'Pago na $tipoNome ${widget.mesaComanda!.numero}',
          );
        }));
      }
      
      // Adicionar couvert já pago se houver
      if (widget.mesaComanda!.couvertPago > 0.01) {
        listaPagamentos.add(PagamentoPedido(
          id: 'couvert_pago_anterior',
          tipo: TipoPagamento.outro,
          valor: widget.mesaComanda!.couvertPago,
          recebido: true,
          dataRecebimento: widget.mesaComanda!.updatedAt,
          observacao: 'Couvert já pago anteriormente',
        ));
      }
      
      _pagamentosSalvos = listaPagamentos;

      // Sincronizar cliente se houver
      if (widget.mesaComanda!.clienteNome != null) {
        _clienteSelecionado = Cliente(
          id: widget.mesaComanda!.clienteId ?? '',
          nome: widget.mesaComanda!.clienteNome!,
          email: '',
          telefone: '',
          endereco: '',
          tipoPessoa: TipoPessoa.fisica,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
      }
    } else {
      // Carregar cliente inicial se fornecido
      if (widget.clienteInicial != null) {
        _clienteSelecionado = widget.clienteInicial;
        _salvarClienteSelecionado();
      } else {
        // Tentar carregar cliente salvo (assíncrono após o frame)
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _carregarPreferenciasPDV();
        });
      }
      // Carregar itens para repetir venda
      if (widget.itensParaRepetir != null) {
        _carregarItensParaRepetir();
      } else {
        // Tentar carregar carrinho salvo (assíncrono após o frame)
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _carregarCarrinhoSalvo();
        });
      }
    }

    // Registrar handler global na inicialização
    HardwareKeyboard.instance.addHandler(_globalKeyHandler);

    // Listener para scroll infinito no grid de produtos
    _gridScrollController.addListener(() {
      if (_gridScrollController.position.pixels >= _gridScrollController.position.maxScrollExtent - 400) {
        if (_termoBusca.isEmpty) {
           // Só aumenta se não estiver em busca, ou se o total for maior que o visível
           setState(() {
             _itensVisiveisPDV += _itensPorPaginaPDV;
           });
        }
      }
    });
  }

  void _carregarItensParaRepetir() {
    // Carregar produtos
    if (widget.itensParaRepetir != null) {
      for (final item in widget.itensParaRepetir!) {
        _carrinho.add(
          ItemCarrinho(
            id: item.id,
            nome: item.nome,
            preco: item.preco,
            quantidade: item.quantidade,
            isServico: false,
          ),
        );
      }
    }
    // Carregar serviços
    if (widget.servicosParaRepetir != null) {
      for (final servico in widget.servicosParaRepetir!) {
        _carrinho.add(
          ItemCarrinho(
            id: servico.id,
            nome: servico.descricao,
            preco: servico.valor,
            quantidade: 1,
            isServico: true,
          ),
        );
      }
    }
  }

  void _entrarTelaCheia() {
    try {
      if (kIsWeb) {
        if (!html_helper.isFullscreen()) {
          html_helper.requestFullscreen();
        }
      } else {
        // Para mobile/desktop nativo, usar SystemUiMode
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      }
    } catch (e) {
      debugPrint('Erro ao entrar em tela cheia: $e');
    }
  }

  void _toggleTelaCheia() {
    try {
      if (kIsWeb) {
        if (!html_helper.isFullscreen()) {
          html_helper.requestFullscreen();
        } else {
          html_helper.exitFullscreen();
        }
      } else {
        // Toggle básico para mobile nativo (sem usar dart:html)
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      }
      setState(() {});
    } catch (e) {
      debugPrint('Erro ao alternar tela cheia: $e');
    }
  }

  void _carregarPedidoParaEditar(Pedido pedido) {
    _pedidoOriginal = pedido;

    // Carregar pagamentos salvos
    _pagamentosSalvos = List.from(pedido.pagamentos);

    // Carregar observações
    _observacoesVenda = pedido.observacoes;

    // Carregar produtos
    for (final produto in pedido.produtos) {
      _carrinho.add(
        ItemCarrinho(
          id: produto.id,
          nome: produto.nome,
          preco: produto.preco,
          quantidade: produto.quantidade,
          isServico: false,
          observacao: produto.observacao,
        ),
      );
    }

    // Carregar serviços
    for (final servico in pedido.servicos) {
      _carrinho.add(
        ItemCarrinho(
          id: servico.id,
          nome: servico.descricao,
          preco: servico.valor,
          quantidade: 1,
          isServico: true,
          observacao: servico.observacao,
        ),
      );
    }

    // Carregar informações de delivery se existirem
    if (pedido.deliveryInfo != null) {
      _isDelivery = true;
      _taxaEntrega = pedido.deliveryInfo!.taxaEntrega;
      _motoristaId = pedido.deliveryInfo!.motoristaId;
      _motoristaNome = pedido.deliveryInfo!.motoristaNome;
      _valorParaTroco = pedido.deliveryInfo!.valorParaTroco;
      _previsaoEntrega = pedido.deliveryInfo!.previsaoEntrega ?? '';
      _formaPagamentoDelivery = pedido.pagamentos.isNotEmpty ? pedido.pagamentos.first.tipo : null;
      _enderecoEntrega = EnderecoCliente(
        id: pedido.deliveryInfo!.enderecoId,
        tipo: 'Entrega',
        logradouro: pedido.deliveryInfo!.logradouro,
        numero: pedido.deliveryInfo!.numero,
        bairro: pedido.deliveryInfo!.bairro,
        cidade: pedido.deliveryInfo!.cidade,
        uf: pedido.deliveryInfo!.uf,
        cep: pedido.deliveryInfo!.cep ?? '',
      );
    } else {
      _isDelivery = false;
      _enderecoEntrega = null;
      _taxaEntrega = 0.0;
      _motoristaId = null;
      _motoristaNome = null;
    }

    // Carregar cliente se existir
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (pedido.clienteId != null) {
        final dataService = Provider.of<DataService>(context, listen: false);
        final cliente = dataService.clientes
            .where((c) => c.id == pedido.clienteId)
            .firstOrNull;
        if (cliente != null) {
          setState(() => _clienteSelecionado = cliente);
          
          // Se for delivery, tentar encontrar o objeto EnderecoCliente real do cliente
          if (_isDelivery && _enderecoEntrega != null) {
            final enderecoReal = cliente.enderecos
                .where((e) => e.id == _enderecoEntrega!.id)
                .firstOrNull;
            if (enderecoReal != null) {
              setState(() => _enderecoEntrega = enderecoReal);
            }
          }
        }
      } else if (pedido.clienteNome != null && pedido.clienteNome!.isNotEmpty) {
        // Se não tem ID mas tem nome, carregar como identificação para a conclusão
        setState(() => _nomeNfce = pedido.clienteNome);
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _timerFullscreen?.cancel();
    _buscaController.dispose();
    _buscaFocusNode.dispose();
    _atalhosFocusNode.dispose();
    _carrinhoScrollController.dispose();
    _gridScrollController.dispose();
    HardwareKeyboard.instance.removeHandler(_globalKeyHandler);
    super.dispose();
  }

  /// Scrolla o grid para mostrar o item selecionado
  void _scrollToSelectedGridItem(int index, int crossAxisCount, double itemHeight) {
    if (!_gridScrollController.hasClients) return;

    // Caso especial: voltando para categorias
    if (index == -1) {
      _gridScrollController.animateTo(0.0, duration: const Duration(milliseconds: 300), curve: Curves.easeOutQuart);
      return;
    }
    
    final effectiveCrossAxisCount = _viewMode == ViewMode.list ? 1 : crossAxisCount;
    // ALTURA MATEMÁTICA: 82.0 (itemExtent) + 0 (spacing na lista)
    // Se for grade, usamos 82.0 + 4.0 do spacing
    final effectiveItemHeight = _viewMode == ViewMode.list ? 82.0 : 86.0;
    
    // Lazy loading antecipado
    if (_termoBusca.isEmpty && index >= _itensVisiveisPDV - 100) {
      setState(() => _itensVisiveisPDV += 1000); // Carregar blocos maiores (1000)
    }

    final row = index ~/ effectiveCrossAxisCount;
    final scrollPosition = row * effectiveItemHeight; 
    final viewportHeight = _gridScrollController.position.viewportDimension;
    final currentOffset = _gridScrollController.offset;
    
    // Só rola se o item sair da "zona de conforto" (margem de 5px)
    const margin = 5.0;
    if (scrollPosition < (currentOffset + margin) || (scrollPosition + effectiveItemHeight) > (currentOffset + viewportHeight - margin)) {
      final targetScroll = (scrollPosition - (viewportHeight / 2) + (effectiveItemHeight / 2))
          .clamp(0.0, _gridScrollController.position.maxScrollExtent);
          
      _gridScrollController.animateTo(
        targetScroll,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutQuart,
      );
    }
  }

  // ============ Métodos de Persistência do Carrinho ============

  /// Carrega o carrinho salvo do localStorage (isolado por empresa)
  Future<void> _carregarCarrinhoSalvo() async {
    try {
      if (widget.pedidoParaEditar != null) {
        // Não carregar carrinho salvo se estiver editando um pedido
        return;
      }

      // Obter empresa atual para isolar dados do carrinho
      try {
        final dataService = Provider.of<DataService>(context, listen: false);
        _empresaIdStorage = dataService.currentEmpresaId;
      } catch (_) {}

      final carrinhoMap = await _storage.carregarLista(_chavePDV(_keyCarrinhoPDV));
      if (carrinhoMap.isNotEmpty) {
        setState(() {
          _carrinho.clear();
          _carrinho.addAll(carrinhoMap.map((map) => ItemCarrinho.fromMap(map)));
        });
        debugPrint('>>> ✓ Carrinho carregado: ${_carrinho.length} itens');
      }

      // Carregar desconto total
      final descontoTotalMap = await _storage.carregar(_chavePDV(_keyDescontoTotalPDV));
      if (descontoTotalMap != null && descontoTotalMap is double) {
        setState(() {
          _descontoTotal = descontoTotalMap;
        });
      }
    } catch (e) {
      debugPrint('>>> ✗ Erro ao carregar carrinho: $e');
    }
  }

  /// Salva o carrinho atual no localStorage (isolado por empresa)
  Future<void> _salvarCarrinho() async {
    try {
      if (widget.pedidoParaEditar != null) {
        // Não salvar se estiver editando um pedido
        return;
      }

      await _storage.salvarLista(_chavePDV(_keyCarrinhoPDV), _carrinho);
      await _storage.salvar(_chavePDV(_keyDescontoTotalPDV), _descontoTotal);
      debugPrint('>>> ✓ Carrinho salvo: ${_carrinho.length} itens');
    } catch (e) {
      debugPrint('>>> ✗ Erro ao salvar carrinho: $e');
    }
  }

  /// Carrega tabela de preço e cliente salvos no PDV
  Future<void> _carregarPreferenciasPDV() async {
    await _carregarTabelaPreco();
    await _carregarClienteSelecionado();
    if (_tabelaPrecoAtiva == null && _clienteSelecionado?.perfilPreco != null) {
      if (mounted) {
        setState(() => _tabelaPrecoAtiva = _clienteSelecionado!.perfilPreco);
      }
    }
  }

  Future<void> _carregarTabelaPreco() async {
    try {
      final dados = await _storage.carregarLista(_chavePDV(_keyTabelaPrecoPDV));
      if (dados.isNotEmpty) {
        final nome = dados.first['nome'] as String?;
        if (nome != null && nome.isNotEmpty && mounted) {
          setState(() => _tabelaPrecoAtiva = nome);
        }
      }
    } catch (e) {
      debugPrint('>>> ✗ Erro ao carregar tabela de preço: $e');
    }
  }

  Future<void> _salvarTabelaPreco() async {
    try {
      if (_tabelaPrecoAtiva != null && _tabelaPrecoAtiva!.isNotEmpty) {
        await _storage.salvarLista(_chavePDV(_keyTabelaPrecoPDV), [
          {'nome': _tabelaPrecoAtiva},
        ]);
      } else {
        await _storage.salvarLista(_chavePDV(_keyTabelaPrecoPDV), []);
      }
    } catch (e) {
      debugPrint('>>> ✗ Erro ao salvar tabela de preço: $e');
    }
  }

  void _aplicarTabelaPreco(String? tabela) {
    setState(() => _tabelaPrecoAtiva = tabela);
    _salvarTabelaPreco();
    _recalcularPrecosCarrinho();
    if (tabela != null) {
      _mostrarNotificacaoSucesso(
        icone: Icons.price_change,
        titulo: 'Tabela aplicada',
        subtitulo: tabela,
        cor: Colors.orangeAccent,
      );
    }
  }

  /// Carrega o cliente selecionado salvo
  Future<void> _carregarClienteSelecionado() async {
    try {
      if (widget.pedidoParaEditar != null || widget.clienteInicial != null) {
        // Não carregar se já tiver cliente definido
        return;
      }

      final clienteMap = await _storage.carregarLista(_chavePDV(_keyClientePDV));
      if (clienteMap.isNotEmpty) {
        final clienteData = clienteMap.first;
        final clienteId = clienteData['id'] as String?;

        if (clienteId != null) {
          final dataService = Provider.of<DataService>(context, listen: false);
          final cliente = dataService.clientes
              .where((c) => c.id == clienteId)
              .firstOrNull;

          if (cliente != null) {
            setState(() {
              _clienteSelecionado = cliente;
            });
            debugPrint('>>> ✓ Cliente carregado: ${cliente.nome}');
          }
        }
      }
    } catch (e) {
      debugPrint('>>> ✗ Erro ao carregar cliente: $e');
    }
  }

  /// Salva o cliente selecionado no localStorage
  Future<void> _salvarClienteSelecionado() async {
    try {
      if (_clienteSelecionado != null) {
        await _storage.salvarLista(_chavePDV(_keyClientePDV), [
          {'id': _clienteSelecionado!.id},
        ]);
        debugPrint('>>> ✓ Cliente salvo: ${_clienteSelecionado!.nome}');
      } else {
        // Se não há cliente, limpar do storage (salvar lista vazia)
        await _storage.salvarLista(_chavePDV(_keyClientePDV), []);
      }
    } catch (e) {
      debugPrint('>>> ✗ Erro ao salvar cliente: $e');
    }
  }

  /// Limpa o carrinho e cliente salvos (quando finalizar venda) - isolado por empresa
  Future<void> _limparCarrinhoSalvo() async {
    try {
      // Limpar carrinho (salvar lista vazia)
      await _storage.salvarLista(_chavePDV(_keyCarrinhoPDV), []);
      // Limpar cliente (salvar lista vazia)
      await _storage.salvarLista(_chavePDV(_keyClientePDV), []);
      await _storage.salvarLista(_chavePDV(_keyTabelaPrecoPDV), []);
      // Limpar desconto total
      await _storage.salvar(_chavePDV(_keyDescontoTotalPDV), 0.0);
      debugPrint('>>> ✓ Carrinho, cliente e desconto limpos do storage');
    } catch (e) {
      debugPrint('>>> ✗ Erro ao limpar carrinho: $e');
    }
  }

  /// Reseta completamente o estado da venda na interface (limpa carrinho, cliente, seleções e focos)
  void _resetarTodaVenda() {
    setState(() {
      _carrinho.clear();
      // Limpeza completa de todos os caches (PDV e Build)
      _cachedItens = null;
      _cachedCategorias = null;
      _cachedProdutosCategoria = null;
      _ultimoTermoCache = null;
      _ultimaCategoriaCache = null;
      _ultimaAtualizacaoCache = null;
      _cacheProdutosCategoria = [];
      _cacheCategoriaAtiva = null;
      _cacheTotalProdutosPDV = 0;

      _clienteSelecionado = null;
      _tabelaPrecoAtiva = null;
      _descontoTotal = 0.0;
      _observacoesVenda = null;
      _pagamentosSalvos = [];
      _gridSelectedIndex = -1;
      _cartSelectedIndex = -1;
      _categoriaSelectedIndex = -1;
      _categoriaAtiva = null; // Limpa o filtro de categoria (incluindo "Todos")
      _focoNoCarrinho = false;
      _focoNasCategorias = false;
      _quantidadeDigitada = 1;
      _termoBusca = '';
      _pedidoOriginal = null;
      _cpfNfce = null;
      _nomeNfce = null;
      _mesaComandaVinculada = null;
      _isDelivery = false;
      _enderecoEntrega = null;
      _taxaEntrega = 0.0;
      _motoristaId = null;
      _motoristaNome = null;
      _valorParaTroco = 0.0;
      _formaPagamentoDelivery = TipoPagamento.dinheiro;
      _previsaoEntrega = '';
    });
    _buscaController.clear();
    // Limpar storage persistente
    _limparCarrinhoSalvo();
    debugPrint('>>> [VendaDireta] 🔄 ESTADO DA VENDA RESETADO COM SUCESSO. Pronto para próxima operação.');
  }

  /// Limpa a mesa/comanda vinculada salvando no histórico do DataService
  Future<void> _limparMesaComandaVinculada() async {
    if (_mesaComandaVinculada == null) return;
    
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.blueAccent),
            const SizedBox(width: 8),
            Text('Limpar $tipoNome?', style: const TextStyle(color: Colors.white)),
          ],
        ),
        content: Text(
          'Deseja limpar a ${_mesaComandaVinculada!.numero} e salvar o consumo atual no histórico?\n\nIsso irá liberar a $tipoNome para um novo cliente.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
            child: const Text('Limpar e Salvar'),
          ),
        ],
      ),
    );

    if (confirmar == true) {
      try {
        final dataService = Provider.of<DataService>(context, listen: false);
        final authService = Provider.of<AuthService>(context, listen: false);
        
        await dataService.limparMesaComanda(
          _mesaComandaVinculada!.id, 
          usuario: authService.usuarioAtual?.nome,
        );
        
        _resetarTodaVenda();
        
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Mesa limpa e histórico salvo com sucesso!'),
              backgroundColor: Colors.blue,
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Erro ao limpar mesa: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  double get _totalCarrinho {
    final subtotalItens = _carrinho.fold(
      0.0,
      (sum, item) => sum + item.subtotal,
    );
    final total = subtotalItens - _descontoTotal;
    return _isDelivery ? total + _taxaEntrega : total;
  }

  double get _totalCarrinhoSemDesconto {
    final base = _carrinho.fold(0.0, (sum, item) => sum + item.subtotalSemDesconto);
    return _isDelivery ? base + _taxaEntrega : base;
  }

  double get _totalItens =>
      _carrinho.fold(0.0, (sum, item) => sum + item.quantidade);

  void _exibirSelecaoAdicionais(Produto produto, {bool manterFoco = false, String? fornecedorPreSelecionado}) {
    List<AdicionalProduto> selecionados = [];
    final precoBase = produto.precoAtual;
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final totalAdicionais = selecionados.fold(0.0, (sum, a) => sum + a.preco);
          
          return AlertDialog(
            backgroundColor: const Color(0xFF1E293B),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(produto.nome, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                Text('Selecione os adicionais desejados', style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12)),
              ],
            ),
            content: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Consumer<DataService>(
                      builder: (context, dataService, _) {
                        final empresa = dataService.empresaAtual;
                        // Combinar adicionais específicos do produto com os globais da empresa
                        final List<AdicionalProduto> listaExibicao = [...produto.adicionais.where((a) => a.ativo)];
                        
                        if (empresa != null && empresa.modelosAdicionais.isNotEmpty) {
                          for (final modelo in empresa.modelosAdicionais) {
                            final nomeNormalizado = modelo.nome.trim().toLowerCase();
                            if (!listaExibicao.any((a) => a.nome.trim().toLowerCase() == nomeNormalizado)) {
                              listaExibicao.add(modelo);
                            }
                          }
                        }

                        if (listaExibicao.isEmpty) {
                          return Center(
                            child: Padding(
                              padding: const EdgeInsets.all(20.0),
                              child: Text('Nenhum adicional disponível', style: TextStyle(color: Colors.white.withOpacity(0.3))),
                            ),
                          );
                        }

                        return ListView.builder(
                          shrinkWrap: true,
                          itemCount: listaExibicao.length,
                          itemBuilder: (context, index) {
                            final adicional = listaExibicao[index];
                            final qtd = selecionados.where((s) => s.id == adicional.id).length;
                            final estaSelecionado = qtd > 0;
                            
                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              decoration: BoxDecoration(
                                color: estaSelecionado ? Colors.blueAccent.withOpacity(0.1) : Colors.white.withOpacity(0.03),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: estaSelecionado ? Colors.blueAccent : Colors.white.withOpacity(0.05)),
                              ),
                              child: ListTile(
                                dense: true,
                                title: Text(adicional.nome, style: const TextStyle(color: Colors.white, fontSize: 14)),
                                subtitle: Text('+ R\$ ${adicional.preco.toStringAsFixed(2)}', 
                                  style: const TextStyle(color: Colors.greenAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (estaSelecionado) ...[
                                      IconButton(
                                        icon: const Icon(Icons.remove_circle_outline, color: Colors.white38),
                                        onPressed: () {
                                          setDialogState(() {
                                            final idx = selecionados.indexWhere((s) => s.id == adicional.id);
                                            if (idx != -1) selecionados.removeAt(idx);
                                          });
                                        },
                                      ),
                                      Text('$qtd', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                                    ],
                                    IconButton(
                                      icon: Icon(estaSelecionado ? Icons.add_circle : Icons.add_circle_outline, 
                                        color: estaSelecionado ? Colors.blueAccent : Colors.white38),
                                      onPressed: () {
                                        setDialogState(() {
                                          selecionados.add(adicional);
                                        });
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        );
                      }
                    ),
                  ),
                  const Divider(color: Colors.white10, height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Total p/ item:', style: TextStyle(color: Colors.white60)),
                      Text('R\$ ${(precoBase + totalAdicionais).toStringAsFixed(2)}', 
                        style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 16)),
                    ],
                  ),
                ],
              ),
            ),
            actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('CANCELAR', style: TextStyle(color: Colors.white38)),
              ),
              ElevatedButton(
                onPressed: () {
                  // Preço com promoções aplicadas conforme a quantidade digitada.
                  final precoItem = produto.aplicarPromocoes(
                    produto.preco,
                    quantidade: _quantidadeDigitada,
                    subtotalItem: produto.preco * _quantidadeDigitada,
                  );
                  setState(() {
                    _carrinho.add(
                      ItemCarrinho(
                        id: produto.id,
                        nome: produto.nome,
                        descricao: produto.descricao,
                        preco: precoItem,
                        isServico: false,
                        quantidade: _quantidadeDigitada,
                        fornecedorNome: fornecedorPreSelecionado ?? produto.fornecedorNome,
                        observacao: produto.observacaoPadrao,
                        adicionais: List<AdicionalProduto>.from(selecionados),
                        precoSemPromocao: (precoItem < produto.preco - 0.001) ? produto.preco : null,
                      ),
                    );
                  });
                  
                  // Sincronização com Mesa/Comanda se houver
                  if (_mesaComandaVinculada != null) {
                    final dataService = Provider.of<DataService>(context, listen: false);
                    final newItemMc = ItemMesaComanda(
                      id: const Uuid().v4(),
                      itemId: produto.id,
                      nome: produto.nome,
                      quantidade: _quantidadeDigitada,
                      preco: precoItem,
                      isServico: false,
                      paraCozinha: produto.paraCozinha,
                      paraBar: produto.paraBar,
                      local: (produto.departamentoId != null && produto.departamentoId!.isNotEmpty)
                          ? (dataService.nomeDepartamento(produto.departamentoId).isNotEmpty
                              ? dataService.nomeDepartamento(produto.departamentoId)
                              : (produto.paraCozinha == true ? 'Cozinha' : (produto.paraBar == true ? 'Bar' : null)))
                          : (produto.paraCozinha == true ? 'Cozinha' : (produto.paraBar == true ? 'Bar' : null)),
                      status: StatusItem.pendente,
                      observacao: produto.observacaoPadrao,
                      adicionais: List<AdicionalProduto>.from(selecionados),
                      usuarioCriou: Provider.of<AuthService>(context, listen: false).usuarioAtual?.nome ?? 'PDV',
                    );
                    _mesaComandaVinculada = _mesaComandaVinculada!.copyWith(
                      itens: [..._mesaComandaVinculada!.itens, newItemMc],
                    );
                    dataService.updateMesaComanda(_mesaComandaVinculada!);
                  }
                  
                  _mostrarNotificacaoItemAdicionado(
                    nome: produto.nome,
                    quantidade: _quantidadeDigitada,
                    quantidadeTotal: _quantidadeDigitada, 
                    preco: produto.precoAtual + totalAdicionais,
                    jaExistia: false,
                    isServico: false,
                    totalCarrinho: _totalCarrinho,
                  );
                  
                  setState(() => _quantidadeDigitada = 1);
                  if (!manterFoco) {
                    setState(() => _termoBusca = '');
                    _buscaController.clear();
                    _buscaFocusNode.requestFocus();
                  }
                  _salvarCarrinho();
                  
                  // Scroll para o topo para mostrar o novo item (lista invertida)
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (_carrinhoScrollController.hasClients) {
                      _carrinhoScrollController.animateTo(
                        0.0,
                        duration: const Duration(milliseconds: 350),
                        curve: Curves.easeOutQuart,
                      );
                    }
                  });
                  
                  Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('ADICIONAR AO CARRINHO', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
              ),
            ],
          );
        }
      ),
    );
  }

  void _exibirSelecaoFornecedor(Produto produto, {bool manterFoco = false}) {
    debugPrint('>>> [PDV_DEBUG] Abrindo diálogo de fornecedor para: ${produto.nome}');
    // Filtrar fornecedores: remover "Geral" da lista de opções se houver outros
    final opcoes = produto.estoquePorFornecedor.entries
        .where((e) => e.key.trim().toLowerCase() != 'geral')
        .toList();
    
    debugPrint('>>> [PDV_DEBUG] Opções finais: ${opcoes.map((e) => e.key).toList()}');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(produto.nome, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            const Text('Selecione o fornecedor:', style: TextStyle(color: Colors.white54, fontSize: 12)),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ...opcoes.map((entry) {
                final nome = entry.key;
                final qtd = entry.value;
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withOpacity(0.05)),
                  ),
                  child: ListTile(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    title: Text(nome, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                    trailing: Text('$qtd un', style: TextStyle(color: qtd > 0 ? Colors.greenAccent : Colors.redAccent, fontSize: 12)),
                    onTap: () {
                      Navigator.pop(context);
                      if (_deveMostrarAdicionais(produto, Provider.of<DataService>(context, listen: false).empresaAtual)) {
                        _exibirSelecaoAdicionais(produto, manterFoco: manterFoco, fornecedorPreSelecionado: nome);
                      } else {
                        _efetivarAdicaoAoCarrinho(produto, fornecedorNome: nome, manterFoco: manterFoco);
                      }
                    },
                  ),
                );
              }).toList(),
            ],
          ),
        ),
      ),
    );
  }

  void _efetivarAdicaoAoCarrinho(dynamic item, {String? fornecedorNome, bool manterFoco = false, List<OpcaoPerguntaSelecao>? opcoesCombo, double quantidade = 1}) {
    final isServico = item is Servico;
    final id = item.id;
    final nome = item.nome;
    final empresaAtual = Provider.of<DataService>(context, listen: false).empresaAtual;
    final modificadorPerfil = empresaAtual?.getModificadorPerfilValor(_perfilPrecoEfetivo) ?? 0.0;
    final tipoModificador = empresaAtual?.getModificadorPerfilTipo(_perfilPrecoEfetivo) ?? 'desconto';
    
    // Forma de venda selecionada (se veio do diálogo de múltiplas formas)
    final FormaVenda? formaSelecionada = _formaVendaPendente;
    // Reset imediato para não contaminar a próxima adição
    _formaVendaPendente = null;

    // Preço: usa o preço da forma selecionada quando disponível;
    // senão usa o preço inteligente normal do produto.
    double preco = isServico
        ? item.preco
        : (formaSelecionada != null && formaSelecionada.preco > 0)
            ? formaSelecionada.preco
            : (item as Produto).getPrecoInteligente(
                perfilCliente: _perfilPrecoEfetivo,
                modificadorPerfil: modificadorPerfil,
                tipoModificador: tipoModificador,
                quantidade: quantidade,
              );
    final precoBase = preco;

    // Preço de tabela SEM o desconto do perfil de preços — usado para exibir o
    // desconto da tabela no cupom não fiscal e na NFC-e.
    double? precoTabela;
    if (!isServico) {
      final prod = item as Produto;
      if (formaSelecionada != null && formaSelecionada.preco > 0) {
        // Forma de venda com preço próprio: já é o preço de referência (sem perfil)
        precoTabela = formaSelecionada.preco;
      } else {
        // Recalcula o preço SEM o modificador do perfil (mantém regras de quantidade)
        final precoSemPerfil = prod.getPrecoInteligente(
          perfilCliente: null,
          modificadorPerfil: 0.0,
          tipoModificador: 'desconto',
          quantidade: quantidade,
        );
        if (precoSemPerfil > preco + 0.001) {
          precoTabela = precoSemPerfil;
        }
      }
    }

    // Aplica as promoções empilhadas (por data, dia da semana, quantidade ou
    // valor mínimo) usando a quantidade que está sendo adicionada.
    if (!isServico && item is Produto) {
      final qtdPromo = _quantidadeDigitada > 0 ? _quantidadeDigitada : quantidade;
      preco = item.aplicarPromocoes(
        preco,
        quantidade: qtdPromo,
        subtotalItem: preco * qtdPromo,
      );
    }
    // Guarda o preço base (sem promoção) para exibir o desconto na conferência.
    final double? precoSemPromocao = (preco < precoBase - 0.001) ? precoBase : null;
    final descricao = isServico ? null : (item as Produto).descricao;
    final observacao = isServico ? null : (item as Produto).observacaoPadrao;
    final fornecedorId = isServico ? null : (item as Produto).fornecedorId;

    // Se fornecedorNome não foi passado, tenta usar o do produto
    final fNome = fornecedorNome ?? (isServico ? null : (item as Produto).fornecedorNome);

    List<OpcaoPerguntaSelecao>? finalOpcoesCombo = opcoesCombo;
    if (item is Produto && item.ehComposto && item.exibirComposicaoPdv && (finalOpcoesCombo == null || finalOpcoesCombo.isEmpty)) {
      final dataService = Provider.of<DataService>(context, listen: false);
      finalOpcoesCombo = [];
      for (final itemComp in item.composicao) {
        // Buscar nome do ingrediente na lista global de produtos
        final prodIngrediente = dataService.produtos.firstWhere(
          (p) => p.id == itemComp.produtoId,
          orElse: () => null as dynamic, // cast para evitar erro de tipo no orElse
        );
        final nomeIngrediente = prodIngrediente?.nome ?? 'Ingrediente';
        final qtdFormatada = itemComp.quantidade == itemComp.quantidade.roundToDouble()
            ? itemComp.quantidade.toStringAsFixed(0)
            : itemComp.quantidade.toStringAsFixed(2);
        finalOpcoesCombo.add(
          OpcaoPerguntaSelecao(
            id: 'comp_${itemComp.produtoId}_${DateTime.now().microsecondsSinceEpoch}',
            produtoId: itemComp.produtoId,
            nome: '$nomeIngrediente (${qtdFormatada} UN)',
            precoAdicional: 0.0,
            quantidadeBaixa: itemComp.quantidade,
          ),
        );
      }
    }

    // Verificar se já existe no carrinho com MESMO fornecedor
    // Não agrupa itens de combo para manter as seleções separadas no carrinho
    final index = (finalOpcoesCombo != null && finalOpcoesCombo.isNotEmpty) 
        ? -1 
        : _carrinho.indexWhere((c) => c.id == id && c.adicionais.isEmpty && c.opcoesCombo.isEmpty && c.fornecedorNome == fNome);
    final bool jaExistia = index >= 0;

    if (jaExistia) {
      setState(() {
        // Mover item existente para o fim da lista (topo no visual invertido)
        final itemExistente = _carrinho.removeAt(index);
        itemExistente.quantidade += _quantidadeDigitada;
        _carrinho.add(itemExistente);
      });
      // Reavalia as promoções com a quantidade TOTAL do item (regras por
      // quantidade/valor mínimo dependem do subtotal acumulado do carrinho).
      _recalcularPrecosCarrinho();
    } else {
      setState(() {
        _carrinho.add(
          ItemCarrinho(
            id: id,
            nome: nome,
            descricao: descricao,
            preco: preco,
            isServico: isServico,
            quantidade: _quantidadeDigitada,
            fornecedorNome: fNome,
            fornecedorId: fornecedorId,
            observacao: observacao,
            opcoesCombo: finalOpcoesCombo,
            unidadeVenda: formaSelecionada?.tipo,
            quantidadeBaixa: formaSelecionada?.quantidadeBaixa,
            precoSemPromocao: precoSemPromocao,
            precoTabela: precoTabela,
          ),
        );
      });
    }

    _tocarSomPDV('notification.mp3', tipo: 'adicionar');
    _posAdicaoAoCarrinho(item, nome, preco, isServico, jaExistia, index, manterFoco);
  }

  void _posAdicaoAoCarrinho(dynamic item, String nome, double preco, bool isServico, bool jaExistia, int index, bool manterFoco) {
    final id = item.id;
    
    // SICRONIZAÇÃO COM COMANDA/MESA (se houver vínculo)
    if (_mesaComandaVinculada != null) {
      final dataService = Provider.of<DataService>(context, listen: false);
      final newItemMc = ItemMesaComanda(
        id: const Uuid().v4(),
        itemId: id,
        nome: nome,
        quantidade: _quantidadeDigitada,
        preco: preco,
        isServico: isServico,
        paraCozinha: isServico ? false : (item as Produto).paraCozinha,
        paraBar: isServico ? false : (item as Produto).paraBar,
        local: isServico
            ? null
            : ((item as Produto).departamentoId != null && (item as Produto).departamentoId!.isNotEmpty
                ? (dataService.nomeDepartamento((item as Produto).departamentoId).isNotEmpty
                    ? dataService.nomeDepartamento((item as Produto).departamentoId)
                    : ((item as Produto).paraCozinha == true ? 'Cozinha' : ((item as Produto).paraBar == true ? 'Bar' : null)))
                : ((item as Produto).paraCozinha == true ? 'Cozinha' : ((item as Produto).paraBar == true ? 'Bar' : null))),
        status: StatusItem.pendente,
        usuarioCriou: Provider.of<AuthService>(context, listen: false).usuarioAtual?.nome ?? 'PDV',
      );

      _mesaComandaVinculada = _mesaComandaVinculada!.copyWith(
        itens: [..._mesaComandaVinculada!.itens, newItemMc],
        updatedAt: DateTime.now(),
      );
      dataService.updateMesaComanda(_mesaComandaVinculada!);
    }

    // Mostrar notificação inteligente
    final double quantidadeAtual = jaExistia
        ? _carrinho[index].quantidade
        : _quantidadeDigitada;
    _mostrarNotificacaoItemAdicionado(
      nome: nome,
      quantidade: _quantidadeDigitada,
      quantidadeTotal: quantidadeAtual,
      preco: preco,
      jaExistia: jaExistia,
      isServico: isServico,
      totalCarrinho: _totalCarrinho,
    );

    // Resetar quantidade
    setState(() {
      _quantidadeDigitada = 1.0;
      _focoNoCarrinho = false; // Garante que o foco saia do carrinho
    });

    // Sempre limpa e foca na busca após adicionar, a menos que explicitamente solicitado o contrário
    // No contexto do PDV, manterFoco=true geralmente significa que queremos continuar na busca
    setState(() {
      _termoBusca = '';
    });
    _buscaController.clear();
    
    // Força o foco persistente no campo de busca agendando após a renderização do frame
    // e com pequeno delay para garantir o foco mesmo após o fechamento de modais (ex: diálogos de quantidade/fornecedor)
    _buscaFocusNode.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _buscaFocusNode.canRequestFocus) {
        _buscaFocusNode.requestFocus();
      }
    });
    Future.delayed(const Duration(milliseconds: 50), () {
      if (mounted && _buscaFocusNode.canRequestFocus) {
        _buscaFocusNode.requestFocus();
      }
    });

    // Salvar carrinho automaticamente
    _salvarCarrinho();

    // Scroll para o topo para mostrar o novo item (lista invertida)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_carrinhoScrollController.hasClients) {
        _carrinhoScrollController.animateTo(
          0.0,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutQuart,
        );
      }
    });
  }

  /// Exibe o diálogo de escolha da forma de venda quando o produto tem
  /// múltiplas formas (unidade, caixa, pacote, saco).
  void _exibirSelecaoFormaVenda(Produto produto, {bool manterFoco = false}) {
    final formas = produto.formasVendaEfetivas;
    showDialog<FormaVenda>(
      context: context,
      barrierDismissible: true,
      builder: (context) => Dialog(
        backgroundColor: const Color(0xFF1E1E2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          width: 420,
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blueAccent.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.import_export, color: Colors.blueAccent, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'ESCOLHA A FORMA DE VENDA',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        Text(
                          produto.nome.toUpperCase(),
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.5),
                            fontSize: 11,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white38, size: 18),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ...formas.map((forma) {
                IconData icone;
                switch (forma.tipo) {
                  case 'caixa':
                    icone = Icons.inventory_outlined;
                    break;
                  case 'pacote':
                    icone = Icons.widgets_outlined;
                    break;
                  case 'saco':
                    icone = Icons.shopping_bag_outlined;
                    break;
                  default:
                    icone = Icons.inventory_2_outlined;
                }
                final baixaFormatada = forma.quantidadeBaixa == forma.quantidadeBaixa.roundToDouble()
                    ? forma.quantidadeBaixa.toStringAsFixed(0)
                    : forma.quantidadeBaixa.toString();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: InkWell(
                    onTap: () => Navigator.pop(context, forma),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white.withOpacity(0.1)),
                      ),
                      child: Row(
                        children: [
                          Icon(icone, color: Colors.blueAccent, size: 22),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  forma.label,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  forma.vendePorEmbalagem
                                      ? '1 $produtoUnidadeLabel(forma.tipo) = $baixaFormatada unidade(s)'
                                      : 'Venda unitária',
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.5),
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            _formatoMoeda.format(forma.preco > 0 ? forma.preco : produto.preco),
                            style: const TextStyle(
                              color: Colors.cyanAccent,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    ).then((formaSelecionada) {
      if (!mounted || formaSelecionada == null) return;
      _formaVendaPendente = formaSelecionada;
      // Continua o fluxo normal de adição (fornecedor, adicionais, quantidade)
      _adicionarAoCarrinho(produto, manterFoco: manterFoco);
    });
  }

  String produtoUnidadeLabel(String tipo) {
    switch (tipo) {
      case 'caixa':
        return 'caixa';
      case 'pacote':
        return 'pacote';
      case 'saco':
        return 'saco';
      default:
        return 'item';
    }
  }

  void _adicionarAoCarrinho(dynamic item, {bool manterFoco = false}) {
    if (item is! Produto) {
      _efetivarAdicaoAoCarrinho(item, manterFoco: manterFoco);
      return;
    }

    final produto = item as Produto;
    final isServico = item is Servico;

    // INTERCEPTADOR DE COMBOS / PERGUNTAS DE SELEÇÃO
    if (produto.perguntasSelecao.isNotEmpty) {
      showDialog<List<OpcaoPerguntaSelecao>>(
        context: context,
        barrierDismissible: false,
        builder: (context) => PopupPerguntasCombo(produto: produto),
      ).then((opcoes) {
        if (opcoes != null) {
          _efetivarAdicaoAoCarrinho(
            produto,
            manterFoco: manterFoco,
            opcoesCombo: opcoes,
          );
        }
      });
      return;
    }

    // INTERCEPTADOR DE MÚLTIPLAS FORMAS DE VENDA
    // Se o produto é vendido por mais de uma forma (unidade + caixa + pacote +
    // saco), pergunta qual forma usar antes de adicionar. Cada forma tem seu
    // próprio preço e sua própria baixa no estoque.
    // (Só abre o diálogo se ainda não veio de uma seleção — evita loop.)
    if (produto.temMultiplasFormasVenda && _formaVendaPendente == null) {
      _exibirSelecaoFormaVenda(produto, manterFoco: manterFoco);
      return;
    }
    final dataService = Provider.of<DataService>(context, listen: false);
    final empresa = dataService.empresaAtual;
    
    final config = empresa?.configuracoes ?? {};
    final ativarSelecaoFornecedor = config['selecionarFornecedorPDV'] == true;

    // SnackBar temporário para ajudar o usuário a entender por que não aparece
    if (ativarSelecaoFornecedor) {
       debugPrint('>>> [DEBUG_PDV] Coca: ${produto.estoquePorFornecedor}');
    }

    // 1. FORNECEDOR (PRIORIDADE)
    if (ativarSelecaoFornecedor && !isServico && produto.estoquePorFornecedor.isNotEmpty) {
      final opcoesValidas = produto.estoquePorFornecedor.entries
          .where((e) => e.key.trim().toLowerCase() != 'geral')
          .toList();
      
      if (opcoesValidas.length > 1) {
        _exibirSelecaoFornecedor(produto, manterFoco: manterFoco);
        return;
      } else if (opcoesValidas.length == 1) {
        final fornecedor = opcoesValidas.first.key;
        if (_deveMostrarAdicionais(produto, empresa)) {
          _exibirSelecaoAdicionais(produto, manterFoco: manterFoco, fornecedorPreSelecionado: fornecedor);
          return;
        }
        _efetivarAdicaoAoCarrinho(produto, fornecedorNome: fornecedor, manterFoco: manterFoco);
        return;
      }
    }

    // 2. ADICIONAIS
    if (_deveMostrarAdicionais(produto, empresa)) {
      _exibirSelecaoAdicionais(produto, manterFoco: manterFoco);
      return;
    }

    // 3. DIÁLOGO DE QUANTIDADE AUTOMÁTICO (Para produtos fracionáveis: KG, L, M, etc)
    // Se o usuário já digitou uma quantidade na barra de busca (ex: 0,200), respeitamos e não abrimos o dialog.
    final unidadesFracionaveis = [
      'KG', 'KILO', 'KILOS', 'KILOGRAMA', 'KILOGRAMAS', 'G', 'GR', 'GRAMA', 'GRAMAS', 
      'L', 'LT', 'LITRO', 'LITROS', 'ML', 'MILILITRO', 'MILILITROS', 
      'METRO', 'METROS', 'M', 'CM', 'MM'
    ];
    final unidadeProd = produto.unidade.trim().toUpperCase();
    final ehFracionavel = unidadesFracionaveis.contains(unidadeProd) || 
                          unidadeProd.startsWith('KG') || 
                          unidadeProd.startsWith('KIL') || 
                          unidadeProd.startsWith('LIT') ||
                          unidadeProd.startsWith('MET');
    
    debugPrint('>>> [PDV] Adicionando item: ${produto.nome}, Unidade: "$unidadeProd", EhFracionavel: $ehFracionavel, QtdDigitada: $_quantidadeDigitada');

    if (ehFracionavel && _quantidadeDigitada == 1.0) {
      _exibirDialogoQuantidade(produto, manterFoco: manterFoco);
      return;
    }

    _efetivarAdicaoAoCarrinho(item, manterFoco: manterFoco);
  }

  /// Formata a quantidade de baixa de um produto (unidades por embalagem/item vendido)
  String _formatarQtdBaixa(Produto p) {
    final q = p.quantidadeBaixa > 0 ? p.quantidadeBaixa : 1.0;
    return q == q.roundToDouble() ? q.toStringAsFixed(0) : q.toStringAsFixed(2);
  }

  /// Verifica se o produto é composto com pelo menos uma conversão configurada.
  bool _produtoComConversaoComposicao(Produto produto) {
    if (!produto.ehComposto || produto.composicao.isEmpty) return false;
    return produto.composicao.any((c) => c.pesoTotalSaco != null && c.fracaoBase != null);
  }

  /// Texto da conversão de baixa a partir do objeto Produto (para diálogos).
  String _textoConversaoBaixaProduto(Produto produto) {
    for (final c in produto.composicao) {
      if (c.pesoTotalSaco != null && c.fracaoBase != null) {
        final dataService = Provider.of<DataService>(context, listen: false);
        String unIng = c.unidadeBaixa ?? '';
        if (unIng.isEmpty) {
          final pIng = dataService.produtos.cast<Produto?>().firstWhere(
            (p) => p?.id == c.produtoId,
            orElse: () => null,
          );
          if (pIng != null) unIng = pIng.unidade;
        }
        return textoConversao(
          c.fracaoBase!,
          c.pesoTotalSaco!,
          unidadeBaixa: unIng,
          unidadeVenda: c.unidadeVenda ?? produto.unidade,
        );
      }
    }
    return 'conversão configurada';
  }

  /// Exibe um diálogo rápido para digitar a quantidade (ideal para itens pesáveis/fracionados)
  void _exibirDialogoQuantidade(Produto produto, {bool manterFoco = false}) async {
    final TextEditingController qtdController = TextEditingController();
    final focusNode = FocusNode();

    // Carregar configurações locais da balança
    final balancaService = BalancaService();
    final config = await balancaService.obterConfiguracao();
    final bool balancaAtiva = config['ativo'] == true;

    if (!mounted) return;

    bool iniciouLeitura = false;
    bool lendo = false;
    String? statusText;
    bool pesoSimulado = false;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          
          // Função interna para ler da balança
          Future<void> lerDaBalanca() async {
            setDialogState(() {
              lendo = true;
              statusText = "Lendo peso da balança...";
            });
            
            final res = await balancaService.lerPeso();
            final peso = (res['peso'] as num?)?.toDouble() ?? 0.0;
            final simulado = res['simulado'] == true;
            final erro = res['erro'] as String?;
            
            setDialogState(() {
              lendo = false;
              pesoSimulado = simulado;
              if (peso > 0) {
                qtdController.text = peso.toStringAsFixed(3).replaceAll('.', ',');
                statusText = simulado 
                    ? "Peso Simulado: ${peso.toStringAsFixed(3)} kg"
                    : "Peso Lido: ${peso.toStringAsFixed(3)} kg";
                if (erro != null) {
                  statusText = "Simulado: ${peso.toStringAsFixed(3)} kg\n(Porta COM indisponível)";
                }
              } else {
                statusText = erro ?? "Erro ao ler peso da balança.";
              }
            });
          }

          // Auto-iniciar leitura na primeira renderização se ativa
          if (balancaAtiva && !iniciouLeitura) {
            iniciouLeitura = true;
            Future.microtask(() => lerDaBalanca());
          }

          return AlertDialog(
            backgroundColor: const Color(0xFF1A1A2E),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: balancaAtiva ? Colors.tealAccent : Colors.blueAccent, 
                width: 1.5
              ),
            ),
            title: Row(
              children: [
                Icon(
                  balancaAtiva ? Icons.scale_rounded : Icons.edit_note_rounded, 
                  color: balancaAtiva ? Colors.tealAccent : Colors.blueAccent
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Quantidade: ${produto.nome}',
                    style: const TextStyle(color: Colors.white, fontSize: 18),
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      produto.vendePorEmbalagem
                          ? 'Unidade de venda: ${produto.unidadeVendaLabel} (${_formatarQtdBaixa(produto)} un. por ${produto.unidadeVenda})'
                          : 'Unidade: ${produto.unidade.toUpperCase()}',
                      style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 14),
                    ),
                    if (balancaAtiva)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: pesoSimulado ? Colors.orange.withOpacity(0.15) : Colors.teal.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: pesoSimulado ? Colors.orangeAccent : Colors.tealAccent,
                            width: 0.5
                          ),
                        ),
                        child: Text(
                          pesoSimulado ? 'SIMULADOR ATIVO' : 'BALANÇA ONLINE',
                          style: TextStyle(
                            color: pesoSimulado ? Colors.orangeAccent : Colors.tealAccent,
                            fontSize: 10,
                            fontWeight: FontWeight.bold
                          ),
                        ),
                      ),
                  ],
                ),
                // Aviso de conversão de baixa quando o produto é composto com conversão
                // (ex.: vende 1000 ml de chopp → baixa 1 litro no barril)
                if (_produtoComConversaoComposicao(produto))
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.amber.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.amber.withOpacity(0.25)),
                      ),
                      child: Text(
                        '⚖️ Baixa no estoque: ${_textoConversaoBaixaProduto(produto)}',
                        style: const TextStyle(color: Colors.amber, fontSize: 11, height: 1.35),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                const SizedBox(height: 20),
                Stack(
                  alignment: Alignment.centerRight,
                  children: [
                    TextField(
                      controller: qtdController,
                      focusNode: focusNode,
                      autofocus: !balancaAtiva,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                      decoration: InputDecoration(
                        hintText: '0,000',
                        hintStyle: TextStyle(color: Colors.white.withOpacity(0.1)),
                        enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(
                            color: balancaAtiva ? Colors.tealAccent.withOpacity(0.5) : Colors.blueAccent
                          )
                        ),
                        focusedBorder: UnderlineInputBorder(
                          borderSide: BorderSide(
                            color: balancaAtiva ? Colors.tealAccent : Colors.blueAccent, 
                            width: 2
                          )
                        ),
                      ),
                      onSubmitted: (val) {
                        final valor = val.replaceAll(',', '.');
                        final qtd = double.tryParse(valor) ?? 0.0;
                        if (qtd > 0) {
                          Navigator.pop(context);
                          setState(() => _quantidadeDigitada = qtd);
                          _efetivarAdicaoAoCarrinho(produto, manterFoco: manterFoco);
                        }
                      },
                    ),
                    if (lendo)
                      const Positioned(
                        right: 10,
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.tealAccent),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                if (statusText != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      statusText!,
                      style: TextStyle(
                        color: pesoSimulado ? Colors.orangeAccent.withOpacity(0.8) : Colors.white60,
                        fontSize: 12,
                        height: 1.3
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Use vírgula para valores decimais',
                      style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 11),
                    ),
                    if (balancaAtiva) ...[
                      const SizedBox(width: 12),
                      TextButton.icon(
                        onPressed: lendo ? null : () => lerDaBalanca(),
                        icon: const Icon(Icons.refresh, size: 14, color: Colors.tealAccent),
                        label: const Text(
                          'LER NOVAMENTE',
                          style: TextStyle(color: Colors.tealAccent, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('CANCELAR', style: TextStyle(color: Colors.white54)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: balancaAtiva ? Colors.teal : Colors.blueAccent,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () {
                  final valor = qtdController.text.replaceAll(',', '.');
                  final qtd = double.tryParse(valor) ?? 0.0;
                  if (qtd > 0) {
                    Navigator.pop(context);
                    setState(() => _quantidadeDigitada = qtd);
                    _efetivarAdicaoAoCarrinho(produto, manterFoco: manterFoco);
                  }
                },
                child: const Text('ADICIONAR', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );

    // Garantir o foco no campo
    Future.delayed(const Duration(milliseconds: 100), () {
      focusNode.requestFocus();
    });
  }

  bool _deveMostrarAdicionais(Produto produto, Empresa? empresa) {
    if (!produto.temAdicionais) return false;
    
    // Verificar se realmente tem algum adicional para mostrar (produto ou global)
    final especificos = produto.adicionais.where((a) => a.ativo).isNotEmpty;
    final globais = (empresa?.modelosAdicionais ?? []).isNotEmpty;
    
    return especificos || globais;
  }

  /// Verifica se o produto do item tem múltiplas formas de venda cadastradas.
  bool _produtoTemMultiplasFormas(ItemCarrinho item) {
    if (item.isServico) return false;
    final dataService = Provider.of<DataService>(context, listen: false);
    for (final p in dataService.produtos) {
      if (p.id == item.id) {
        return p.temMultiplasFormasVenda;
      }
    }
    return false;
  }

  /// Troca a forma de venda de um item já no carrinho (unidade/caixa/pacote/saco).
  void _trocarFormaVendaItem(int index) {
    final item = _carrinho[index];
    if (item.isServico) return;
    final dataService = Provider.of<DataService>(context, listen: false);
    Produto? produto;
    for (final p in dataService.produtos) {
      if (p.id == item.id) {
        produto = p;
        break;
      }
    }
    if (produto == null) return;
    final produtoAlvo = produto;

    showDialog<FormaVenda>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: const Color(0xFF1E1E2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          width: 420,
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'TROCAR FORMA DE VENDA',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                produtoAlvo.nome.toUpperCase(),
                style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 11),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 14),
              ...produtoAlvo.formasVendaEfetivas.map((forma) {
                IconData icone;
                switch (forma.tipo) {
                  case 'caixa':
                    icone = Icons.inventory_outlined;
                    break;
                  case 'pacote':
                    icone = Icons.widgets_outlined;
                    break;
                  case 'saco':
                    icone = Icons.shopping_bag_outlined;
                    break;
                  default:
                    icone = Icons.inventory_2_outlined;
                }
                final selecionada = forma.tipo == item.unidadeVenda;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: InkWell(
                    onTap: () {
                      // Atualiza o item com a nova forma: preço, baixa e rótulo.
                      // Reconstrói o ItemCarrinho para também atualizar o precoOriginal
                      // (evita exibir "preço alterado/desconto" falso após a troca).
                      final precoBaseForma = forma.preco > 0 ? forma.preco : produtoAlvo.preco;
                      final novoPreco = produtoAlvo.aplicarPromocoes(
                        precoBaseForma,
                        quantidade: item.quantidade,
                        subtotalItem: precoBaseForma * item.quantidade,
                      );
                      final itemAtual = item;
                      setState(() {
                        _carrinho[index] = ItemCarrinho(
                          id: itemAtual.id,
                          nome: itemAtual.nome,
                          descricao: itemAtual.descricao,
                          preco: novoPreco,
                          precoOriginal: novoPreco,
                          quantidade: itemAtual.quantidade,
                          isServico: itemAtual.isServico,
                          desconto: itemAtual.desconto,
                          fornecedorNome: itemAtual.fornecedorNome,
                          fornecedorId: itemAtual.fornecedorId,
                          observacao: itemAtual.observacao,
                          adicionais: itemAtual.adicionais,
                          opcoesCombo: itemAtual.opcoesCombo,
                          isBrinde: itemAtual.isBrinde,
                          baixaProporcional: itemAtual.baixaProporcional,
                          unidadeVenda: forma.tipo,
                          quantidadeBaixa: forma.quantidadeBaixa,
                          precoSemPromocao:
                              (novoPreco < precoBaseForma - 0.001) ? precoBaseForma : null,
                          precoTabela: itemAtual.precoTabela,
                        );
                      });
                      _recalcularPrecosCarrinho();
                      _salvarCarrinho();
                      Navigator.pop(context);
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: selecionada
                            ? Colors.blueAccent.withOpacity(0.2)
                            : Colors.white.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: selecionada
                              ? Colors.blueAccent
                              : Colors.white.withOpacity(0.1),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            icone,
                            color: selecionada ? Colors.blueAccent : Colors.white70,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              forma.label,
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          if (selecionada)
                            const Icon(Icons.check_circle, color: Colors.blueAccent, size: 18)
                          else
                            Text(
                              _formatoMoeda.format(forma.preco > 0 ? forma.preco : produtoAlvo.preco),
                              style: const TextStyle(
                                color: Colors.cyanAccent,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
              const SizedBox(height: 4),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('CANCELAR', style: TextStyle(color: Colors.grey)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _alterarQuantidade(int index, int delta) {
    setState(() {
      _carrinho[index].quantidade += delta;
      
      if (_carrinho[index].quantidade <= 0) {
        _carrinho.removeAt(index);
      }
    });
    
    _recalcularPrecosCarrinho();

    // SICRONIZAÇÃO COM COMANDA/MESA (se houver vínculo)
    if (_mesaComandaVinculada != null) {
      final dataService = Provider.of<DataService>(context, listen: false);
      // Se o item foi removido do carrinho, o index pode ser inválido.
      // Precisamos garantir que o item ainda existe no carrinho antes de tentar acessá-lo.
      // Se o item foi removido, a lógica de remoção já deve ter sido tratada em _removerItem.
      // Aqui, estamos tratando apenas a alteração de quantidade de um item existente.
      if (index >= 0 && index < _carrinho.length) {
        final itemCarrinho = _carrinho[index];

        if (delta > 0) {
          // Se aumentou, adiciona novo lançamento na comanda
          final newItemMc = ItemMesaComanda(
            id: const Uuid().v4(),
            itemId: itemCarrinho.id,
            nome: itemCarrinho.nome,
            quantidade: delta.toDouble(),
            preco: itemCarrinho.preco,
            isServico: itemCarrinho.isServico,
            paraCozinha: itemCarrinho.isServico ? false : dataService.getProdutoById(itemCarrinho.id)?.paraCozinha,
            paraBar: itemCarrinho.isServico ? false : dataService.getProdutoById(itemCarrinho.id)?.paraBar,
            local: itemCarrinho.isServico
                ? null
                : () {
                    final prod = dataService.getProdutoById(itemCarrinho.id);
                    if (prod != null && prod.departamentoId != null && prod.departamentoId!.isNotEmpty) {
                      final nome = dataService.nomeDepartamento(prod.departamentoId);
                      if (nome.isNotEmpty) return nome;
                    }
                    if (prod?.paraCozinha == true) return 'Cozinha';
                    if (prod?.paraBar == true) return 'Bar';
                    return null;
                  }(),
            status: StatusItem.pendente,
            usuarioCriou: Provider.of<AuthService>(context, listen: false).usuarioAtual?.nome ?? 'PDV',
          );

          _mesaComandaVinculada = _mesaComandaVinculada!.copyWith(
            itens: [..._mesaComandaVinculada!.itens, newItemMc],
            updatedAt: DateTime.now(),
          );
        } else {
          // Se diminuiu, temos que "cancelar" um item da comanda
          final itensMc = List<ItemMesaComanda>.from(_mesaComandaVinculada!.itens);
          final itemParaCancelarIndex = itensMc.lastIndexWhere(
            (i) => i.itemId == itemCarrinho.id && i.status != StatusItem.cancelado
          );

          if (itemParaCancelarIndex != -1) {
             final itemParaCanc = itensMc[itemParaCancelarIndex];
             if (itemParaCanc.quantidade > (delta * -1)) {
                itensMc[itemParaCancelarIndex] = itemParaCanc.copyWith(
                  quantidade: itemParaCanc.quantidade + delta, // delta é negativo
                  usuarioModificou: Provider.of<AuthService>(context, listen: false).usuarioAtual?.nome ?? 'PDV',
                  dataModificacao: DateTime.now(),
                );
             } else {
                itensMc[itemParaCancelarIndex] = itemParaCanc.copyWith(
                  status: StatusItem.cancelado,
                  usuarioModificou: Provider.of<AuthService>(context, listen: false).usuarioAtual?.nome ?? 'PDV',
                  dataModificacao: DateTime.now(),
                  acaoRealizada: 'Cancelado via PDV',
                );
             }
             _mesaComandaVinculada = _mesaComandaVinculada!.copyWith(itens: itensMc);
          }
        }
        dataService.updateMesaComanda(_mesaComandaVinculada!);
      }
    }

    // Salvar carrinho automaticamente
    _salvarCarrinho();
  }

  void _scrollToSelectedCartItem(int index) {
    if (index < 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_carrinhoScrollController.hasClients) {
        // Estima altura do item no carrinho: ~105px (card + margem)
        final targetOffset = index * 105.0;
        final currentOffset = _carrinhoScrollController.offset;
        final viewportHeight = 400.0; // Estimativa do container visível do carrinho

        if (targetOffset < currentOffset) {
          _carrinhoScrollController.animateTo(
            targetOffset,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        } else if (targetOffset > currentOffset + viewportHeight - 120) {
          _carrinhoScrollController.animateTo(
            targetOffset - viewportHeight + 120,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      }
    });
  }

  void _removerItem(int index) {
    setState(() {
      final itemRemovido = _carrinho[index];
      _carrinho.removeAt(index);
      
      // SICRONIZAÇÃO COM COMANDA/MESA (se houver vínculo)
      if (_mesaComandaVinculada != null) {
        final dataService = Provider.of<DataService>(context, listen: false);
        final itensMc = List<ItemMesaComanda>.from(_mesaComandaVinculada!.itens);
        
        // Cancela TODOS os lançamentos desse item que não estejam cancelados
        for (var i = 0; i < itensMc.length; i++) {
          if (itensMc[i].itemId == itemRemovido.id && itensMc[i].status != StatusItem.cancelado) {
            itensMc[i] = itensMc[i].copyWith(
              status: StatusItem.cancelado,
              usuarioModificou: Provider.of<AuthService>(context, listen: false).usuarioAtual?.nome ?? 'PDV',
              dataModificacao: DateTime.now(),
              acaoRealizada: 'Removido via PDV',
            );
          }
        }
        
        _mesaComandaVinculada = _mesaComandaVinculada!.copyWith(itens: itensMc);
        dataService.updateMesaComanda(_mesaComandaVinculada!);
      }
    });
    _tocarSomPDV('notification.mp3', tipo: 'remover');
    // Salvar carrinho automaticamente
    _salvarCarrinho();
  }

  void _limparCarrinho() {
    if (_carrinho.isEmpty) return;

    showDialog(
      context: context,
      builder: (context) => Focus(
        autofocus: true,
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;
          if (event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.numpadEnter) {
            _resetarTodaVenda();
            _salvarCarrinho();
            Navigator.pop(context);
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.escape) {
            Navigator.pop(context);
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: AlertDialog(
          backgroundColor: const Color(0xFF1A1A2E),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: const [
              Icon(
                Icons.delete_sweep_rounded,
                color: Colors.redAccent,
                size: 28,
              ),
              SizedBox(width: 12),
              Text('Limpar Carrinho', style: TextStyle(color: Colors.white)),
            ],
          ),
          content: const Text(
            'Deseja realmente remover todos os itens do carrinho?',
            style: TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'CANCELAR',
                style: TextStyle(color: Colors.white54),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () {
                _resetarTodaVenda();
                _salvarCarrinho();
                Navigator.pop(context);
              },
              child: const Text(
                'LIMPAR TUDO',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _aplicarDescontoItem(int index) {
    final item = _carrinho[index];
    final formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final subtotalSemDesconto = item.subtotalSemDesconto;

    final descontoController = TextEditingController(
      text: item.desconto > 0 ? item.desconto.toStringAsFixed(2) : '0.00',
    );
    final descontoPercentualController = TextEditingController(
      text: item.desconto > 0
          ? ((item.desconto / subtotalSemDesconto) * 100).toStringAsFixed(2)
          : '0.00',
    );
    bool usarPercentual = false;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E2E),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              const Icon(
                Icons.discount_rounded,
                color: Colors.orangeAccent,
                size: 28,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Desconto no Item',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  item.nome,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Subtotal: ${formatoMoeda.format(subtotalSemDesconto)}',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: ChoiceChip(
                        label: const Text('Valor (R\$)'),
                        selected: !usarPercentual,
                        onSelected: (selected) {
                          setDialogState(() {
                            usarPercentual = false;
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ChoiceChip(
                        label: const Text('Percentual (%)'),
                        selected: usarPercentual,
                        onSelected: (selected) {
                          setDialogState(() {
                            usarPercentual = true;
                          });
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: usarPercentual
                      ? descontoPercentualController
                      : descontoController,
                  style: const TextStyle(color: Colors.white, fontSize: 18),
                  decoration: InputDecoration(
                    labelText: usarPercentual
                        ? 'Desconto (%)'
                        : 'Desconto (R\$)',
                    labelStyle: const TextStyle(color: Colors.white70),
                    prefixText: usarPercentual ? '' : 'R\$ ',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: Colors.white.withOpacity(0.3),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: Colors.orangeAccent,
                        width: 2,
                      ),
                    ),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.05),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: (value) {
                    setDialogState(() {
                      if (usarPercentual) {
                        final percentual =
                            double.tryParse(value.replaceAll(',', '.')) ?? 0.0;
                        final valorDesconto =
                            (subtotalSemDesconto * percentual) / 100;
                        descontoController.text = valorDesconto.toStringAsFixed(
                          2,
                        );
                      } else {
                        final valor =
                            double.tryParse(value.replaceAll(',', '.')) ?? 0.0;
                        final percentual = subtotalSemDesconto > 0
                            ? (valor / subtotalSemDesconto) * 100
                            : 0.0;
                        descontoPercentualController.text = percentual
                            .toStringAsFixed(2);
                      }
                    });
                  },
                ),
                const SizedBox(height: 12),
                if (usarPercentual)
                  Text(
                    'Valor: ${formatoMoeda.format(double.tryParse(descontoController.text.replaceAll(',', '.')) ?? 0.0)}',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.7),
                      fontSize: 12,
                    ),
                  )
                else
                  Text(
                    'Percentual: ${descontoPercentualController.text}%',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.7),
                      fontSize: 12,
                    ),
                  ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.green.withOpacity(0.3)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Total com desconto:',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                      Text(
                        formatoMoeda.format(
                          subtotalSemDesconto -
                              (double.tryParse(
                                    descontoController.text.replaceAll(
                                      ',',
                                      '.',
                                    ),
                                  ) ??
                                  0.0),
                        ),
                        style: const TextStyle(
                          color: Colors.greenAccent,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                setState(() {
                  _carrinho[index].desconto = 0.0;
                });
                Navigator.pop(dialogContext);
                _salvarCarrinho();
              },
              child: const Text(
                'Remover Desconto',
                style: TextStyle(color: Colors.redAccent),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text(
                'Cancelar',
                style: TextStyle(color: Colors.white54),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                final desconto =
                    double.tryParse(
                      descontoController.text.replaceAll(',', '.'),
                    ) ??
                    0.0;

                if (desconto < 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Desconto não pode ser negativo'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }

                if (desconto > subtotalSemDesconto) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Desconto não pode ser maior que ${formatoMoeda.format(subtotalSemDesconto)}',
                      ),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }

                setState(() {
                  _carrinho[index].desconto = desconto;
                });
                Navigator.pop(dialogContext);
                _salvarCarrinho();

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Desconto de ${formatoMoeda.format(desconto)} aplicado',
                    ),
                    backgroundColor: Colors.green,
                    duration: const Duration(seconds: 2),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orangeAccent,
                foregroundColor: Colors.white,
              ),
              child: const Text('Aplicar'),
            ),
          ],
        ),
      ),
    );
  }

  void _alterarPrecoItem(int index) {
    final authService = Provider.of<AuthService>(context, listen: false);
    final dataService = Provider.of<DataService>(context, listen: false);
    final usuario = authService.usuarioAtual;
    
    // Verifica se tem permissão (master, admin, ou permissão específica)
    final bool temPermissao = usuario?.isMaster == true || 
                             usuario?.isAdmin == true ||
                             usuario?.isGerente == true ||
                             (usuario?.permissoesPersonalizadas?.contains('alterar_preco') == true);
                             
    if (!temPermissao) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Você não tem permissão para alterar o preço do produto.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final item = _carrinho[index];
    
    // Verifica se é fracionável para liberar o campo de Valor Desejado
    bool isFracionavel = false;
    try {
      final produto = dataService.produtos.firstWhere((p) => p.id == item.id);
      final unidade = produto.unidade.trim().toUpperCase();
      isFracionavel = unidade.startsWith('KG') || unidade.startsWith('KIL') || unidade.startsWith('LIT') || unidade.startsWith('MET');
    } catch (_) {}

    final formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final precoController = TextEditingController(
      text: item.preco.toStringAsFixed(2),
    );
    final valorDesejadoController = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: Row(
          children: [
            const Icon(
              Icons.monetization_on_rounded,
              color: Colors.greenAccent,
              size: 28,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Alterar Preço / Quantidade',
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                item.nome,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Preço atual: ${formatoMoeda.format(item.preco)}',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.7),
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: precoController,
                style: const TextStyle(color: Colors.white, fontSize: 18),
                decoration: InputDecoration(
                  labelText: 'Preço Unitário (R\$)',
                  labelStyle: const TextStyle(color: Colors.white70),
                  prefixText: 'R\$ ',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: Colors.white.withOpacity(0.3),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                      color: Colors.greenAccent,
                      width: 2,
                    ),
                  ),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.05),
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
              ),
              if (isFracionavel) ...[
                const SizedBox(height: 20),
                const Divider(color: Colors.white24),
                const SizedBox(height: 10),
                const Text('Ou comprar por valor', style: TextStyle(color: Colors.orangeAccent, fontSize: 14, fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                TextField(
                  controller: valorDesejadoController,
                  style: const TextStyle(color: Colors.white, fontSize: 18),
                  decoration: InputDecoration(
                    labelText: 'Quero gastar (R\$)',
                    labelStyle: const TextStyle(color: Colors.white70),
                    prefixText: 'R\$ ',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: Colors.orangeAccent.withOpacity(0.5),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: Colors.orangeAccent,
                        width: 2,
                      ),
                    ),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.05),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                ),
                const SizedBox(height: 8),
                const Text('A quantidade (peso) será ajustada automaticamente.', style: TextStyle(color: Colors.white54, fontSize: 12), textAlign: TextAlign.center),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text(
              'Cancelar',
              style: TextStyle(color: Colors.white54),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              final novoPreco = double.tryParse(
                precoController.text.replaceAll(',', '.'),
              ) ?? -1.0;
              final valorDesejado = double.tryParse(
                valorDesejadoController.text.replaceAll(',', '.'),
              ) ?? 0.0;

              if (novoPreco < 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Valor inválido.'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }

              setState(() {
                _carrinho[index].preco = novoPreco;
                if (isFracionavel && valorDesejado > 0 && novoPreco > 0) {
                  _carrinho[index].quantidade = valorDesejado / novoPreco;
                }
              });
              Navigator.pop(dialogContext);
              _salvarCarrinho();

              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    isFracionavel && valorDesejado > 0 
                      ? 'Quantidade ajustada para ${_carrinho[index].quantidade.toStringAsFixed(3)} baseada no valor de ${formatoMoeda.format(valorDesejado)}'
                      : 'Preço alterado para ${formatoMoeda.format(novoPreco)}',
                  ),
                  backgroundColor: Colors.green,
                  duration: const Duration(seconds: 3),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.greenAccent,
              foregroundColor: Colors.black,
            ),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
  }

  void _aplicarDescontoTotal() {
    final formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final subtotalSemDesconto = _totalCarrinhoSemDesconto;

    final descontoController = TextEditingController(
      text: _descontoTotal > 0 ? _descontoTotal.toStringAsFixed(2) : '0.00',
    );
    final descontoPercentualController = TextEditingController(
      text: _descontoTotal > 0
          ? ((_descontoTotal / subtotalSemDesconto) * 100).toStringAsFixed(2)
          : '0.00',
    );
    bool usarPercentual = false;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E2E),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              const Icon(
                Icons.discount_rounded,
                color: Colors.orangeAccent,
                size: 28,
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Desconto Total',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Subtotal dos itens: ${formatoMoeda.format(subtotalSemDesconto)}',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: ChoiceChip(
                        label: const Text('Valor (R\$)'),
                        selected: !usarPercentual,
                        onSelected: (selected) {
                          setDialogState(() {
                            usarPercentual = false;
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ChoiceChip(
                        label: const Text('Percentual (%)'),
                        selected: usarPercentual,
                        onSelected: (selected) {
                          setDialogState(() {
                            usarPercentual = true;
                          });
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: usarPercentual
                      ? descontoPercentualController
                      : descontoController,
                  style: const TextStyle(color: Colors.white, fontSize: 18),
                  decoration: InputDecoration(
                    labelText: usarPercentual
                        ? 'Desconto (%)'
                        : 'Desconto (R\$)',
                    labelStyle: const TextStyle(color: Colors.white70),
                    prefixText: usarPercentual ? '' : 'R\$ ',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: Colors.white.withOpacity(0.3),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: Colors.orangeAccent,
                        width: 2,
                      ),
                    ),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.05),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: (value) {
                    setDialogState(() {
                      if (usarPercentual) {
                        final percentual =
                            double.tryParse(value.replaceAll(',', '.')) ?? 0.0;
                        final valorDesconto =
                            (subtotalSemDesconto * percentual) / 100;
                        descontoController.text = valorDesconto.toStringAsFixed(
                          2,
                        );
                      } else {
                        final valor =
                            double.tryParse(value.replaceAll(',', '.')) ?? 0.0;
                        final percentual = subtotalSemDesconto > 0
                            ? (valor / subtotalSemDesconto) * 100
                            : 0.0;
                        descontoPercentualController.text = percentual
                            .toStringAsFixed(2);
                      }
                    });
                  },
                ),
                const SizedBox(height: 12),
                if (usarPercentual)
                  Text(
                    'Valor: ${formatoMoeda.format(double.tryParse(descontoController.text.replaceAll(',', '.')) ?? 0.0)}',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.7),
                      fontSize: 12,
                    ),
                  )
                else
                  Text(
                    'Percentual: ${descontoPercentualController.text}%',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.7),
                      fontSize: 12,
                    ),
                  ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.green.withOpacity(0.3)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Total final:',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                      Text(
                        formatoMoeda.format(
                          subtotalSemDesconto -
                              (double.tryParse(
                                    descontoController.text.replaceAll(
                                      ',',
                                      '.',
                                    ),
                                  ) ??
                                  0.0),
                        ),
                        style: const TextStyle(
                          color: Colors.greenAccent,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                setState(() {
                  _descontoTotal = 0.0;
                });
                await _storage.salvar(_keyDescontoTotalPDV, 0.0);
                Navigator.pop(dialogContext);
              },
              child: const Text(
                'Remover Desconto',
                style: TextStyle(color: Colors.redAccent),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text(
                'Cancelar',
                style: TextStyle(color: Colors.white54),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                final desconto =
                    double.tryParse(
                      descontoController.text.replaceAll(',', '.'),
                    ) ??
                    0.0;

                if (desconto < 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Desconto não pode ser negativo'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }

                if (desconto > subtotalSemDesconto) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Desconto não pode ser maior que ${formatoMoeda.format(subtotalSemDesconto)}',
                      ),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }

                setState(() {
                  _descontoTotal = desconto;
                });
                await _storage.salvar(_keyDescontoTotalPDV, desconto);
                Navigator.pop(dialogContext);

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Desconto total de ${formatoMoeda.format(desconto)} aplicado',
                    ),
                    backgroundColor: Colors.green,
                    duration: const Duration(seconds: 2),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orangeAccent,
                foregroundColor: Colors.white,
              ),
              child: const Text('Aplicar'),
            ),
          ],
        ),
      ),
    );
  }


  List<String> _getCategorias(DataService dataService) {
    final categorias = dataService.produtos
        .map((p) => p.grupo)
        .toSet()
        .toList();
    categorias.sort();
    return categorias;
  }

  int _getGridCrossAxisCount(double screenWidth) {
    if (screenWidth >= 1600) return 6;
    if (screenWidth >= 1200) return 5;
    if (screenWidth >= 900) return 4;
    return 3;
  }

  double _getGridItemAspectRatio(double screenHeight) {
    if (screenHeight < 650) return 2.0;
    if (screenHeight < 750) return 1.8;
    return 1.6;
  }

  List<Produto> _getProdutosPorCategoria(DataService dataService) {
    final totalPerguntas = dataService.produtos.fold<int>(0, (sum, p) => sum + p.perguntasSelecao.length);

    // Se o cache for válido, retorna ele
    if (_cacheProdutosCategoria.isNotEmpty &&
        _cacheCategoriaAtiva == _categoriaAtiva &&
        _cacheSortPDV == _sortOption &&
        _cacheTotalProdutosPDV == dataService.produtos.length &&
        _cacheTotalPerguntasPDV == totalPerguntas) {
      return _cacheProdutosCategoria;
    }

    List<Produto> lista;
    if (_categoriaAtiva == 'Todos') {
      // "Todos" selecionado explicitamente: mostra todos os produtos
      lista = List<Produto>.from(dataService.produtos);
    } else if (_categoriaAtiva == null) {
      // Estado inicial (nulo): nenhuma categoria selecionada - grade vazia
      lista = [];
    } else {
      lista = dataService.produtos
          .where((p) => p.grupo == _categoriaAtiva)
          .toList();
    }
    
    // Aplicar ordenação selecionada
    lista.sort((a, b) {
      switch (_sortOption) {
        case SortOption.nome:
          return a.nome.toLowerCase().compareTo(b.nome.toLowerCase());
        case SortOption.recentes:
          final dateA = a.updatedAt ?? a.createdAt ?? DateTime(2000);
          final dateB = b.updatedAt ?? b.createdAt ?? DateTime(2000);
          return dateB.compareTo(dateA); 
        case SortOption.grupo:
          final grupoCompare = a.grupo.toLowerCase().compareTo(b.grupo.toLowerCase());
          if (grupoCompare != 0) return grupoCompare;
          return a.nome.toLowerCase().compareTo(b.nome.toLowerCase());
        case SortOption.codigo:
        default:
          final numA = int.tryParse(a.codigo?.replaceAll(RegExp(r'[^0-9]'), '') ?? '0') ?? 0;
          final numB = int.tryParse(b.codigo?.replaceAll(RegExp(r'[^0-9]'), '') ?? '0') ?? 0;
          return numA.compareTo(numB);
      }
    });

    // Atualizar cache
    _cacheProdutosCategoria = lista;
    _cacheCategoriaAtiva = _categoriaAtiva;
    _cacheSortPDV = _sortOption;
    _cacheTotalProdutosPDV = dataService.produtos.length;
    _cacheTotalPerguntasPDV = totalPerguntas;
    
    return lista;
  }

  List<dynamic> _buscarItens(DataService dataService, {String? termoOverride}) {
    final termoFinal = (termoOverride ?? _termoBusca).trim();
    if (termoFinal.isEmpty) return [];

    final buscaLower = termoFinal.toLowerCase();
    final ehNumero = RegExp(r'^[0-9]+$').hasMatch(buscaLower);

    // Se for número, mínimo 1 caractere; se for texto, mínimo 2 caracteres
    if (!ehNumero && buscaLower.length < 2) return [];

    // Listas de prioridade
    final exatos = <dynamic>[];
    final parciais = <dynamic>[];
    final nomes = <dynamic>[];

    // Se o termo contiver vírgula, NÃO remove a vírgula para buscar códigos de produto (ex: 10,00 não deve virar código 1000)
    final bool temVirgula = termoFinal.contains(',');
    final queryNumeros = temVirgula ? '' : termoFinal.replaceAll(RegExp(r'[^0-9]'), ''); 
    final queryNumerosSemZeros = queryNumeros.isEmpty
        ? ''
        : int.tryParse(queryNumeros)?.toString() ?? queryNumeros;

    // 1. FILTRAR PRODUTOS
    for (final produto in dataService.produtos) {
      final codigo = (produto.codigo ?? '').trim();
      final codigoLower = codigo.toLowerCase();
      // Todos os códigos de barras (principal + adicionais)
      final todosBarras = produto.todosCodigosBarras;
      final barrasExatoOuPrefixo = todosBarras.any((b) {
        final bLower = b.toLowerCase();
        return b == termoFinal || bLower.startsWith(buscaLower);
      });

      final ehMatchCodigoOuBarras = codigoLower == buscaLower || 
                                     codigoLower == 'cod-$buscaLower' || 
                                     codigo == termoFinal || 
                                     barrasExatoOuPrefixo ||
                                     codigoLower.startsWith(buscaLower) || 
                                     codigoLower.startsWith('cod-$buscaLower');

      final nome = produto.nome.toLowerCase().trim();

      // MATCH EXATO (PRIORIDADE 1)
      if (codigoLower == buscaLower || 
          codigoLower == 'cod-$buscaLower' || 
          codigo == termoFinal || 
          todosBarras.contains(termoFinal)) {
        exatos.add(produto);
        continue;
      }

      // MATCH CÓDIGO PARCIAL (PRIORIDADE 2)
      if (codigoLower.startsWith(buscaLower) || 
          codigoLower.startsWith('cod-$buscaLower') ||
          (queryNumerosSemZeros.isNotEmpty && codigo.contains(queryNumerosSemZeros))) {
        parciais.add(produto);
        continue;
      }

      // MATCH NOME (PRIORIDADE 3)
      if (nome.contains(buscaLower)) {
        nomes.add(produto);
      }
    }

    // 2. FILTRAR SERVIÇOS
    final servicosEncontrados = <dynamic>[];
    for (final servico in dataService.servicos) {
      final nome = servico.nome.toLowerCase();
      if (nome.contains(buscaLower)) {
        servicosEncontrados.add(servico);
      }
    }

    // 3. MONTAR LISTA FINAL (ORDEM DE IMPORTÂNCIA)
    // Ordenamos apenas dentro de cada grupo para manter a lógica
    parciais.sort((a, b) => (a.codigo ?? '').compareTo(b.codigo ?? ''));
    nomes.sort((a, b) => a.nome.compareTo(b.nome));
    servicosEncontrados.sort((a, b) => a.nome.compareTo(b.nome));

    final resultados = <dynamic>[];
    resultados.addAll(exatos);
    resultados.addAll(parciais);
    resultados.addAll(nomes);
    resultados.addAll(servicosEncontrados);

    return resultados;
  }


  void _solicitarAberturaCaixa(BuildContext context, DataService dataService) {
    final valorController = TextEditingController(text: '0.00');
    final formKey = GlobalKey<FormState>();
    final formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

    showDialog(
      context: context,
      barrierDismissible: false, // Não permite fechar sem abrir o caixa
      builder: (dialogContext) => PopScope(
        canPop: false, // Impede fechar com back button
        child: AlertDialog(
          backgroundColor: const Color(0xFF1E1E2E),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    colors: [
                      Colors.green.withOpacity(0.4),
                      Colors.greenAccent.withOpacity(0.2),
                    ],
                  ),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.lock_open_rounded,
                  color: Colors.greenAccent,
                  size: 32,
                ),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Text(
                  'Abrir Caixa',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Para iniciar as vendas, é necessário abrir o caixa.',
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: valorController,
                    style: const TextStyle(color: Colors.white, fontSize: 18),
                    decoration: InputDecoration(
                      labelText: 'Valor Inicial (R\$)',
                      labelStyle: const TextStyle(color: Colors.white70),
                      prefixText: 'R\$ ',
                      prefixStyle: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: Colors.white.withOpacity(0.3),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: Colors.green,
                          width: 2,
                        ),
                      ),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.05),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    autofocus: true,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Informe o valor inicial';
                      }
                      final valor = double.tryParse(
                        value.replaceAll('.', '').replaceAll(',', '.'),
                      );
                      if (valor == null || valor < 0) {
                        return 'Valor inválido';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.blue.withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: Colors.blue.withOpacity(0.8),
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'O valor inicial será usado para calcular o total esperado no fechamento do caixa.',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.7),
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (context) => const HomePage()),
                  (route) => false,
                );
              },
              child: const Text(
                'Fechar',
                style: TextStyle(color: Colors.white54),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                if (formKey.currentState!.validate()) {
                  try {
                    final valor = double.parse(
                      valorController.text
                          .replaceAll('.', '')
                          .replaceAll(',', '.'),
                    );

                    await dataService.abrirCaixaComValor(valor);

                    if (dialogContext.mounted) {
                      Navigator.pop(dialogContext);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Caixa aberto com ${formatoMoeda.format(valor)}',
                          ),
                          backgroundColor: Colors.green,
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  } catch (e) {
                    if (dialogContext.mounted) {
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        SnackBar(
                          content: Text('Erro ao abrir caixa: $e'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 16,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Abrir Caixa',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Realiza a baixa de estoque manual de um item (sem venda financeira)
  Future<void> _darBaixaEstoqueItem(int index) async {
    if (index < 0 || index >= _carrinho.length) return;
    
    final item = _carrinho[index];
    if (item.isServico) return; // Serviços não têm estoque
    
    final descricaoController = TextEditingController();
    final quantidadeController = TextEditingController(text: item.quantidade.toString());

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.inventory_2_outlined, color: Colors.redAccent),
            const SizedBox(width: 12),
            const Text(
              'Baixa de Estoque',
              style: TextStyle(color: Colors.white, fontSize: 18),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Deseja dar baixa manual no produto:',
              style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 14),
            ),
            const SizedBox(height: 8),
            Text(
              item.nome,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 20),
            const Text(
              'Quantidade:',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: quantidadeController,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                filled: true,
                fillColor: Colors.white.withOpacity(0.05),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Motivo / Observação:',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: descricaoController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Ex: Perda, Uso interno...',
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                filled: true,
                fillColor: Colors.white.withOpacity(0.05),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCELAR', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            child: const Text('CONFIRMAR BAIXA'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final qtd = int.tryParse(quantidadeController.text) ?? 0;
      if (qtd <= 0) {
        _mostrarErro('Informe uma quantidade válida para a baixa.');
        return;
      }

      final dataService = Provider.of<DataService>(context, listen: false);
      final authService = Provider.of<AuthService>(context, listen: false);
      final usuario = authService.usuarioAtual;

      // 1. Registrar a saída no estoque sem gerar venda
      await dataService.registrarSaidaEstoque(
        produtoId: item.id, 
        quantidade: qtd.toDouble(),
        motivo: 'Baixa Manual',
        fornecedorNome: item.fornecedorNome,
        observacao: descricaoController.text.trim().isEmpty 
            ? 'Baixa manual realizada via PDV' 
            : descricaoController.text.trim(),
        usuario: usuario?.nome ?? 'Operador',
      );

      // 2. Notificar sucesso
      _mostrarNotificacaoSucesso(
        icone: Icons.inventory_2_outlined,
        titulo: 'BAIXA REALIZADA',
        subtitulo: item.nome,
        info: 'Estoque deduzido em $qtd unidades',
        cor: Colors.redAccent,
      );

      // 3. Remover do carrinho (já "processado")
      _removerItem(index);
    }
  }

  void _adicionarObservacaoItem(int index) async {
    if (index < 0 || index >= _carrinho.length) return;
    final item = _carrinho[index];
    final controller = TextEditingController(text: item.observacao ?? '');

    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.notes_rounded, color: Colors.blueAccent),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Observação: ${item.nome}',
                style: const TextStyle(color: Colors.white, fontSize: 18),
              ),
            ),
          ],
        ),
        content: TextField(
          controller: controller,
          maxLines: 3,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Ex: Sem cebola, gelo e limão...',
            hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
            filled: true,
            fillColor: Colors.white.withOpacity(0.05),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCELAR', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blueAccent,
              foregroundColor: Colors.white,
            ),
            child: const Text('SALVAR'),
          ),
        ],
      ),
    );

    if (result != null) {
      setState(() {
        _carrinho[index].observacao = result.isEmpty ? null : result;
      });
      _salvarCarrinho();
    }
  }

  void _finalizarVenda(DataService dataService) {
    if (_estaFinalizando) return; // Proteção contra múltiplos cliques
    
    if (_carrinho.isEmpty && _mesaComandaVinculada == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Adicione itens ao carrinho'),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.only(
            bottom: MediaQuery.of(context).size.height - 150,
            left: 16,
            right: 16,
          ),
        ),
      );
      return;
    }

    // Verificar se o caixa está aberto antes de finalizar venda
    if (!dataService.caixaAberto) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'É necessário abrir o caixa antes de realizar vendas',
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: 'Abrir',
            textColor: Colors.white,
            onPressed: () {
              _solicitarAberturaCaixa(context, dataService);
            },
          ),
        ),
      );
      return;
    }

    setState(() => _dialogAberto = true);
    _mostrarDialogPagamento(dataService).then((_) {
      if (mounted) setState(() => _dialogAberto = false);
    });
  }

  /// Finalização ultra-rápida em Dinheiro (F10)
  void _finalizarDinheiroDireto(DataService dataService) {
    if (_estaFinalizando) return;
    
    if (_carrinho.isEmpty && _mesaComandaVinculada == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Adicione itens ao carrinho para venda rápida'),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (!dataService.caixaAberto) {
      _solicitarAberturaCaixa(context, dataService);
      return;
    }

    final total = _totalCarrinho;
    final pagamento = PagamentoPedido(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      tipo: TipoPagamento.dinheiro,
      valor: total,
      recebido: true,
      dataRecebimento: DateTime.now(),
      valorRecebido: total,
      troco: 0,
    );

    _concluirVendaComPagamentos(dataService, [pagamento]);
  }


  

  void _recalcularPrecosCarrinho() {
    final dataService = Provider.of<DataService>(context, listen: false);
    final empresaAtual = dataService.empresaAtual;
    final configPerfil = empresaAtual?.getConfigPerfilPreco(_perfilPrecoEfetivo);
    
    final qtdMinima = configPerfil != null && configPerfil['quantidade_minima'] != null 
        ? (configPerfil['quantidade_minima'] as num).toDouble() 
        : 0.0;
        
    final tipoQtdMinima = configPerfil != null && configPerfil['tipo_quantidade_minima'] != null 
        ? configPerfil['tipo_quantidade_minima'] as String
        : 'carrinho';
        
    final descontoPerfil = configPerfil != null && configPerfil['tipo'] == 'desconto'
        ? (configPerfil['valor'] as num?)?.toDouble() ?? 0.0
        : 0.0;
        
    final totalItens = _totalItens;
    
    setState(() {
      for (var item in _carrinho) {
        if (!item.isServico) {
          final prod = dataService.produtos.firstWhere((p) => p.id == item.id, orElse: () => null as dynamic);
          if (prod != null) {
            // Itens com forma de venda selecionada (caixa/pacote/saco) têm preço
            // próprio da forma: recalcula apenas a promoção sobre o preço-base
            // da forma, sem passar pelo getPrecoInteligente (que não conhece a
            // forma) — evita sobrescrever o preço da forma ao mudar quantidades.
            if (item.unidadeVenda != null && item.unidadeVenda!.isNotEmpty) {
              final baseForma = item.precoSemPromocao ?? item.preco;
              item.preco = prod.aplicarPromocoes(
                baseForma,
                quantidade: item.quantidade,
                subtotalItem: baseForma * item.quantidade,
              );
              item.precoSemPromocao = (item.preco < baseForma - 0.001) ? baseForma : null;
              continue;
            }
            
            bool aplicarTabela = false;
            if (qtdMinima <= 0) {
              aplicarTabela = true;
            } else if (tipoQtdMinima == 'carrinho') {
              aplicarTabela = totalItens >= qtdMinima;
            } else { // 'item'
              aplicarTabela = item.quantidade >= qtdMinima;
            }

            final modificadorPerfil = configPerfil != null && (configPerfil['tipo'] == 'desconto' || configPerfil['tipo'] == 'acrescimo')
                ? (configPerfil['valor'] as num?)?.toDouble() ?? 0.0
                : 0.0;
            final tipoModificador = configPerfil != null ? configPerfil['tipo'] as String? ?? 'desconto' : 'desconto';
                
            item.preco = prod.getPrecoInteligente(
              perfilCliente: aplicarTabela ? _perfilPrecoEfetivo : null,
              modificadorPerfil: aplicarTabela ? modificadorPerfil : 0.0,
              tipoModificador: tipoModificador,
              quantidade: item.quantidade,
            );
            final precoBaseRecalc = item.preco;
            // Reaplica as promoções empilhadas conforme a quantidade atual do item.
            item.preco = prod.aplicarPromocoes(
              item.preco,
              quantidade: item.quantidade,
              subtotalItem: item.preco * item.quantidade,
            );
            // Atualiza o preço base (sem promoção) para a conferência.
            item.precoSemPromocao =
                (item.preco < precoBaseRecalc - 0.001) ? precoBaseRecalc : null;
            // Atualiza o preço de tabela (sem o desconto do perfil) para o cupom.
            final precoSemPerfilRecalc = prod.getPrecoInteligente(
              perfilCliente: null,
              modificadorPerfil: 0.0,
              tipoModificador: 'desconto',
              quantidade: item.quantidade,
            );
            item.precoTabela = (precoSemPerfilRecalc > item.preco + 0.001)
                ? precoSemPerfilRecalc
                : null;
          }
        }
      }
    });
  }
  void _selecionarTabelaPreco(DataService dataService) {
    final tabelas = _obterTabelasPrecoEmpresa();
    if (tabelas.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nenhuma tabela de preço cadastrada na empresa.'),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _buildSeletorTabelaPreco(tabelas),
    );
  }

  Widget _buildSeletorTabelaPreco(List<Map<String, dynamic>> tabelas) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.65,
      decoration: const BoxDecoration(
        color: Color(0xFF1E1E2E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                const Icon(Icons.price_change, color: Colors.orangeAccent, size: 28),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Tabela de Preço',
                    style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),
                if (_tabelaPrecoAtiva != null)
                  TextButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _aplicarTabelaPreco(null);
                    },
                    icon: const Icon(Icons.clear, size: 16),
                    label: const Text('Padrão'),
                    style: TextButton.styleFrom(foregroundColor: Colors.white54),
                  ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'Escolha a tabela para aplicar nos preços do carrinho. Ao selecionar um cliente, a tabela dele é aplicada automaticamente.',
              style: TextStyle(color: Colors.white54, fontSize: 13),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              children: [
                ListTile(
                  leading: Icon(
                    Icons.storefront,
                    color: _tabelaPrecoAtiva == null ? Colors.blueAccent : Colors.white38,
                  ),
                  title: Text(
                    'Padrão (preço de venda)',
                    style: TextStyle(
                      color: _tabelaPrecoAtiva == null ? Colors.blueAccent : Colors.white,
                      fontWeight: _tabelaPrecoAtiva == null ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  subtitle: const Text(
                    'Sem tabela de preço aplicada',
                    style: TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                  trailing: _tabelaPrecoAtiva == null
                      ? const Icon(Icons.check_circle, color: Colors.blueAccent)
                      : null,
                  onTap: () {
                    Navigator.pop(context);
                    _aplicarTabelaPreco(null);
                  },
                ),
                const Divider(color: Colors.white12),
                ...tabelas.map((config) {
                  final nome = config['nome'] as String;
                  final selecionada = _tabelaPrecoAtiva == nome;
                  final tipo = config['tipo'] as String? ?? 'fixo';
                  final corTipo = tipo == 'desconto'
                      ? Colors.greenAccent
                      : (tipo == 'acrescimo' ? Colors.redAccent : Colors.orangeAccent);

                  return Card(
                    color: selecionada ? Colors.orangeAccent.withOpacity(0.12) : Colors.white.withOpacity(0.05),
                    margin: const EdgeInsets.only(bottom: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: selecionada ? Colors.orangeAccent : Colors.transparent,
                      ),
                    ),
                    child: ListTile(
                      leading: Icon(Icons.price_change, color: corTipo),
                      title: Text(
                        nome,
                        style: TextStyle(
                          color: selecionada ? Colors.orangeAccent : Colors.white,
                          fontWeight: selecionada ? FontWeight.bold : FontWeight.w500,
                        ),
                      ),
                      subtitle: Text(
                        _descricaoTipoTabelaPDV(config),
                        style: TextStyle(color: corTipo.withOpacity(0.9), fontSize: 12),
                      ),
                      trailing: selecionada
                          ? const Icon(Icons.check_circle, color: Colors.orangeAccent)
                          : const Icon(Icons.chevron_right, color: Colors.white24),
                      onTap: () {
                        Navigator.pop(context);
                        _aplicarTabelaPreco(nome);
                      },
                    ),
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _selecionarCliente(DataService dataService) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _buildSeletorCliente(dataService),
    );
  }

  void _selecionarVendedor(DataService dataService) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _buildSeletorVendedor(dataService),
    );
  }

  Widget _buildSeletorVendedor(DataService dataService) {
    final vendedores = dataService.funcionarios.where((f) => f.ativo).toList();

    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      decoration: const BoxDecoration(
        color: Color(0xFF1E1E2E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Selecionar Vendedor',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          if (_vendedorSelecionado != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ElevatedButton.icon(
                onPressed: () {
                  setState(() => _vendedorSelecionado = null);
                  Navigator.pop(context);
                },
                icon: const Icon(Icons.clear),
                label: const Text('Remover Vendedor Atual'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 48),
                ),
              ),
            ),
          const SizedBox(height: 8),
          Expanded(
            child: vendedores.isEmpty
                ? const Center(
                    child: Text(
                      'Nenhum vendedor encontrado.',
                      style: TextStyle(color: Colors.white54),
                    ),
                  )
                : ListView.builder(
                    itemCount: vendedores.length,
                    itemBuilder: (context, index) {
                      final func = vendedores[index];
                      final isSelected = _vendedorSelecionado?.id == func.id;
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: isSelected ? Colors.purpleAccent : Colors.grey[800],
                          child: Icon(Icons.person, color: isSelected ? Colors.white : Colors.white54),
                        ),
                        title: Text(func.nome, style: const TextStyle(color: Colors.white)),
                        subtitle: Text(
                          func.porcentagemComissao > 0 
                            ? 'Comissão: ${func.porcentagemComissao}%' 
                            : 'Sem comissão definida',
                          style: const TextStyle(color: Colors.white54, fontSize: 12),
                        ),
                        trailing: isSelected ? const Icon(Icons.check, color: Colors.purpleAccent) : null,
                        onTap: () {
                          setState(() => _vendedorSelecionado = func);
                          Navigator.pop(context);
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  void _abrirLancamentoDespesa() {
    final descricaoController = TextEditingController();
    final valorController = TextEditingController();
    final responsavelController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    // Estados do diálogo
    int abaAtiva = 0; // 0: Novo Lançamento, 1: Contas Pendentes
    String tipoLancamento = 'Dinheiro do Caixa'; // 'Dinheiro do Caixa' ou 'Contas a Pagar'
    String statusContaPagar = 'Pendente'; // 'Pendente' ou 'Pago'
    bool tirarDoCaixaSePago = true;
    DateTime dataVencimentoSelecionada = DateTime.now();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final dataService = Provider.of<DataService>(context, listen: false);
          
          return AlertDialog(
            backgroundColor: const Color(0xFF1E1E2E),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            contentPadding: EdgeInsets.zero,
            title: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      abaAtiva == 0 ? Icons.money_off : Icons.receipt_long, 
                      color: Colors.redAccent
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    abaAtiva == 0 ? 'Lançar Despesa' : 'Contas Pendentes',
                    style: const TextStyle(color: Colors.white, fontSize: 20),
                  ),
                ],
              ),
            ),
            content: SizedBox(
              width: 500,
              height: 550,
              child: Column(
                children: [
                  // Tabs
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 20),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () => setDialogState(() => abaAtiva = 0),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                color: abaAtiva == 0 ? Colors.blueAccent : Colors.transparent,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Center(
                                child: Text(
                                  'NOVO LANÇAMENTO',
                                  style: TextStyle(
                                    color: Colors.white, 
                                    fontSize: 12, 
                                    fontWeight: FontWeight.bold
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: InkWell(
                            onTap: () => setDialogState(() => abaAtiva = 1),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                color: abaAtiva == 1 ? Colors.blueAccent : Colors.transparent,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Center(
                                child: Text(
                                  'CONTAS PENDENTES',
                                  style: TextStyle(
                                    color: Colors.white, 
                                    fontSize: 12, 
                                    fontWeight: FontWeight.bold
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  
                  Expanded(
                    child: abaAtiva == 0 
                      ? _buildFormNovoLancamento(
                          formKey, 
                          descricaoController, 
                          valorController, 
                          responsavelController, 
                          tipoLancamento, 
                          statusContaPagar, 
                          tirarDoCaixaSePago,
                          dataVencimentoSelecionada,
                          (tipo) => setDialogState(() => tipoLancamento = tipo),
                          (status) => setDialogState(() => statusContaPagar = status),
                          (v) => setDialogState(() => tirarDoCaixaSePago = v),
                          (data) => setDialogState(() => dataVencimentoSelecionada = data),
                        )
                      : _buildListaContasPendentes(dataService, setDialogState),
                  ),
                ],
              ),
            ),
            actionsPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('FECHAR', style: TextStyle(color: Colors.white54)),
              ),
              if (abaAtiva == 0) ...[
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () async {
                    if (!formKey.currentState!.validate()) return;
                    
                    final valor = double.parse(valorController.text.replaceAll(',', '.'));
                    final descricao = descricaoController.text.trim();
                    final responsavel = responsavelController.text.trim();
                    
                    try {
                      if (tipoLancamento == 'Dinheiro do Caixa') {
                        if (dataService.aberturaCaixaAtual == null) {
                          throw Exception('O caixa precisa estar aberto para pagar com dinheiro do dia.');
                        }
                        await dataService.registrarSangria(
                          valor: valor,
                          motivo: '[PAGAMENTO] $descricao',
                          responsavel: responsavel.isNotEmpty ? responsavel : null,
                        );
                      } else {
                        final novaConta = ContaPagar(
                          id: DateTime.now().millisecondsSinceEpoch.toString(),
                          tipo: TipoContaPagar.despesaVariavel,
                          descricao: descricao,
                          valor: valor,
                          dataVencimento: dataVencimentoSelecionada,
                          status: statusContaPagar == 'Pago' ? StatusContaPagar.pago : StatusContaPagar.pendente,
                          dataPagamento: statusContaPagar == 'Pago' ? DateTime.now() : null,
                          valorPago: statusContaPagar == 'Pago' ? valor : 0,
                          formaPagamento: statusContaPagar == 'Pago' ? 'Dinheiro' : null,
                          usuarioCriacao: responsavel,
                        );
                        await dataService.addContaPagar(novaConta);
                        
                        if (statusContaPagar == 'Pago' && tirarDoCaixaSePago) {
                          if (dataService.aberturaCaixaAtual != null) {
                            await dataService.registrarSangria(
                              valor: valor,
                              motivo: '[PAGAMENTO] Despesa: $descricao',
                              responsavel: responsavel.isNotEmpty ? responsavel : null,
                            );
                          }
                        }
                      }
                      
                      if (context.mounted) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Sucesso: $tipoLancamento registrado.')),
                        );
                      }
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.redAccent),
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: tipoLancamento == 'Dinheiro do Caixa' ? Colors.redAccent : Colors.blueAccent,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: Text(
                    tipoLancamento == 'Dinheiro do Caixa' ? 'PAGAR COM CAIXA' : 'LANÇAR CONTA',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildFormNovoLancamento(
    GlobalKey<FormState> formKey,
    TextEditingController descricaoController,
    TextEditingController valorController,
    TextEditingController responsavelController,
    String tipoLancamento,
    String statusContaPagar,
    bool tirarDoCaixaSePago,
    DateTime dataVencimento,
    Function(String) onTypeChanged,
    Function(String) onStatusChanged,
    Function(bool) onTirarDoCaixaChanged,
    Function(DateTime) onDataChanged,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Form(
        key: formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Escolha a forma de lançamento para esta despesa.',
              style: TextStyle(color: Colors.white54, fontSize: 13),
            ),
            const SizedBox(height: 20),
            
            Row(
              children: [
                Expanded(
                  child: _buildTipoOption(
                    'Pagar com Dinheiro do Caixa', 
                    Icons.account_balance_wallet, 
                    tipoLancamento == 'Dinheiro do Caixa',
                    () => onTypeChanged('Dinheiro do Caixa'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildTipoOption(
                    'Lançar Conta (Fora do Caixa)', 
                    Icons.receipt_long, 
                    tipoLancamento == 'Contas a Pagar',
                    () => onTypeChanged('Contas a Pagar'),
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 20),

            if (tipoLancamento == 'Contas a Pagar') ...[
              const Text('Data de Vencimento', style: TextStyle(color: Colors.white70, fontSize: 12)),
              const SizedBox(height: 8),
              InkWell(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: dataVencimento,
                    firstDate: DateTime.now().subtract(const Duration(days: 365)),
                    lastDate: DateTime.now().add(const Duration(days: 3650)),
                    builder: (context, child) {
                      return Theme(
                        data: ThemeData.dark().copyWith(
                          colorScheme: const ColorScheme.dark(
                            primary: Colors.blueAccent,
                            onPrimary: Colors.white,
                            surface: Color(0xFF1E1E2E),
                            onSurface: Colors.white,
                          ),
                          dialogBackgroundColor: const Color(0xFF1E1E2E),
                        ),
                        child: child!,
                      );
                    },
                  );
                  if (picked != null) onDataChanged(picked);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today, color: Colors.blueAccent, size: 20),
                      const SizedBox(width: 12),
                      Text(
                        DateFormat('dd / MM / yyyy').format(dataVencimento),
                        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const Spacer(),
                      const Icon(Icons.edit, color: Colors.white24, size: 16),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            TextFormField(
              controller: descricaoController,
              style: const TextStyle(color: Colors.white),
              decoration: _inputDecoration('Descrição / Motivo', Icons.description),
              validator: (v) => v == null || v.isEmpty ? 'Informe a descrição' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: valorController,
              style: const TextStyle(color: Colors.white),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: _inputDecoration('Valor (R\$)', Icons.attach_money),
              validator: (v) {
                if (v == null || v.isEmpty) return 'Informe o valor';
                final val = double.tryParse(v.replaceAll(',', '.'));
                if (val == null || val <= 0) return 'Valor inválido';
                return null;
              },
            ),
            
            if (tipoLancamento == 'Contas a Pagar') ...[
              const SizedBox(height: 20),
              const Divider(color: Colors.white10),
              const SizedBox(height: 10),
              const Text('Status da Conta', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildStatusChip(
                      'Pendente', 
                      statusContaPagar == 'Pendente',
                      () => onStatusChanged('Pendente'),
                      Colors.orange,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildStatusChip(
                      'Pago', 
                      statusContaPagar == 'Pago',
                      () => onStatusChanged('Pago'),
                      Colors.green,
                    ),
                  ),
                ],
              ),
              if (statusContaPagar == 'Pago') ...[
                const SizedBox(height: 12),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Tirar dinheiro do caixa?', style: TextStyle(color: Colors.white70, fontSize: 14)),
                  value: tirarDoCaixaSePago,
                  onChanged: (v) => onTirarDoCaixaChanged(v ?? false),
                  activeColor: Colors.blueAccent,
                  checkColor: Colors.white,
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                ),
              ],
            ],
            
            const SizedBox(height: 16),
            TextFormField(
              controller: responsavelController,
              style: const TextStyle(color: Colors.white),
              decoration: _inputDecoration('Responsável (Opcional)', Icons.person_outline),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildListaContasPendentes(DataService dataService, StateSetter setDialogState) {
    final contasPendentes = dataService.contasPagar
        .where((c) => c.status == StatusContaPagar.pendente)
        .toList()
      ..sort((a, b) => a.dataVencimento.compareTo(b.dataVencimento));

    if (contasPendentes.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_outline, color: Colors.green.withOpacity(0.2), size: 80),
            const SizedBox(height: 16),
            const Text(
              'Tudo em dia!', 
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)
            ),
            const Text(
              'Nenhuma conta pendente encontrada.', 
              style: TextStyle(color: Colors.white54, fontSize: 14)
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: contasPendentes.length,
      itemBuilder: (context, index) {
        final conta = contasPendentes[index];
        final hoje = DateTime.now();
        final vencida = conta.dataVencimento.isBefore(DateTime(hoje.year, hoje.month, hoje.day));

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.03),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: vencida ? Colors.red.withOpacity(0.3) : Colors.white.withOpacity(0.08),
            ),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.all(12),
            leading: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: (vencida ? Colors.red : Colors.orange).withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                vencida ? Icons.warning_amber_rounded : Icons.receipt_long, 
                color: vencida ? Colors.redAccent : Colors.orange, 
                size: 24
              ),
            ),
            title: Text(
              conta.descricao,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text(
                  'Vencimento: ${DateFormat('dd/MM/yyyy').format(conta.dataVencimento)}',
                  style: TextStyle(
                    color: vencida ? Colors.redAccent : Colors.white54, 
                    fontSize: 12,
                    fontWeight: vencida ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                if (vencida)
                  const Text(
                    'CONTA VENCIDA',
                    style: TextStyle(color: Colors.redAccent, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
              ],
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'R\$ ${conta.valor.toStringAsFixed(2)}',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 6),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => _baixarContaPagarDialog(dataService, conta),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.green.withOpacity(0.3)),
                      ),
                      child: const Text(
                        'PAGAR',
                        style: TextStyle(color: Colors.greenAccent, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white54),
      prefixIcon: Icon(icon, color: Colors.white54),
      filled: true,
      fillColor: Colors.white.withOpacity(0.05),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
    );
  }

  void _baixarContaPagarDialog(DataService dataService, ContaPagar conta) {
    bool tirarDoCaixa = true;
    final authService = Provider.of<AuthService>(context, listen: false);

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setSubDialogState) => Dialog(
          backgroundColor: const Color(0xFF1E1E2E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: Container(
            padding: const EdgeInsets.all(24),
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.check_circle_outline, color: Colors.greenAccent),
                    ),
                    const SizedBox(width: 16),
                    const Text(
                      'Baixar Conta',
                      style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                const Text(
                  'Confirmar pagamento de:',
                  style: TextStyle(color: Colors.white54, fontSize: 14),
                ),
                const SizedBox(height: 8),
                Text(
                  conta.descricao,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20),
                ),
                const SizedBox(height: 4),
                Text(
                  'Valor: R\$ ${conta.valor.toStringAsFixed(2)}',
                  style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 18),
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          'Registrar saída do caixa?', 
                          style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)
                        ),
                        subtitle: const Text(
                          'O dinheiro será retirado do saldo do dia.',
                          style: TextStyle(color: Colors.white54, fontSize: 12),
                        ),
                        value: tirarDoCaixa,
                        onChanged: (v) => setSubDialogState(() => tirarDoCaixa = v ?? false),
                        activeColor: Colors.blueAccent,
                        checkColor: Colors.white,
                        dense: true,
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.pop(context),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('CANCELAR', style: TextStyle(color: Colors.white54, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        onPressed: () async {
                          try {
                            // Atualizar conta como paga
                            final contaAtualizada = conta.copyWith(
                              status: StatusContaPagar.pago,
                              dataPagamento: DateTime.now(),
                              valorPago: conta.valor,
                              formaPagamento: 'Dinheiro',
                            );
                            
                            await dataService.updateContaPagar(contaAtualizada);
                            
                            // Se tirar do caixa
                            if (tirarDoCaixa) {
                              if (dataService.aberturaCaixaAtual == null) {
                                throw Exception('O caixa precisa estar aberto para registrar a saída.');
                              }
                              await dataService.registrarSangria(
                                valor: conta.valor,
                                motivo: '[PAGAMENTO] Baixa conta: ${conta.descricao}',
                                responsavel: authService.usuarioAtual?.nome ?? 'Sistema',
                              );
                            }
                            
                            if (context.mounted) {
                              Navigator.pop(context); // Fecha dialog de confirmação
                              Navigator.pop(context); // Fecha dialog de despesa
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('✓ Conta baixada com sucesso!'), 
                                  backgroundColor: Colors.green,
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            }
                          } catch (e) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Erro: $e'), 
                                backgroundColor: Colors.redAccent,
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text(
                          'CONFIRMAR PAGAMENTO',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }


  Widget _buildTipoOption(String label, IconData icon, bool selected, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: selected ? Colors.blueAccent.withOpacity(0.2) : Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? Colors.blueAccent : Colors.transparent,
            width: 2,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, color: selected ? Colors.blueAccent : Colors.white54, size: 32),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : Colors.white54,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusChip(String label, bool selected, VoidCallback onTap, Color color) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.2) : Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? color : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: selected ? color : Colors.white54,
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  void _editarCliente(DataService dataService, Cliente cliente) async {
    final resultado = await Navigator.push<Cliente>(
      context,
      MaterialPageRoute(
        builder: (context) => ClienteDetalhesPage(cliente: cliente),
      ),
    );

    if (resultado != null) {
      setState(() {
        _clienteSelecionado = resultado;
        if (resultado.perfilPreco != null && resultado.perfilPreco!.isNotEmpty) {
          _tabelaPrecoAtiva = resultado.perfilPreco;
        }
      });
      _salvarClienteSelecionado();
      _salvarTabelaPreco();
      _recalcularPrecosCarrinho();
    } else {
      // Pode ter sido excluído, verifica se ainda existe
      final existe = dataService.clientes.any((c) => c.id == cliente.id);
      if (!existe) {
        setState(() {
          _clienteSelecionado = null;
        });
        _salvarClienteSelecionado();
      }
    }
  }

  void _abrirHistoricoNFCe() {
    final authService = Provider.of<AuthService>(context, listen: false);
    final empresa = authService.empresaAtual;
    if (empresa == null) return;
    
    showDialog(
      context: context,
      builder: (context) => HistoricoNFCePDVDialog(empresa: empresa),
    );
  }

  void _abrirHistoricoVendas() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const HistoricoVendasPage()),
    );
  }

  void _abrirPedidos() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const PedidosPage()),
    );
  }

  void _abrirDialogPagamento() {
    final dataService = Provider.of<DataService>(context, listen: false);

    if (!dataService.caixaAberto) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('É necessário abrir o caixa antes de fazer um pagamento'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final valorController = TextEditingController();
    final motivoController = TextEditingController();
    final observacaoController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: Row(
          children: [
            Icon(Icons.remove_circle_outline, color: Colors.red),
            const SizedBox(width: 8),
            const Text(
              'Pagamento do Caixa',
              style: TextStyle(color: Colors.white),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: valorController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                ],
                decoration: InputDecoration(
                  labelText: 'Valor (R\$)',
                  labelStyle: const TextStyle(color: Colors.white70),
                  prefixIcon: const Icon(Icons.attach_money, color: Colors.red),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.red),
                  ),
                ),
                style: const TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: motivoController,
                decoration: InputDecoration(
                  labelText: 'Motivo *',
                  labelStyle: const TextStyle(color: Colors.white70),
                  prefixIcon: const Icon(Icons.description, color: Colors.red),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.red),
                  ),
                ),
                style: const TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: observacaoController,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: 'Observação (opcional)',
                  labelStyle: const TextStyle(color: Colors.white70),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.red),
                  ),
                ),
                style: const TextStyle(color: Colors.white),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Cancelar',
              style: TextStyle(color: Colors.white70),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              final valor = double.tryParse(valorController.text);
              final motivo = motivoController.text.trim();

              if (valor == null || valor <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Informe um valor válido'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }

              if (motivo.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Informe o motivo do pagamento'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }

              // Calcular saldo disponível no caixa
              final abertura = dataService.aberturaCaixaAtual;
              if (abertura == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Não há caixa aberto'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }

              // Calcular saldo atual: valor inicial + vendas - sangrias + suprimentos
              final vendasDoCaixa = dataService.vendasBalcao
                  .where(
                    (v) =>
                        !v.isCancelada &&
                        v.dataVenda.isAfter(abertura.dataAbertura),
                  )
                  .fold(0.0, (sum, v) {
                    final tiposParcelaveis = [
                      TipoPagamento.crediario,
                      TipoPagamento.boleto,
                    ];
                    if (tiposParcelaveis.contains(v.tipoPagamento)) {
                      return sum + (v.valorRecebido ?? 0);
                    }
                    return sum + v.valorTotal;
                  });

              final sangriasAtuais = dataService.getSangriasCaixaAtual().fold(
                0.0,
                (sum, s) => sum + s.valor,
              );

              final suprimentosAtuais = dataService
                  .getSuprimentosCaixaAtual()
                  .fold(0.0, (sum, s) => sum + s.valor);

              final saldoDisponivel =
                  abertura.valorInicial +
                  vendasDoCaixa -
                  sangriasAtuais +
                  suprimentosAtuais;

              if (valor > saldoDisponivel) {
                final formatoMoeda = NumberFormat.currency(
                  locale: 'pt_BR',
                  symbol: 'R\$',
                );
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Saldo insuficiente! Disponível: ${formatoMoeda.format(saldoDisponivel)}',
                    ),
                    backgroundColor: Colors.red,
                    duration: const Duration(seconds: 3),
                  ),
                );
                return;
              }

              try {
                await dataService.registrarSangria(
                  valor: valor,
                  motivo: motivo,
                  observacao: observacaoController.text.trim().isEmpty
                      ? null
                      : observacaoController.text.trim(),
                );

                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Sangria de R\$ ${valor.toStringAsFixed(2)} registrada com sucesso',
                    ),
                    backgroundColor: Colors.green,
                  ),
                );
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Erro ao registrar pagamento: $e'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Confirmar Pagamento'),
          ),
        ],
      ),
    );
  }

  void _abrirDialogObservacoes() {
    final observacoesController = TextEditingController(
      text: _observacoesVenda ?? '',
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.note_outlined,
                color: Colors.blueAccent,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Observações da Venda',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Adicione observações sobre esta venda (opcional)',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: observacoesController,
                maxLines: 6,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText:
                      'Ex: Cliente solicitou entrega, produto com garantia estendida, etc.',
                  hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.05),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: Colors.white.withOpacity(0.2),
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: Colors.white.withOpacity(0.2),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                      color: Colors.blueAccent,
                      width: 2,
                    ),
                  ),
                  contentPadding: const EdgeInsets.all(16),
                ),
              ),
            ],
          ),
        ),
        actions: [
          if (_observacoesVenda != null && _observacoesVenda!.isNotEmpty)
            TextButton(
              onPressed: () {
                setState(() {
                  _observacoesVenda = null;
                });
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Observações removidas'),
                    backgroundColor: Colors.orange,
                    duration: Duration(seconds: 1),
                  ),
                );
              },
              child: Text(
                'Remover',
                style: TextStyle(color: Colors.red.withOpacity(0.8)),
              ),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Cancelar',
              style: TextStyle(color: Colors.white54),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _observacoesVenda = observacoesController.text.trim();
              });
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    _observacoesVenda!.isEmpty
                        ? 'Observações removidas'
                        : 'Observações salvas',
                  ),
                  backgroundColor: Colors.green,
                  duration: const Duration(seconds: 1),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blueAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
  }

  void _abrirBuscaFacilitada(BuildContext context) {
    final dataService = Provider.of<DataService>(context, listen: false);
    final buscaController = TextEditingController();
    final buscaFocusNode = FocusNode();
    String termoBusca = '';
    int indiceSelecionado = -1;

    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          // Buscar itens usando a mesma lógica
          final resultados = _buscarItensComTermo(dataService, termoBusca);

          void selecionarItem(dynamic item) {
            Navigator.pop(context);
            _adicionarAoCarrinho(item);
          }

          return Dialog(
            backgroundColor: Colors.transparent,
            alignment: Alignment.topRight,
            insetPadding: const EdgeInsets.only(
              right: 16,
              top: 120,
              bottom: 20,
            ),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 350, maxHeight: 400),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E2E),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.5),
                    blurRadius: 20,
                    spreadRadius: 3,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Cabeçalho compacto
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.blue.withOpacity(0.3),
                          Colors.blueAccent.withOpacity(0.2),
                        ],
                      ),
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(16),
                        topRight: Radius.circular(16),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.blue.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Icon(
                            Icons.search,
                            color: Colors.blueAccent,
                            size: 16,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Busca Rápida',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.close,
                            color: Colors.white70,
                            size: 18,
                          ),
                          onPressed: () => Navigator.pop(context),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    ),
                  ),
                  // Campo de busca
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: TextField(
                      controller: buscaController,
                      focusNode: buscaFocusNode,
                      autofocus: true,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Digite nome, código...',
                        hintStyle: TextStyle(
                          color: Colors.white.withOpacity(0.4),
                        ),
                        prefixIcon: const Icon(
                          Icons.search,
                          color: Colors.blue,
                          size: 20,
                        ),
                        suffixIcon: termoBusca.isNotEmpty
                            ? IconButton(
                                icon: const Icon(
                                  Icons.clear,
                                  color: Colors.white54,
                                  size: 18,
                                ),
                                onPressed: () {
                                  buscaController.clear();
                                  setDialogState(() {
                                    termoBusca = '';
                                    indiceSelecionado = -1;
                                  });
                                },
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                              )
                            : null,
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.05),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: Colors.white.withOpacity(0.2),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: Colors.white.withOpacity(0.2),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: Colors.blueAccent,
                            width: 2,
                          ),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                      onChanged: (value) {
                        setDialogState(() {
                          termoBusca = value;
                          indiceSelecionado = -1;
                        });
                      },
                      onSubmitted: (value) {
                        if (indiceSelecionado >= 0 &&
                            indiceSelecionado < resultados.length) {
                          selecionarItem(resultados[indiceSelecionado]);
                        } else if (resultados.length == 1) {
                          selecionarItem(resultados[0]);
                        } else if (resultados.isEmpty &&
                            value.trim().isNotEmpty) {
                          final valorDigitado = double.tryParse(
                            value.replaceAll(',', '.').trim(),
                          );
                          Navigator.pop(context);
                          if (valorDigitado != null) {
                            _lancarDiversosRapido(precoInicial: valorDigitado);
                          }
                        }
                      },
                    ),
                  ),
                  // Resultados compactos
                  Flexible(
                    child: termoBusca.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.all(16),
                            child: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.search_off,
                                    size: 32,
                                    color: Colors.white.withOpacity(0.3),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Digite para buscar',
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.5),
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : resultados.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.all(16),
                            child: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.inventory_2_outlined,
                                    size: 32,
                                    color: Colors.white.withOpacity(0.3),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Nenhum resultado',
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.5),
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Pressione Enter para Diversos',
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.4),
                                      fontSize: 10,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : ListView.builder(
                            shrinkWrap: true,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            itemCount: resultados.length > 8
                                ? 8
                                : resultados.length,
                            itemBuilder: (context, index) {
                              final item = resultados[index];
                              final isSelected = index == indiceSelecionado;
                              final isProduto = item is Produto;

                              return InkWell(
                                onTap: () => selecionarItem(item),
                                child: Container(
                                  margin: const EdgeInsets.only(bottom: 6),
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                  decoration: BoxDecoration(
                                    gradient: isSelected
                                        ? LinearGradient(
                                            begin: Alignment.centerLeft,
                                            end: Alignment.centerRight,
                                            colors: isProduto
                                                ? [Colors.blue.shade900.withOpacity(0.6), Colors.blue.shade800.withOpacity(0.3)]
                                                : [Colors.purple.shade900.withOpacity(0.6), Colors.purple.shade800.withOpacity(0.3)],
                                          )
                                        : null,
                                    color: isSelected ? null : Colors.white.withOpacity(0.05),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: isSelected
                                          ? (isProduto ? Colors.blueAccent : Colors.purpleAccent)
                                          : Colors.white.withOpacity(0.08),
                                      width: isSelected ? 2 : 1,
                                    ),
                                    boxShadow: isSelected
                                        ? [
                                            BoxShadow(
                                              color: (isProduto ? Colors.blue : Colors.purple).withOpacity(0.2),
                                              blurRadius: 8,
                                              offset: const Offset(0, 2),
                                            ),
                                          ]
                                        : null,
                                  ),
                                  child: Builder(
                                    builder: (context) {
                                      if (isProduto) {
                                        final produto = item as Produto;
                                        return Row(
                                          children: [
                                            // Código como badge ou ícone
                                            if (produto.codigo != null && produto.codigo!.isNotEmpty)
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                                constraints: const BoxConstraints(minWidth: 48),
                                                decoration: BoxDecoration(
                                                  gradient: LinearGradient(
                                                    begin: Alignment.topLeft,
                                                    end: Alignment.bottomRight,
                                                    colors: [
                                                      Colors.blue.shade600,
                                                      Colors.blue.shade800,
                                                    ],
                                                  ),
                                                  borderRadius: BorderRadius.circular(10),
                                                  boxShadow: [
                                                    BoxShadow(
                                                      color: Colors.blue.withOpacity(0.3),
                                                      blurRadius: 6,
                                                      offset: const Offset(0, 2),
                                                    ),
                                                  ],
                                                ),
                                                child: Text(
                                                  produto.codigo!,
                                                  textAlign: TextAlign.center,
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 13,
                                                    letterSpacing: 0.5,
                                                  ),
                                                ),
                                              )
                                            else
                                              Container(
                                                padding: const EdgeInsets.all(10),
                                                decoration: BoxDecoration(
                                                  color: Colors.blue.withOpacity(0.15),
                                                  borderRadius: BorderRadius.circular(10),
                                                ),
                                                child: const Icon(
                                                  Icons.inventory_2_rounded,
                                                  color: Colors.blueAccent,
                                                  size: 22,
                                                ),
                                              ),
                                            const SizedBox(width: 14),
                                            // Nome e estoque
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    produto.nome.toUpperCase(),
                                                    style: TextStyle(
                                                      color: isDark ? Colors.yellow.shade200 : const Color(0xFF0F172A),
                                                      fontSize: 24,
                                                      fontWeight: FontWeight.w900,
                                                      height: 1.15,
                                                      letterSpacing: 0.5,
                                                      shadows: isDark ? [
                                                        const Shadow(
                                                          color: Colors.black87,
                                                          blurRadius: 4,
                                                          offset: Offset(0, 2),
                                                        ),
                                                      ] : null,
                                                    ),
                                                    maxLines: 2,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                  const SizedBox(height: 4),
                                                  // Estoque indicator
                                                  Row(
                                                    children: [
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                        decoration: BoxDecoration(
                                                          color: produto.estoque <= 0
                                                              ? Colors.red.withOpacity(0.2)
                                                              : produto.estoque < 10
                                                                  ? Colors.orange.withOpacity(0.15)
                                                                  : Colors.green.withOpacity(0.12),
                                                          borderRadius: BorderRadius.circular(6),
                                                        ),
                                                        child: Text(
                                                          produto.estoque <= 0
                                                              ? '⚠ Sem estoque'
                                                              : 'Est: ${produto.estoque}',
                                                          style: TextStyle(
                                                            color: produto.estoque <= 0
                                                                ? (isDark ? Colors.redAccent : Colors.red.shade800)
                                                                : produto.estoque < 10
                                                                    ? (isDark ? Colors.orangeAccent : Colors.orange.shade900)
                                                                    : (isDark ? Colors.greenAccent.shade200 : Colors.green.shade800),
                                                            fontSize: 11,
                                                            fontWeight: FontWeight.w600,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            // Preço em pill
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                              decoration: BoxDecoration(
                                                color: isDark ? Colors.green.withOpacity(0.15) : const Color(0xFFDCFCE7),
                                                borderRadius: BorderRadius.circular(10),
                                                border: Border.all(
                                                  color: isDark ? Colors.greenAccent.withOpacity(0.2) : const Color(0xFF86EFAC),
                                                ),
                                              ),
                                              child: Text(
                                                'R\$ ${produto.preco.toStringAsFixed(2)}',
                                                style: TextStyle(
                                                  color: isDark ? Colors.greenAccent : const Color(0xFF15803D),
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.bold,
                                                  letterSpacing: 0.3,
                                                ),
                                              ),
                                            ),
                                          ],
                                        );
                                      } else {
                                        final servico = item as Servico;
                                        return Row(
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.all(10),
                                              decoration: BoxDecoration(
                                                gradient: LinearGradient(
                                                  begin: Alignment.topLeft,
                                                  end: Alignment.bottomRight,
                                                  colors: [
                                                    Colors.purple.shade600.withOpacity(0.4),
                                                    Colors.purple.shade800.withOpacity(0.2),
                                                  ],
                                                ),
                                                borderRadius: BorderRadius.circular(10),
                                              ),
                                              child: const Icon(
                                                Icons.build_rounded,
                                                color: Colors.purpleAccent,
                                                size: 22,
                                              ),
                                            ),
                                            const SizedBox(width: 14),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    servico.nome.toUpperCase(),
                                                    style: TextStyle(
                                                      color: Colors.yellow.shade200,
                                                      fontSize: 24,
                                                      fontWeight: FontWeight.w900,
                                                      height: 1.15,
                                                      letterSpacing: 0.5,
                                                      shadows: [
                                                        Shadow(
                                                          color: Colors.black87,
                                                          blurRadius: 4,
                                                          offset: Offset(0, 2),
                                                        ),
                                                      ],
                                                    ),
                                                    maxLines: 2,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                  const SizedBox(height: 3),
                                                  Text(
                                                    '✦ Serviço',
                                                    style: TextStyle(
                                                      color: Colors.purpleAccent.withOpacity(0.7),
                                                      fontSize: 11,
                                                      fontWeight: FontWeight.w600,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            // Preço em pill
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                              decoration: BoxDecoration(
                                                color: Colors.green.withOpacity(0.15),
                                                borderRadius: BorderRadius.circular(10),
                                                border: Border.all(
                                                  color: Colors.greenAccent.withOpacity(0.2),
                                                ),
                                              ),
                                              child: Text(
                                                'R\$ ${servico.preco.toStringAsFixed(2)}',
                                                style: const TextStyle(
                                                  color: Colors.greenAccent,
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.bold,
                                                  letterSpacing: 0.3,
                                                ),
                                              ),
                                            ),
                                          ],
                                        );
                                      }
                                    },
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                  // Rodapé mínimo
                  if (resultados.isNotEmpty && termoBusca.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.03),
                        borderRadius: const BorderRadius.only(
                          bottomLeft: Radius.circular(20),
                          bottomRight: Radius.circular(20),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 14,
                            color: Colors.white.withOpacity(0.5),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '${resultados.length > 10 ? '10+' : resultados.length} resultado${resultados.length != 1 ? 's' : ''} • Enter para selecionar',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.6),
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      buscaFocusNode.requestFocus();
    });
  }

  List<dynamic> _buscarItensComTermo(DataService dataService, String termo) {
    if (termo.isEmpty) return [];

    final query = termo.trim();
    final queryLower = query.toLowerCase();

    if (query.isEmpty ||
        (!RegExp(r'^[0-9]+$').hasMatch(queryLower) && queryLower.length < 2)) {
      return [];
    }

    final resultados = <dynamic>[];
    final queryNumeros = query.replaceAll(RegExp(r'[^0-9]'), '');
    final queryNumerosSemZeros = queryNumeros.isEmpty
        ? ''
        : int.tryParse(queryNumeros)?.toString() ?? queryNumeros;

    // Verificar se a busca é APENAS numérica (sem letras)
    final ehApenasNumerico = RegExp(r'^[0-9]+$').hasMatch(query);

    // Buscar produtos
    for (final produto in dataService.produtos) {
      final nome = produto.nome.toLowerCase();
      final codigo = (produto.codigo ?? '').trim();
      final codigoLower = codigo.toLowerCase();
      // Todos os códigos de barras (principal + adicionais)
      final todosBarras = produto.todosCodigosBarras;
      final grupo = produto.grupo.toLowerCase();

      final codigoNumeros = codigo.replaceAll(RegExp(r'[^0-9]'), '');
      final codigoNumerosSemZeros = codigoNumeros.isEmpty
          ? ''
          : int.tryParse(codigoNumeros)?.toString() ?? codigoNumeros;
      // Códigos de barras (principal + adicionais) normalizados
      final barrasNumerosSemZeros = todosBarras
          .map((b) => b.replaceAll(RegExp(r'[^0-9]'), ''))
          .map((n) => n.isEmpty ? '' : (int.tryParse(n)?.toString() ?? n))
          .toList();
      final barrasLower = todosBarras.map((b) => b.toLowerCase()).toList();

      bool encontrou = false;

      // Se a busca for APENAS numérica, buscar SOMENTE pelo código (busca exata)
      if (ehApenasNumerico) {
        // Buscar APENAS por código ou código de barras (busca exata)
        if (codigoNumerosSemZeros == queryNumerosSemZeros ||
            barrasNumerosSemZeros.contains(queryNumerosSemZeros) ||
            codigoLower == queryLower ||
            codigo == query ||
            barrasLower.contains(queryLower) ||
            todosBarras.contains(query)) {
          encontrou = true;
        }
      } else {
        // Busca com letras ou texto - busca normal (código e nome)
        if (codigoLower == queryLower ||
            codigo == query ||
            barrasLower.contains(queryLower) ||
            todosBarras.contains(query) ||
            (queryNumerosSemZeros.isNotEmpty &&
                (codigoNumerosSemZeros == queryNumerosSemZeros ||
                    barrasNumerosSemZeros.contains(queryNumerosSemZeros))) ||
            codigoLower.startsWith(queryLower) ||
            barrasLower.any((b) => b.startsWith(queryLower)) ||
            nome == queryLower ||
            nome.startsWith(queryLower) ||
            (query.length >= 3 &&
                (nome.contains(queryLower) ||
                    codigoLower.contains(queryLower))) ||
            grupo.contains(queryLower)) {
          encontrou = true;
        }
      }

      if (encontrou) {
        resultados.add(produto);
      }
    }

    // Buscar serviços
    for (final servico in dataService.servicos) {
      final nome = servico.nome.toLowerCase();
      if (nome == queryLower ||
          nome.startsWith(queryLower) ||
          (query.length >= 3 && nome.contains(queryLower))) {
        resultados.add(servico);
      }
    }

    return resultados;
  }

  void _abrirDialogSuprimento() {
    final dataService = Provider.of<DataService>(context, listen: false);

    if (!dataService.caixaAberto) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('É necessário abrir o caixa antes de fazer suprimento'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final valorController = TextEditingController();
    final motivoController = TextEditingController();
    final observacaoController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: Row(
          children: [
            Icon(Icons.add_circle_outline, color: Colors.green),
            const SizedBox(width: 8),
            const Text(
              'Suprimento do Caixa',
              style: TextStyle(color: Colors.white),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: valorController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                ],
                decoration: InputDecoration(
                  labelText: 'Valor (R\$)',
                  labelStyle: const TextStyle(color: Colors.white70),
                  prefixIcon: const Icon(
                    Icons.attach_money,
                    color: Colors.green,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.green),
                  ),
                ),
                style: const TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: motivoController,
                decoration: InputDecoration(
                  labelText: 'Motivo *',
                  labelStyle: const TextStyle(color: Colors.white70),
                  prefixIcon: const Icon(
                    Icons.description,
                    color: Colors.green,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.green),
                  ),
                ),
                style: const TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: observacaoController,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: 'Observação (opcional)',
                  labelStyle: const TextStyle(color: Colors.white70),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.green),
                  ),
                ),
                style: const TextStyle(color: Colors.white),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Cancelar',
              style: TextStyle(color: Colors.white70),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              final valor = double.tryParse(valorController.text);
              final motivo = motivoController.text.trim();

              if (valor == null || valor <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Informe um valor válido'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }

              if (motivo.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Informe o motivo do suprimento'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }

              try {
                await dataService.registrarSuprimento(
                  valor: valor,
                  motivo: motivo,
                  observacao: observacaoController.text.trim().isEmpty
                      ? null
                      : observacaoController.text.trim(),
                );

                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Suprimento de R\$ ${valor.toStringAsFixed(2)} registrado com sucesso',
                    ),
                    backgroundColor: Colors.green,
                  ),
                );
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Erro ao registrar suprimento: $e'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('Confirmar Suprimento'),
          ),
        ],
      ),
    );
  }

  Future<void> _mostrarDialogPagamento(
    DataService dataService, {
    List<PagamentoPedido>? pagamentosIniciais,
  }) async {
    // Limpar seleções de navegação do grid para que o foco fique apenas no diálogo
    setState(() {
      _gridSelectedIndex = -1;
      _cartSelectedIndex = -1;
      _focoNoCarrinho = false;
      _focoNasCategorias = false;
    });

    List<PagamentoPedido> pagamentosAUsar = pagamentosIniciais ?? List.from(_pagamentosSalvos);
    
    // Se for Delivery e o pagamento preferencial estiver definido (e ainda sem pagamentos lançados),
    // já pré-preenche o pagamento preferencial com o valor total (produtos + taxa de entrega)
    if (pagamentosAUsar.isEmpty && _isDelivery && _formaPagamentoDelivery != null) {
      final total = _totalCarrinho;
      double? troco;
      if (_formaPagamentoDelivery == TipoPagamento.dinheiro && _valorParaTroco > total) {
        troco = _valorParaTroco - total;
      }
      pagamentosAUsar = [
        PagamentoPedido(
          id: const Uuid().v4(),
          tipo: _formaPagamentoDelivery!,
          valor: total,
          recebido: true,
          valorRecebido: _formaPagamentoDelivery == TipoPagamento.dinheiro ? (_valorParaTroco > 0 ? _valorParaTroco : total) : null,
          troco: troco,
        )
      ];
    }
    
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _DialogPagamentoPDV(
        subtotal: _totalCarrinhoSemDesconto,
        descontoTotal: _totalCarrinhoSemDesconto - _totalCarrinho,
        totalCarrinho: _totalCarrinho,
        pagamentosIniciais: pagamentosAUsar,
        cliente: _clienteSelecionado,
        cpfCnpjInicial: _cpfNfce,
        nomeInicial: _nomeNfce,
        onDadosConsumidorChanged: (cpf, nome) {
          _cpfNfce = cpf;
          _nomeNfce = nome;
          // Não precisa dar setState aqui porque o modal já se gerencia
        },
        onConfirmar: (listaPagamentos, desc, acres) {
          Navigator.pop(context);
          _concluirVendaComPagamentos(dataService, listaPagamentos);
        },
        onSalvarPendente: (listaPagamentos) {
          Navigator.pop(context);
          _salvarVendaPendente(dataService, listaPagamentos);
        },
      ),
    );
  }

  Future<void> _concluirVendaComPagamentos(
    DataService dataService,
    List<PagamentoPedido> pagamentos,
  ) async {
    if (_estaFinalizando) return;
    // CAPTURAR DADOS IMEDIATAMENTE (Atomicidade e Segurança contra Race Conditions)
    final itensVendaCapturados = List<ItemCarrinho>.from(_carrinho);
    final totalVendaCapturado = _totalCarrinho; 
    final mesaParaLimparId = this.mesaParaLimparId;
    final mesaNumero = this.mesaNumero;
    final tipoNome = this.tipoNome;
    final clienteSelecionadoCapturado = _clienteSelecionado;
    final vendedorSelecionadoCapturado = _vendedorSelecionado;
    final observacoesVendaCapturadas = _observacoesVenda;
    final cpfNfceCapturado = _cpfNfce;
    final nomeNfceCapturado = _nomeNfce;
    final mesaComandaOriginal = _mesaComandaVinculada;
    
    // DELIVERY DATA CAPTURE
    final isDeliveryCapturado = _isDelivery;
    final enderecoEntregaCapturado = _enderecoEntrega;
    final taxaEntregaCapturado = _taxaEntrega;
    final motoristaIdCapturado = _motoristaId;
    final motoristaNomeCapturado = _motoristaNome;

    if (itensVendaCapturados.isEmpty && mesaParaLimparId == null) {
      debugPrint('>>> [VendaDireta] ⚠️ Abortando finalização: Carrinho vazio e sem mesa vinculada.');
      return;
    }

    // VALIDAR FORMAS DE PAGAMENTO DA TABELA DE PREÇO
    final configPerfil = dataService.empresaAtual?.getConfigPerfilPreco(_perfilPrecoEfetivo);
    final formasPermitidas = configPerfil != null && configPerfil['formas_pagamento'] != null 
        ? List<String>.from(configPerfil['formas_pagamento'])
        : <String>[];

    final qtdMinima = configPerfil != null && configPerfil['quantidade_minima'] != null 
        ? (configPerfil['quantidade_minima'] as num).toDouble() 
        : 0.0;
        
    final aplicarTabela = _totalItens >= qtdMinima;

    if (aplicarTabela && formasPermitidas.isNotEmpty && configPerfil != null) {
      bool pagamentoInvalido = false;
      for (var p in pagamentos) {
        // Se a forma de pagamento não estiver na lista (e o valor for maior que zero para garantir que foi usada)
        if (p.valor > 0 && !formasPermitidas.contains(p.tipo.name)) {
          pagamentoInvalido = true;
          break;
        }
      }
      
      if (pagamentoInvalido) {
        final nomesPermitidos = formasPermitidas.map((f) {
           return TipoPagamento.values.firstWhere((t) => t.name == f, orElse: () => TipoPagamento.outro).nome;
        }).join(', ');
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('A Tabela "${configPerfil['nome']}" exige pagamento em: $nomesPermitidos.'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          )
        );
        return; // Aborta a finalização
      }
    }

    setState(() => _estaFinalizando = true);
    
    final uuid = const Uuid();
    debugPrint('>>> [VendaDireta] 🚀 INICIANDO FINALIZAÇÃO DA VENDA (Segura)');
    debugPrint('>>> [VendaDireta] 🔍 Total Capturado: R\$ ${totalVendaCapturado.toStringAsFixed(2)}');
    debugPrint('>>> [VendaDireta] 🔍 Itens: ${itensVendaCapturados.length}');
    
    try {
      String numero = _pedidoOriginal?.numero ?? (isDeliveryCapturado 
          ? dataService.getProximoNumeroPedido() 
          : dataService.getProximoNumeroVenda());
          
      if (mesaNumero != null && _pedidoOriginal == null) {
        final bool isComanda = mesaComandaOriginal?.tipo == TipoControle.comanda || 
                               mesaNumero.toUpperCase().contains('CMD') || 
                               mesaNumero.toUpperCase().contains('COMANDA');
        final prefixo = isComanda ? 'CMD' : 'MESA';
        final proximoNumVal = numero.split('-').last;
        numero = '$prefixo-$mesaNumero-$proximoNumVal';
      }

      final pagamentosAtualizados = pagamentos.map((p) {
        final isInstantaneo =
            p.tipo == TipoPagamento.dinheiro ||
            p.tipo == TipoPagamento.pix ||
            p.tipo == TipoPagamento.cartaoCredito ||
            p.tipo == TipoPagamento.cartaoDebito;

        if (isInstantaneo && !p.isParcela) {
          return PagamentoPedido(
            id: p.id,
            tipo: p.tipo,
            valor: p.valor,
            recebido: true,
            dataRecebimento: DateTime.now(),
            dataVencimento: p.dataVencimento,
            parcelas: p.parcelas,
            numeroParcela: p.numeroParcela,
            parcelamentoId: p.parcelamentoId,
            observacao: p.observacao,
            valorRecebido: p.valorRecebido,
            troco: p.troco,
          );
        }
        return p;
      }).toList();

      final totalRecebido = pagamentosAtualizados
          .where((p) => p.recebido)
          .fold(0.0, (sum, p) => sum + p.valor);

      String statusPedido;
      if (totalRecebido >= totalVendaCapturado - 0.01) {
        statusPedido = 'Pago';
      } else {
        statusPedido = 'Pendente';
      }

      TipoPagamento tipoPagamentoVenda = pagamentosAtualizados.isNotEmpty 
          ? pagamentosAtualizados.first.tipo 
          : TipoPagamento.outro;

      final itensVenda = itensVendaCapturados
          .map(
            (item) => ItemVendaBalcao(
              id: item.id,
              nome: item.nome,
              precoUnitario: item.isBrinde ? 0.0 : item.preco,
              precoOriginal: item.precoOriginal,
              precoSemPromocao: item.precoSemPromocao,
              quantidade: item.quantidade,
              isServico: item.isServico,
              fornecedorNome: item.fornecedorNome,
              observacao: item.isBrinde 
                  ? (item.observacao != null && item.observacao!.isNotEmpty 
                      ? '[BRINDE] ${item.observacao}' 
                      : '[BRINDE]') 
                  : item.observacao,
              adicionais: item.adicionais,
              opcoesCombo: item.opcoesCombo,
              precoTabela: item.precoTabela,
            baixaProporcional: item.baixaProporcional,
            unidadeVenda: item.unidadeVenda,
            quantidadeBaixa: item.quantidadeBaixa,
            ),
          )
          .toList();

      String? observacoesFinais = observacoesVendaCapturadas;
      final String labelOrigem = tipoNome == 'Comanda' ? '[COMANDA]' : (tipoNome == 'Mesa' ? '[MESA]' : '[BALCÃO]');
      
      if (observacoesFinais == null || observacoesFinais.isEmpty) {
        if (mesaNumero != null) {
          observacoesFinais = 'Venda originada da $tipoNome $mesaNumero';
        }
      }

      String? clienteNomeFinal = clienteSelecionadoCapturado?.nome ?? nomeNfceCapturado;
      if (mesaNumero != null) {
        if (clienteNomeFinal == null || clienteNomeFinal.isEmpty) {
          clienteNomeFinal = '$labelOrigem $mesaNumero';
        } else if (!clienteNomeFinal.toUpperCase().contains(labelOrigem.toUpperCase())) {
          clienteNomeFinal = '$labelOrigem $mesaNumero - $clienteNomeFinal';
        }
      }

      final String tagIdentificacao = '[VIP-MC] originado de $labelOrigem $mesaNumero';
      final observacaoIdentificadora = mesaParaLimparId != null 
          ? (observacoesFinais != null && observacoesFinais.isNotEmpty 
              ? '$tagIdentificacao | $observacoesFinais' 
              : tagIdentificacao)
          : observacoesFinais;

      final vendaId = _pedidoOriginal?.id ?? uuid.v4();
      final vendaBalcao = VendaBalcao(
        id: vendaId,
        numero: numero,
        dataVenda: DateTime.now(),
        clienteId: clienteSelecionadoCapturado?.id,
        clienteNome: clienteNomeFinal,
        clienteTelefone: clienteSelecionadoCapturado?.telefone,
        clienteCpfCnpj: clienteSelecionadoCapturado?.cpfCnpj ?? cpfNfceCapturado,
        vendedorId: vendedorSelecionadoCapturado?.id,
        vendedorNome: vendedorSelecionadoCapturado?.nome,
        itens: itensVenda,
        tipoPagamento: tipoPagamentoVenda,
        pagamentos: pagamentosAtualizados,
        valorTotal: totalVendaCapturado,
        valorRecebido: totalRecebido > 0 ? totalRecebido : null,
        troco: pagamentosAtualizados
            .where((p) => p.troco != null && p.troco! > 0)
            .fold<double?>(null, (sum, p) => (sum ?? 0) + (p.troco ?? 0)),
        observacoes: observacaoIdentificadora,
        operador: dataService.responsavelAtivo ?? 'PDV',
        origem: mesaParaLimparId != null ? 'Mesa/Comanda' : 'Venda Direta',
        deliveryInfo: isDeliveryCapturado && enderecoEntregaCapturado != null
            ? DeliveryInfo(
                id: uuid.v4(),
                enderecoId: enderecoEntregaCapturado.id,
                logradouro: enderecoEntregaCapturado.logradouro,
                numero: enderecoEntregaCapturado.numero,
                bairro: enderecoEntregaCapturado.bairro,
                cidade: enderecoEntregaCapturado.cidade,
                uf: enderecoEntregaCapturado.uf,
                cep: enderecoEntregaCapturado.cep,
                taxaEntrega: taxaEntregaCapturado,
                motoristaId: motoristaIdCapturado,
                motoristaNome: motoristaNomeCapturado,
                status: 'Pendente',
                previsaoEntrega: _previsaoEntrega.trim().isEmpty ? null : _previsaoEntrega.trim(),
                dataPedido: DateTime.now(),
              )
            : null,
      );

      // SALVAR DADOS (Snapshot garantido)
      // Se estava editando um pedido/venda salva, remover o antigo ANTES de adicionar o novo
      if (_pedidoOriginal != null) {
        // dataService.deletePedido(_pedidoOriginal!.id);

        final vendaOriginal = dataService.vendasBalcao
            .where((v) => v.id == _pedidoOriginal!.id || v.numero == _pedidoOriginal!.numero)
            .firstOrNull;
        if (vendaOriginal != null) {
          await dataService.deleteVendaBalcao(vendaOriginal.id);
        }
      }

      // Se for Delivery agora gerado, não criar VendaBalcao ainda (será criada quando paga no PDV)
      if (!isDeliveryCapturado) {
        await dataService.addVendaBalcao(vendaBalcao);
      }

      final temPagamentosPendentes = pagamentosAtualizados.any((p) => !p.recebido);
      final temFiadoOuCrediario = pagamentosAtualizados.any(
        (p) => p.tipo == TipoPagamento.fiado || p.tipo == TipoPagamento.crediario,
      );

      if (mesaParaLimparId != null || temFiadoOuCrediario || temPagamentosPendentes || isDeliveryCapturado) {
        final produtosPedido = <ItemPedido>[];
        final servicosPedido = <ItemServico>[];

        for (final item in itensVenda) {
          if (item.isServico) {
            servicosPedido.add(ItemServico(
              id: item.id,
              descricao: item.nome,
              valor: item.precoUnitario,
              valorAdicional: 0.0,
              dataAgendamento: DateTime.now(),
              observacao: item.observacao,
            ));
          } else {
            produtosPedido.add(ItemPedido(
              id: item.id,
              nome: item.nome,
              preco: item.precoUnitario,
              quantidade: item.quantidade,
              observacao: item.observacao,
              fornecedorNome: item.fornecedorNome,
              adicionais: item.adicionais,
              unidadeVenda: item.unidadeVenda,
              quantidadeBaixa: item.quantidadeBaixa,
              precoSemPromocao: item.precoSemPromocao,
            ));
          }
        }

        final pedido = Pedido(
          id: vendaId,
          numero: numero,
          clienteId: clienteSelecionadoCapturado?.id,
          clienteNome: clienteNomeFinal,
          clienteTelefone: clienteSelecionadoCapturado?.telefone ?? vendaBalcao.clienteTelefone,
          dataPedido: vendaBalcao.dataVenda,
          status: statusPedido,
          total: totalVendaCapturado,
          produtos: produtosPedido,
          servicos: servicosPedido,
          pagamentos: pagamentosAtualizados,
          observacoes: observacaoIdentificadora,
          deliveryInfo: vendaBalcao.deliveryInfo,
          vendedorId: vendedorSelecionadoCapturado?.id,
          vendedorNome: vendedorSelecionadoCapturado?.nome,
          operador: vendaBalcao.operador,
        );

        await dataService.addPedido(pedido);

        // CRIAR REGISTRO DE ENTREGA (Para aparecer no Controle de Entregas)
        if (pedido.deliveryInfo != null) {
          final entrega = Entrega(
            id: uuid.v4(),
            pedidoId: pedido.id,
            pedidoNumero: pedido.numero,
            clienteNome: pedido.clienteNome ?? 'Cliente',
            clienteTelefone: pedido.clienteTelefone,
            enderecoEntrega: '${pedido.deliveryInfo!.logradouro}, ${pedido.deliveryInfo!.numero}',
            bairro: pedido.deliveryInfo!.bairro,
            cidade: pedido.deliveryInfo!.cidade,
            cep: pedido.deliveryInfo!.cep,
            status: StatusEntrega.aguardando,
            dataCriacao: DateTime.now(),
            motoristaId: pedido.deliveryInfo!.motoristaId,
            motoristaNome: pedido.deliveryInfo!.motoristaNome,
            taxaEntrega: pedido.deliveryInfo!.taxaEntrega,
            observacoes: pedido.observacoes,
          );
          await dataService.addEntrega(entrega);
        }
      }

      await _registrarComissaoVendedorSeAplicavel(
        dataService: dataService,
        pedidoId: vendaId,
        pedidoNumero: numero,
        valorPedido: totalVendaCapturado,
        vendedor: vendedorSelecionadoCapturado,
      );

      // Atualizar Fiado do Cliente
      final valorFiado = pagamentosAtualizados
          .where((p) => p.tipo == TipoPagamento.fiado && !p.recebido)
          .fold(0.0, (sum, p) => sum + p.valor);

      if (valorFiado > 0 && clienteSelecionadoCapturado != null) {
        dataService.updateCliente(clienteSelecionadoCapturado.copyWith(
          saldoDevedor: clienteSelecionadoCapturado.saldoDevedor + valorFiado,
          updatedAt: DateTime.now(),
        ));
      }

      // Limpar mesa/comanda vinculada
      if (mesaParaLimparId != null) {
          if (mesaComandaOriginal != null) {
            dataService.updateMesaComanda(mesaComandaOriginal.copyWith(status: 'Fechada'));
          }
          await dataService.deleteMesaComanda(mesaParaLimparId);
      }

      // SALVAMENTO GLOBAL EM BACKGROUND (Evita travamentos visuais)
      dataService.salvarImediatamente(); 

      final trocoTotal = pagamentosAtualizados
          .where((p) => p.troco != null && p.troco! > 0)
          .fold(0.0, (sum, p) => sum + (p.troco ?? 0));

      _resetarTodaVenda();

      
      if (mounted) {
        _tocarSomPDV('notification.mp3', tipo: 'finalizar');
        _mostrarSucessoVenda(
          totalVendaCapturado, numero, vendaBalcao,
          troco: trocoTotal,
          titulo: '${tipoNome.toUpperCase()} FINALIZADA!',
          infoExtra: 'GERADA NO HISTÓRICO!',
          voltarAoFechar: mesaParaLimparId != null,
        );
      }
    } catch (e, stackTrace) {
      debugPrint('>>> ❌ ERRO AO FINALIZAR: $e\n$stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao finalizar venda: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _estaFinalizando = false);
    }
  }

  Future<void> _registrarComissaoVendedorSeAplicavel({
    required DataService dataService,
    required String pedidoId,
    required String pedidoNumero,
    required double valorPedido,
    required Funcionario? vendedor,
  }) async {
    if (vendedor == null || !vendedor.ativo || valorPedido <= 0) return;

    double percentualComissao = 0.0;
    double valorComissao = 0.0;

    if (vendedor.tipoComissao == 'Porcentagem') {
      percentualComissao = vendedor.porcentagemComissao;
      valorComissao = valorPedido * (percentualComissao / 100);
    } else {
      valorComissao = vendedor.valorComissao;
      percentualComissao =
          valorPedido > 0 ? (valorComissao / valorPedido) * 100 : 0.0;
    }

    if (valorComissao <= 0) return;

    final comissaoExistente = dataService.comissoesVendedores
        .where((c) => c.pedidoId == pedidoId && c.funcionarioId == vendedor.id)
        .firstOrNull;

    final comissao = ComissaoVendedor(
      id: comissaoExistente?.id ?? const Uuid().v4(),
      linkVendedorId: comissaoExistente?.linkVendedorId ?? '',
      funcionarioId: vendedor.id,
      funcionarioNome: vendedor.nome,
      pedidoId: pedidoId,
      pedidoNumero: pedidoNumero,
      valorPedido: valorPedido,
      percentualComissao: percentualComissao,
      valorComissao: valorComissao,
      status: comissaoExistente?.status ?? 'Pendente',
      dataPagamento: comissaoExistente?.dataPagamento,
      createdAt: comissaoExistente?.createdAt ?? DateTime.now(),
      updatedAt: DateTime.now(),
    );

    if (comissaoExistente != null) {
      await dataService.updateComissaoVendedor(comissao);
    } else {
      await dataService.addComissaoVendedor(comissao);
    }
  }

  Future<void> _perguntarEmissaoNfce(
    VendaBalcao venda,
    Cliente? cliente,
  ) async {
    final nfceService = NfceService();
    final dataService = Provider.of<DataService>(context, listen: false);
    final empresa = dataService.empresaAtual; // Usando empresaAtual do DataService

    if (empresa != null) {
      final configUrl = empresa.configuracoes?['bridgeNfceUrl'] as String?;
      if (configUrl != null && configUrl.isNotEmpty) {
        nfceService.setBaseUrl(configUrl);
      }
    }

    // Verificar se o backend está online antes de perguntar
    final online = await nfceService.verificarStatusBackend();
    if (!online) return; // Se backend off, nem pergunta

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: const Text(
          'Emissão Fiscal',
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Deseja emitir a NFC-e para esta venda?',
              style: TextStyle(color: Colors.white70),
            ),
            if (cliente == null ||
                cliente.cpfCnpj == null ||
                cliente.cpfCnpj!.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 16.0),
                child: TextField(
                  decoration: const InputDecoration(
                    labelText: 'CPF na Nota (Opcional)',
                    prefixIcon: Icon(
                      Icons.badge_outlined,
                      color: Colors.white54,
                    ),
                    filled: true,
                    fillColor: Colors.white10,
                  ),
                  style: const TextStyle(color: Colors.white),
                  keyboardType: TextInputType.number,
                  onChanged: (value) {
                    // Atualizar CPF temporário se necessário
                    // Por simplicidade, assumir envio direto se digitado
                  },
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Não', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.receipt_long),
            label: const Text('Emitir NFC-e'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            onPressed: () async {
              Navigator.pop(context); // Fecha pergunta
              await _emitirNFCe(venda);
            },
          ),
        ],
      ),
    );
  }

  // Salvar venda pendente para receber depois
  Future<void> _salvarVendaPendente(
    DataService dataService,
    List<PagamentoPedido> pagamentosDoDialog, {
    bool mostrarPromptImpressao = false,
  }) async {
    String? nomeIdentificacao;
    final vendedorSelecionadoCapturado = _vendedorSelecionado;

    // Se não tiver cliente selecionado, perguntar um nome rápido para identificar
    if (_clienteSelecionado == null) {
      // Se já houver um nome identificado (pelo campo NFC-e ou vindo de venda retomada)
      // não perguntamos de novo.
      if (_nomeNfce != null && _nomeNfce!.isNotEmpty) {
        nomeIdentificacao = _nomeNfce;
      } else {
        final controller = TextEditingController();
        nomeIdentificacao = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E2E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Identificar Venda', style: TextStyle(color: Colors.white)),
          content: TextField(
            controller: controller,
            autofocus: true,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: 'Nome do Cliente ou Mesa',
              labelStyle: const TextStyle(color: Colors.white70),
              hintText: 'Ex: João, Mesa 05, Balcão...',
              hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
              filled: true,
              fillColor: Colors.black26,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: const Text('IGNORAR', style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
              child: const Text('SALVAR', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        );
        // Se o usuário digitou um nome, salva ele no _nomeNfce para futuras referências
        if (nomeIdentificacao != null && nomeIdentificacao.isNotEmpty) {
          setState(() {
            _nomeNfce = nomeIdentificacao;
          });
        }
      }
    }

    // DELIVERY DATA CAPTURE
    final isDeliveryCapturado = _isDelivery;
    final enderecoEntregaCapturado = _enderecoEntrega;
    final taxaEntregaCapturado = _taxaEntrega;
    final motoristaIdCapturado = _motoristaId;
    final motoristaNomeCapturado = _motoristaNome;
    
    final uuid = const Uuid();
    final mesaNumero = _mesaComandaVinculada?.numero;
    final mesaParaLimparId = _mesaComandaVinculada?.id;


    // Criar itens da venda balcão
    final itensVenda = _carrinho
        .map(
          (item) => ItemVendaBalcao(
            id: item.id,
            nome: item.nome,
            precoUnitario: item.preco,
            precoOriginal: item.precoOriginal,
            precoSemPromocao: item.precoSemPromocao,
            quantidade: item.quantidade,
            isServico: item.isServico,
            fornecedorNome: item.fornecedorNome,
            observacao: item.observacao,
            adicionais: item.adicionais,
            opcoesCombo: item.opcoesCombo,
          baixaProporcional: item.baixaProporcional,
          unidadeVenda: item.unidadeVenda,
          quantidadeBaixa: item.quantidadeBaixa,
          ),
        )
        .toList();

    // Determinar tipo de pagamento principal (se houver)
    TipoPagamento tipoPrincipal = _formaPagamentoDelivery ?? TipoPagamento.outro;
    if (pagamentosDoDialog.isNotEmpty) {
      tipoPrincipal = pagamentosDoDialog.first.tipo;
    }

    final String numero = _pedidoOriginal?.numero ?? (isDeliveryCapturado 
        ? dataService.getProximoNumeroPedido() 
        : dataService.getProximoNumeroVenda());
        
    String numeroFinal = numero;
    if (mesaNumero != null && _pedidoOriginal == null) {
      final bool isComanda = _mesaComandaVinculada?.tipo == TipoControle.comanda || 
                             mesaNumero.toUpperCase().contains('CMD') || 
                             mesaNumero.toUpperCase().contains('COMANDA');
      final prefixo = isComanda ? 'CMD' : 'MESA';
      final proximoNumVal = numero.split('-').last;
      numeroFinal = '$prefixo-$mesaNumero-$proximoNumVal';
    }

    // Criar venda balcão
    final vendaBalcao = VendaBalcao(
      id: _pedidoOriginal?.id ?? uuid.v4(),
      numero: numeroFinal,
      dataVenda: _pedidoOriginal?.dataPedido ?? DateTime.now(),
      clienteId: _clienteSelecionado?.id,
      clienteNome: _clienteSelecionado?.nome ?? (nomeIdentificacao?.isNotEmpty == true ? nomeIdentificacao : (mesaNumero != null ? 'Mesa $mesaNumero' : null)),
      clienteTelefone: _clienteSelecionado?.telefone,
      vendedorId: vendedorSelecionadoCapturado?.id,
      vendedorNome: vendedorSelecionadoCapturado?.nome,

      itens: itensVenda,
      tipoPagamento: tipoPrincipal,
      valorTotal: _totalCarrinho,
      valorRecebido: null,
      troco: null,
      observacoes: _observacoesVenda?.isNotEmpty == true ? _observacoesVenda : null,
      deliveryInfo: isDeliveryCapturado && enderecoEntregaCapturado != null
            ? DeliveryInfo(
                id: uuid.v4(),
                enderecoId: enderecoEntregaCapturado.id,
                logradouro: enderecoEntregaCapturado.logradouro,
                numero: enderecoEntregaCapturado.numero,
                bairro: enderecoEntregaCapturado.bairro,
                cidade: enderecoEntregaCapturado.cidade,
                uf: enderecoEntregaCapturado.uf,
                cep: enderecoEntregaCapturado.cep,
                taxaEntrega: taxaEntregaCapturado,
                motoristaId: motoristaIdCapturado,
                motoristaNome: motoristaNomeCapturado,
                status: 'Pendente',
                valorParaTroco: _valorParaTroco,
                previsaoEntrega: _previsaoEntrega.trim().isEmpty ? null : _previsaoEntrega.trim(),
                dataPedido: DateTime.now(),
              )
            : null,
    );


    // Salvar venda balcão (Removido: Venda salva agora gera apenas Pedido até ser paga no PDV)
    // dataService.addVendaBalcao(vendaBalcao);

    // Converter itens da venda em itens do pedido
    final produtosPedido = <ItemPedido>[];
    final servicosPedido = <ItemServico>[];

    for (final item in itensVenda) {
      if (item.isServico) {
        servicosPedido.add(
          ItemServico(
            id: item.id,
            descricao: item.nome,
            valor: item.precoUnitario,
            valorAdicional: 0.0,
            dataAgendamento: DateTime.now(),
            observacao: item.observacao,
          ),
        );
      } else {
        produtosPedido.add(
          ItemPedido(
            id: item.id,
            nome: item.nome,
            preco: item.precoUnitario,
            quantidade: item.quantidade,
            observacao: item.observacao,
            fornecedorNome: item.fornecedorNome,
            adicionais: item.adicionais,
            unidadeVenda: item.unidadeVenda,
            quantidadeBaixa: item.quantidadeBaixa,
            precoSemPromocao: item.precoSemPromocao,
          ),
        );
      }
    }

    // Criar pedido a partir da venda salva
    final pedidoVendaSalva = Pedido(
      id: _pedidoOriginal?.id ?? uuid.v4(),
      numero: _pedidoOriginal?.numero ?? vendaBalcao.numero,
      clienteId: _clienteSelecionado?.id,
      clienteNome: vendaBalcao.clienteNome?.trim().isEmpty == true ? 'Delivery' : vendaBalcao.clienteNome,
      clienteTelefone: _clienteSelecionado?.telefone ?? vendaBalcao.clienteTelefone,
      clienteEndereco: isDeliveryCapturado && enderecoEntregaCapturado != null 
          ? '${enderecoEntregaCapturado.logradouro}, ${enderecoEntregaCapturado.numero}' 
          : null,
      dataPedido: vendaBalcao.dataVenda,
      status: 'Pendente',
      produtos: produtosPedido,
      servicos: servicosPedido,
      pagamentos: pagamentosDoDialog.isNotEmpty 
          ? pagamentosDoDialog 
          : [PagamentoPedido(
              id: uuid.v4(),
              tipo: _formaPagamentoDelivery ?? TipoPagamento.outro,
              valor: _totalCarrinho,
              recebido: false,
              observacao: 'Venda Salva: ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}',
            )],
      createdAt: vendaBalcao.dataVenda,
      updatedAt: vendaBalcao.dataVenda,
      observacoes: vendaBalcao.observacoes,
      vendedorId: vendedorSelecionadoCapturado?.id,
      vendedorNome: vendedorSelecionadoCapturado?.nome,
      deliveryInfo: vendaBalcao.deliveryInfo,
    );

    // Se estava editando um pedido/venda salva, remover o antigo ANTES de adicionar o novo
    // Isso evita duplicados e garante que o novo registro (com mesmo ID se carregado) persista
    if (_pedidoOriginal != null) {
      // dataService.deletePedido(_pedidoOriginal!.id);

      final vendaOriginal = dataService.vendasBalcao
          .where((v) => v.numero == _pedidoOriginal!.numero)
          .firstOrNull;
      if (vendaOriginal != null) {
        await dataService.deleteVendaBalcao(vendaOriginal.id);
      }
      
      // Também remover registro de entrega antigo se houver
      final entregaOriginal = dataService.entregas
          .where((e) => e.pedidoId == _pedidoOriginal!.id)
          .firstOrNull;
      if (entregaOriginal != null) {
        dataService.deleteEntrega(entregaOriginal.id);
      }
    }

    // =============== LOGIC SEPARATION (DELIVERY VS BALCÃO) ===============
    final isDelivery = vendaBalcao.deliveryInfo != null;

    if (isDelivery) {
      // 1. DELIVERY: Salvar como Pedido para aparecer na Central de Pedidos
      await dataService.addPedido(pedidoVendaSalva);

      // 2. CRIAR REGISTRO DE ENTREGA
      final registroEntrega = Entrega(
        id: uuid.v4(),
        pedidoId: pedidoVendaSalva.id,
        pedidoNumero: pedidoVendaSalva.numero,
        clienteNome: pedidoVendaSalva.clienteNome ?? 'Delivery',
        clienteTelefone: pedidoVendaSalva.clienteTelefone,
        enderecoEntrega: '${pedidoVendaSalva.deliveryInfo!.logradouro}, ${pedidoVendaSalva.deliveryInfo!.numero}',
        bairro: pedidoVendaSalva.deliveryInfo!.bairro,
        cidade: pedidoVendaSalva.deliveryInfo!.cidade,
        cep: pedidoVendaSalva.deliveryInfo!.cep,
        status: StatusEntrega.aguardando,
        dataCriacao: DateTime.now(),
        motoristaId: pedidoVendaSalva.deliveryInfo!.motoristaId,
        motoristaNome: pedidoVendaSalva.deliveryInfo!.motoristaNome,
        taxaEntrega: pedidoVendaSalva.deliveryInfo!.taxaEntrega,
        observacoes: pedidoVendaSalva.observacoes,
      );
      await dataService.addEntrega(registroEntrega);

      // 3. Notificação de Sucesso Gourmet
      _mostrarSucessoPedidoGerado(vendaBalcao.numero);

      // 4. Diálogo de Impressão (Apenas para Delivery)
      if (mounted) {
        _mostrarDialogoTipoImpressaoPedido(context, pedidoVendaSalva);
      }
    } else {
      // 1. BALCÃO: Salvar apenas como VendaBalcao (aparece na aba "Receber" do PDV)
      dataService.addVendaBalcao(vendaBalcao);

      // 2. Notificação Simples
      _mostrarSucessoVendaSalva(vendaBalcao.numero);

      // 3. Navegação direta para pedidos/receber (sem prompt)
      _navegarParaReceber();
    }

    await _registrarComissaoVendedorSeAplicavel(
      dataService: dataService,
      pedidoId: pedidoVendaSalva.id,
      pedidoNumero: pedidoVendaSalva.numero,
      valorPedido: pedidoVendaSalva.total,
      vendedor: vendedorSelecionadoCapturado,
    );

    _pedidoOriginal = null;

    // Callback de finalização
    widget.onVendaFinalizada?.call();

    // Marcar como fechada e aguardar liberação
    if (mesaParaLimparId != null) {
        // Ativando filtro para sumir da tela
        final tempMc = _mesaComandaVinculada!.copyWith(status: 'Fechada');
        dataService.updateMesaComanda(tempMc);
        
        await dataService.deleteMesaComanda(mesaParaLimparId);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Mesa/Comanda $mesaNumero liberada!'),
              backgroundColor: Colors.orange,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
    }

    // Resetar estado local
    _resetarTodaVenda();

  }

  void _mostrarSucessoPedidoGerado(String numeroVenda) {
    _mostrarNotificacaoSucesso(
      icone: Icons.receipt_long,
      titulo: 'PEDIDO GERADO',
      subtitulo: numeroVenda,
      cor: Colors.orange,
      info: 'Disponível em "PEDIDOS"',
    );

    // Limpar estado completo da venda
    // _resetarTodaVenda();

    // Limpar carrinho salvo após finalizar venda
    // _limparCarrinhoSalvo();

  }

  void _abrirDialogDividirConta() {
    if (_carrinho.isEmpty) return;

    final dataService = Provider.of<DataService>(context, listen: false);
    
    // Map local para armazenar as quantidades selecionadas para dividir (index -> qty)
    final Map<int, double> selecionados = {};
    
    // Inicializa todos com 0.0
    for (int i = 0; i < _carrinho.length; i++) {
      selecionados[i] = 0.0;
    }

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            
            // Calcular o valor total selecionado
            double totalSelecionado = 0.0;
            double totalItensOriginal = _carrinho.fold(0.0, (sum, item) => sum + item.subtotal);
            
            for (int i = 0; i < _carrinho.length; i++) {
              final item = _carrinho[i];
              final qty = selecionados[i] ?? 0.0;
              if (qty > 0.0) {
                final ratio = qty / item.quantidade;
                totalSelecionado += item.subtotal * ratio;
              }
            }

            // Distribuir desconto geral se houver
            double descontoProporcional = 0.0;
            if (_descontoTotal > 0 && totalItensOriginal > 0) {
              final ratioGeral = totalSelecionado / totalItensOriginal;
              descontoProporcional = _descontoTotal * ratioGeral;
            }
            double totalFinalPagar = totalSelecionado - descontoProporcional;

            return AlertDialog(
              backgroundColor: const Color(0xFF1E1E2E),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Row(
                children: const [
                  Icon(Icons.call_split_rounded, color: Colors.blueAccent),
                  SizedBox(width: 8),
                  Text('Dividir por Itens', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                ],
              ),
              content: SizedBox(
                width: 500,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Selecione a quantidade de cada produto que esta pessoa vai pagar agora:',
                      style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 13),
                    ),
                    const SizedBox(height: 16),
                    Flexible(
                      child: Container(
                        constraints: const BoxConstraints(maxHeight: 300),
                        decoration: BoxDecoration(
                          color: Colors.black12,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white10),
                        ),
                        child: ListView.separated(
                          shrinkWrap: true,
                          padding: const EdgeInsets.all(8),
                          itemCount: _carrinho.length,
                          separatorBuilder: (_, __) => const Divider(color: Colors.white10, height: 1),
                          itemBuilder: (context, index) {
                            final item = _carrinho[index];
                            final qtySelecionada = selecionados[index] ?? 0.0;

                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item.nome,
                                          style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'Disponível: ${item.quantidade.toStringAsFixed(0)}x • R\$ ${item.preco.toStringAsFixed(2)} cada',
                                          style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 11),
                                        ),
                                      ],
                                    ),
                                  ),
                                  // Selecionador de Quantidade
                                  Row(
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.remove_circle_outline, color: Colors.redAccent, size: 20),
                                        onPressed: qtySelecionada > 0.0
                                            ? () {
                                                setDialogState(() {
                                                  selecionados[index] = (qtySelecionada - 1.0).clamp(0.0, item.quantidade);
                                                });
                                              }
                                            : null,
                                      ),
                                      Container(
                                        constraints: const BoxConstraints(minWidth: 30),
                                        alignment: Alignment.center,
                                        child: Text(
                                          qtySelecionada.toStringAsFixed(0),
                                          style: TextStyle(
                                            color: qtySelecionada > 0.0 ? Colors.greenAccent : Colors.white24,
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.add_circle_outline, color: Colors.greenAccent, size: 20),
                                        onPressed: qtySelecionada < item.quantidade
                                            ? () {
                                                setDialogState(() {
                                                  selecionados[index] = (qtySelecionada + 1.0).clamp(0.0, item.quantidade);
                                                });
                                              }
                                            : null,
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Resumo Financeiro
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.03),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Subtotal selecionado:', style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12)),
                              Text('R\$ ${totalSelecionado.toStringAsFixed(2)}', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                            ],
                          ),
                          if (descontoProporcional > 0) ...[
                            const SizedBox(height: 4),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Desconto proporcional:', style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12)),
                                Text('- R\$ ${descontoProporcional.toStringAsFixed(2)}', style: const TextStyle(color: Colors.orangeAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ],
                          const Divider(color: Colors.white10, height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Total desta parte:', style: TextStyle(color: Colors.greenAccent, fontSize: 14, fontWeight: FontWeight.bold)),
                              Text(
                                'R\$ ${totalFinalPagar.toStringAsFixed(2)}',
                                style: const TextStyle(color: Colors.greenAccent, fontSize: 16, fontWeight: FontWeight.w900),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('CANCELAR', style: TextStyle(color: Colors.white54)),
                ),
                ElevatedButton(
                  onPressed: totalFinalPagar > 0.0
                      ? () async {
                          Navigator.pop(context);
                          await _processarDivisaoItens(dataService, selecionados, totalFinalPagar, descontoProporcional);
                        }
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueGrey.shade800,
                    disabledBackgroundColor: Colors.white.withOpacity(0.05),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  child: const Text(
                    'ABRIR VENDA (DEIXAR VALOR)',
                    style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),
                ElevatedButton(
                  onPressed: totalFinalPagar > 0.0
                      ? () => _pagarParteAgora(dataService, selecionados, totalFinalPagar, descontoProporcional)
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade700,
                    disabledBackgroundColor: Colors.white.withOpacity(0.05),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  child: const Text(
                    'PAGAR AGORA (FINALIZAR)',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _processarDivisaoItens(
    DataService dataService,
    Map<int, double> selecionados,
    double totalPagar,
    double descontoProporcional,
  ) async {
    final uuid = const Uuid();
    final produtosPedido = <ItemPedido>[];
    final servicosPedido = <ItemServico>[];

    // 1. Coleta os itens selecionados e cria as instâncias para o novo Pedido
    for (int i = 0; i < _carrinho.length; i++) {
      final qty = selecionados[i] ?? 0.0;
      if (qty <= 0.0) continue;

      final item = _carrinho[i];
      if (item.isServico) {
        servicosPedido.add(
          ItemServico(
            id: item.id,
            descricao: item.nome,
            valor: item.preco,
            valorAdicional: 0.0,
            dataAgendamento: DateTime.now(),
            observacao: item.observacao,
          ),
        );
      } else {
        produtosPedido.add(
          ItemPedido(
            id: item.id,
            nome: item.nome,
            preco: item.preco,
            quantidade: qty,
            observacao: item.observacao,
            fornecedorNome: item.fornecedorNome,
            adicionais: item.adicionais,
            unidadeVenda: item.unidadeVenda,
            quantidadeBaixa: item.quantidadeBaixa,
            precoSemPromocao: item.precoSemPromocao,
          ),
        );
      }
    }

    // Identificar a venda de forma rápida para a parte selecionada
    String? identificacao = _nomeNfce;
    if (_clienteSelecionado == null && (identificacao == null || identificacao.isEmpty)) {
      final controller = TextEditingController();
      identificacao = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E2E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Identificar Parte da Conta', style: TextStyle(color: Colors.white)),
          content: TextField(
            controller: controller,
            autofocus: true,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: 'Nome do Pagador ou Mesa',
              labelStyle: const TextStyle(color: Colors.white70),
              hintText: 'Ex: João, Parte 1, Mesa 05...',
              hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
              filled: true,
              fillColor: Colors.black26,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: const Text('IGNORAR', style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
              child: const Text('SALVAR', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
    }

    final String numero = _pedidoOriginal?.numero ?? dataService.getProximoNumeroVenda();
    final String numeroParte = '$numero-DIV';

    // Cria o Pedido para a parte selecionada
    final novoPedido = Pedido(
      id: uuid.v4(),
      numero: numeroParte,
      clienteId: _clienteSelecionado?.id,
      clienteNome: _clienteSelecionado?.nome ?? (identificacao?.isNotEmpty == true ? identificacao : 'Parte da Conta'),
      clienteTelefone: _clienteSelecionado?.telefone,
      clienteEndereco: _isDelivery && _enderecoEntrega != null 
          ? '${_enderecoEntrega!.logradouro}, ${_enderecoEntrega!.numero}' 
          : null,
      dataPedido: DateTime.now(),
      status: 'Pendente',
      produtos: produtosPedido,
      servicos: servicosPedido,
      pagamentos: [
        PagamentoPedido(
          id: uuid.v4(),
          tipo: TipoPagamento.outro,
          valor: totalPagar,
          recebido: false,
          observacao: 'Parte Dividida: ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}',
        ),
      ],
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      observacoes: 'Parte da venda original $numero',
      vendedorId: _vendedorSelecionado?.id,
      vendedorNome: _vendedorSelecionado?.nome,
    );

    // 2. Salva o novo Pedido no banco local / Supabase
    await dataService.addPedido(novoPedido);

    // 3. Atualiza o carrinho principal subtraindo as quantidades faturadas
    setState(() {
      for (int i = 0; i < _carrinho.length; i++) {
        final qty = selecionados[i] ?? 0.0;
        if (qty > 0.0) {
          final item = _carrinho[i];
          item.quantidade -= qty;
          if (item.desconto > 0.0) {
            final ratio = item.quantidade / (item.quantidade + qty);
            item.desconto = item.desconto * ratio;
          }
        }
      }
      _carrinho.removeWhere((item) => item.quantidade <= 0.0);
      _descontoTotal = (_descontoTotal - descontoProporcional).clamp(0.0, double.infinity);
    });

    // Salva o estado atualizado do carrinho no local storage
    await _storage.salvarLista(_keyCarrinhoPDV, _carrinho);

    // 4. Navega direto para a tela de pagamento do PDV
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Parte de R\$ ${totalPagar.toStringAsFixed(2)} separada para pagamento!'),
          backgroundColor: Colors.blueAccent,
        ),
      );
      
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PdvPage(
            pedidoInicial: novoPedido,
            abaInicial: 0,
            esconderAbaVenda: true,
          ),
        ),
      );
    }
  }

  Future<void> _pagarParteAgora(
    DataService dataService,
    Map<int, double> selecionados,
    double totalPortion,
    double descontoProporcional,
  ) async {
    if (!dataService.caixaAberto) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('E necessario abrir o caixa antes de realizar pagamentos'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: 'Abrir',
            textColor: Colors.white,
            onPressed: () {
              _solicitarAberturaCaixa(context, dataService);
            },
          ),
        ),
      );
      return;
    }

    Navigator.pop(context);

    setState(() {
      _gridSelectedIndex = -1;
      _cartSelectedIndex = -1;
      _focoNoCarrinho = false;
      _focoNasCategorias = false;
    });

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _DialogPagamentoPDV(
        subtotal: totalPortion + descontoProporcional,
        descontoTotal: descontoProporcional,
        totalCarrinho: totalPortion,
        pagamentosIniciais: const [],
        cliente: _clienteSelecionado,
        cpfCnpjInicial: _cpfNfce,
        nomeInicial: _nomeNfce,
        onDadosConsumidorChanged: (cpf, nome) {
          _cpfNfce = cpf;
          _nomeNfce = nome;
        },
        onConfirmar: (listaPagamentos, desc, acres) {
          Navigator.pop(context);
          _concluirVendaParcialComPagamentos(
            dataService,
            listaPagamentos,
            selecionados,
            totalPortion,
            descontoProporcional,
          );
        },
        onSalvarPendente: (listaPagamentos) {
          Navigator.pop(context);
          _processarDivisaoItens(
            dataService,
            selecionados,
            totalPortion,
            descontoProporcional,
          );
        },
      ),
    );
  }

  Future<void> _concluirVendaParcialComPagamentos(
    DataService dataService,
    List<PagamentoPedido> pagamentos,
    Map<int, double> selecionados,
    double totalPortion,
    double descontoProporcional,
  ) async {
    if (_estaFinalizando) return;

    final mesaParaLimparId = this.mesaParaLimparId;
    final mesaComandaOriginal = _mesaComandaVinculada;

    final itensVendaCapturados = <ItemCarrinho>[];
    for (int i = 0; i < _carrinho.length; i++) {
      final qty = selecionados[i] ?? 0.0;
      if (qty <= 0.0) continue;
      final item = _carrinho[i];
      itensVendaCapturados.add(
        ItemCarrinho(
          id: item.id,
          nome: item.nome,
          preco: item.preco,
          quantidade: qty,
          isServico: item.isServico,
          fornecedorNome: item.fornecedorNome,
          observacao: item.observacao,
          adicionais: item.adicionais,
          precoTabela: item.precoTabela,
        ),
      );
    }

    if (itensVendaCapturados.isEmpty) return;

    setState(() => _estaFinalizando = true);
    final uuid = const Uuid();

    try {
      final String numeroOriginal = _pedidoOriginal?.numero ?? dataService.getProximoNumeroVenda();
      final String numero = '$numeroOriginal-DIV';

      final pagamentosAtualizados = pagamentos.map((p) {
        final isInstantaneo =
            p.tipo == TipoPagamento.dinheiro ||
            p.tipo == TipoPagamento.pix ||
            p.tipo == TipoPagamento.cartaoCredito ||
            p.tipo == TipoPagamento.cartaoDebito;

        if (isInstantaneo && !p.isParcela) {
          return PagamentoPedido(
            id: p.id,
            tipo: p.tipo,
            valor: p.valor,
            recebido: true,
            dataRecebimento: DateTime.now(),
            dataVencimento: p.dataVencimento,
            parcelas: p.parcelas,
            numeroParcela: p.numeroParcela,
            parcelamentoId: p.parcelamentoId,
            observacao: p.observacao,
            valorRecebido: p.valorRecebido,
            troco: p.troco,
          );
        }
        return p;
      }).toList();

      final totalRecebido = pagamentosAtualizados
          .where((p) => p.recebido)
          .fold(0.0, (sum, p) => sum + p.valor);

      String statusPedido;
      if (totalRecebido >= totalPortion - 0.01) {
        statusPedido = 'Pago';
      } else {
        statusPedido = 'Pendente';
      }

      TipoPagamento tipoPagamentoVenda = pagamentosAtualizados.isNotEmpty
          ? pagamentosAtualizados.first.tipo
          : TipoPagamento.outro;

      final itensVenda = itensVendaCapturados
          .map(
            (item) => ItemVendaBalcao(
              id: item.id,
              nome: item.nome,
              precoUnitario: item.preco,
              precoOriginal: item.precoOriginal,
              precoSemPromocao: item.precoSemPromocao,
              quantidade: item.quantidade,
              isServico: item.isServico,
              fornecedorNome: item.fornecedorNome,
              observacao: item.observacao,            adicionais: item.adicionais,
            opcoesCombo: item.opcoesCombo,
            baixaProporcional: item.baixaProporcional,
            unidadeVenda: item.unidadeVenda,
            quantidadeBaixa: item.quantidadeBaixa,
            ),
          )
          .toList();

      final vendaId = uuid.v4();
      final String labelOrigem = tipoNome == 'Comanda' ? '[COMANDA]' : (tipoNome == 'Mesa' ? '[MESA]' : '[BALCÃO]');
      String? clienteNomeFinal = _clienteSelecionado?.nome ?? _nomeNfce;
      if (mesaNumero != null) {
        if (clienteNomeFinal == null || clienteNomeFinal.isEmpty) {
          clienteNomeFinal = '$labelOrigem $mesaNumero';
        } else if (!clienteNomeFinal.toUpperCase().contains(labelOrigem.toUpperCase())) {
          clienteNomeFinal = '$labelOrigem $mesaNumero - $clienteNomeFinal';
        }
      }

      final vendaBalcao = VendaBalcao(
        id: vendaId,
        numero: numero,
        dataVenda: DateTime.now(),
        clienteId: _clienteSelecionado?.id,
        clienteNome: clienteNomeFinal,
        clienteTelefone: _clienteSelecionado?.telefone,
        clienteCpfCnpj: _clienteSelecionado?.cpfCnpj ?? _cpfNfce,
        vendedorId: _vendedorSelecionado?.id,
        vendedorNome: _vendedorSelecionado?.nome,
        itens: itensVenda,
        tipoPagamento: tipoPagamentoVenda,
        pagamentos: pagamentosAtualizados,
        valorTotal: totalPortion,
        valorRecebido: totalRecebido > 0 ? totalRecebido : null,
        troco: pagamentosAtualizados
            .where((p) => p.troco != null && p.troco! > 0)
            .fold<double?>(null, (sum, p) => (sum ?? 0) + (p.troco ?? 0)),
        observacoes: 'Parte da venda original $numeroOriginal',
        origem: 'Venda Direta',
      );

      await dataService.addVendaBalcao(vendaBalcao);

      final temPagamentosPendentes = pagamentosAtualizados.any((p) => !p.recebido);
      final temFiadoOuCrediario = pagamentosAtualizados.any(
        (p) => p.tipo == TipoPagamento.fiado || p.tipo == TipoPagamento.crediario,
      );

      if (temFiadoOuCrediario || temPagamentosPendentes) {
        final produtosPedido = <ItemPedido>[];
        final servicosPedido = <ItemServico>[];

        for (final item in itensVenda) {
          if (item.isServico) {
            servicosPedido.add(ItemServico(
              id: item.id,
              descricao: item.nome,
              valor: item.precoUnitario,
              valorAdicional: 0.0,
              dataAgendamento: DateTime.now(),
              observacao: item.observacao,
            ));
          } else {
            produtosPedido.add(ItemPedido(
              id: item.id,
              nome: item.nome,
              preco: item.precoUnitario,
              quantidade: item.quantidade,
              observacao: item.observacao,
              fornecedorNome: item.fornecedorNome,
              unidadeVenda: item.unidadeVenda,
              quantidadeBaixa: item.quantidadeBaixa,
              precoSemPromocao: item.precoSemPromocao,
            ));
          }
        }

        final pedido = Pedido(
          id: vendaId,
          numero: numero,
          clienteId: _clienteSelecionado?.id,
          clienteNome: clienteNomeFinal,
          clienteTelefone: _clienteSelecionado?.telefone ?? vendaBalcao.clienteTelefone,
          dataPedido: vendaBalcao.dataVenda,
          status: statusPedido,
          total: totalPortion,
          produtos: produtosPedido,
          servicos: servicosPedido,
          pagamentos: pagamentosAtualizados,
          observacoes: 'Parte da venda original $numeroOriginal',
        );

        await dataService.addPedido(pedido);
      }

      await _registrarComissaoVendedorSeAplicavel(
        dataService: dataService,
        pedidoId: vendaId,
        pedidoNumero: numero,
        valorPedido: totalPortion,
        vendedor: _vendedorSelecionado,
      );

      setState(() {
        for (int i = 0; i < _carrinho.length; i++) {
          final qty = selecionados[i] ?? 0.0;
          if (qty > 0.0) {
            final item = _carrinho[i];
            item.quantidade -= qty;
            if (item.desconto > 0.0) {
              final ratio = item.quantidade / (item.quantidade + qty);
              item.desconto = item.desconto * ratio;
            }
          }
        }
        _carrinho.removeWhere((item) => item.quantidade <= 0.0);
        _descontoTotal = (_descontoTotal - descontoProporcional).clamp(0.0, double.infinity);

        if (_carrinho.isEmpty && mesaParaLimparId != null) {
          if (mesaComandaOriginal != null) {
            dataService.updateMesaComanda(mesaComandaOriginal.copyWith(status: 'Fechada'));
          }
          dataService.deleteMesaComanda(mesaParaLimparId);
        }
      });

      await _storage.salvarLista(_keyCarrinhoPDV, _carrinho);
      dataService.salvarImediatamente();

      final trocoTotal = pagamentosAtualizados
          .where((p) => p.troco != null && p.troco! > 0)
          .fold(0.0, (sum, p) => sum + (p.troco ?? 0));

      if (mounted) {
        _tocarSomPDV('notification.mp3', tipo: 'finalizar');
        _mostrarSucessoVenda(
          totalPortion,
          numero,
          vendaBalcao,
          troco: trocoTotal,
          titulo: 'PARTE DA CONTA PAGA!',
          infoExtra: 'FINALIZADO COM SUCESSO!',
          voltarAoFechar: _carrinho.isEmpty && mesaParaLimparId != null,
        );
      }
    } catch (e, stackTrace) {
      debugPrint('>>> ❌ ERRO AO FINALIZAR PARTE: $e\n$stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao finalizar parte da conta: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _estaFinalizando = false);
    }
  }

  void _mostrarDialogoTipoImpressaoPedido(BuildContext context, Pedido pedido) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.print, color: Colors.blueAccent),
            SizedBox(width: 12),
            Text('Imprimir Pedido?', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: const Text(
          'Deseja imprimir o comprovante deste pedido agora?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _navegarParaReceber();
            },
            child: const Text('NÃO', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              _imprimirPDFPedido(context, pedido, termico: true);
              _navegarParaReceber();
            },
            icon: const Icon(Icons.receipt_long),
            label: const Text('TÉRMICO (80mm)'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blueAccent,
              foregroundColor: Colors.white,
            ),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              _imprimirPDFPedido(context, pedido, termico: false);
              _navegarParaReceber();
            },
            icon: const Icon(Icons.picture_as_pdf),
            label: const Text('A4 (PDF)'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.indigo,
              foregroundColor: Colors.white,
            ),
          ),
          TextButton.icon(
            onPressed: () async {
              Navigator.pop(context);
              await _imprimirPDFPedido(context, pedido, termico: false, forcarPreview: true);
              _navegarParaReceber();
            },
            icon: const Icon(Icons.visibility, color: Colors.white70),
            label: const Text('VER PDF (A4) ANTES', style: TextStyle(color: Colors.white70)),
          ),
          TextButton.icon(
            onPressed: () async {
              Navigator.pop(context);
              await _imprimirPDFPedido(context, pedido, termico: true, forcarPreview: true);
              _navegarParaReceber();
            },
            icon: const Icon(Icons.receipt_long, color: Colors.orangeAccent),
            label: const Text('VER TÉRMICO ANTES', style: TextStyle(color: Colors.orangeAccent)),
          ),
        ],
      ),
    );
  }

  void _navegarParaReceber() {
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const PdvPage(
          abaInicial: 0, // 0 = Aba Receber
          esconderAbaVenda: true,
        ),
      ),
    );
  }

  Future<void> _imprimirPDFPedido(
    BuildContext context,
    Pedido pedido, {
    required bool termico,
    bool forcarPreview = false,
  }) async {
    final dataService = Provider.of<DataService>(context, listen: false);
    final authService = Provider.of<AuthService>(context, listen: false);
    
    // Tentar pegar do dataService se o authService estiver nulo
    Empresa? empresa = authService.empresaAtual ?? dataService.empresaAtual;
    
    if (empresa == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nenhuma empresa selecionada'), backgroundColor: Colors.red),
        );
      }
      return;
    }

    try {
      if (termico) {
        await PedidoPDFService.imprimirPDFTermico(
          pedido: pedido,
          empresa: empresa,
          context: context,
          forcarPreview: forcarPreview,
        );
      } else {
        await PedidoPDFService.imprimirPDF(
          pedido: pedido,
          empresa: empresa,
          context: context,
          forcarPreview: forcarPreview,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao imprimir: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _mostrarSucessoVendaSalva(String numeroVenda) {
    _mostrarNotificacaoSucesso(
      icone: Icons.bookmark_added_rounded,
      titulo: 'PEDIDO GERADO',
      subtitulo: numeroVenda,
      cor: Colors.orange,
      info: 'Disponível em "PEDIDOS"',
    );

    // Limpar estado completo da venda
    // _resetarTodaVenda();

    // Limpar carrinho salvo após finalizar venda
    // _limparCarrinhoSalvo();

  }

  /// Notificação inteligente e discreta para itens adicionados
  void _mostrarNotificacaoItemAdicionado({
    required String nome,
    required double quantidade,
    required double quantidadeTotal,
    required double preco,
    required bool jaExistia,
    required bool isServico,
    required double totalCarrinho,
  }) {
    late OverlayEntry overlayEntry;
    final valorItem = preco * quantidade;

    // Mensagem contextual baseada na situação
    String mensagem;
    IconData icone;
    Color cor;

    if (jaExistia) {
      mensagem = 'Quantidade atualizada';
      icone = Icons.add_circle_outline;
      cor = Colors.blueAccent;
    } else {
      mensagem = isServico ? 'Serviço adicionado' : 'Produto adicionado';
      icone = isServico
          ? Icons.build_circle_outlined
          : Icons.shopping_cart_outlined;
      cor = Colors.greenAccent;
    }

    overlayEntry = OverlayEntry(
      builder: (context) => _NotificacaoItemAdicionado(
        icone: icone,
        titulo: mensagem,
        nomeItem: nome,
        quantidade: quantidade,
        quantidadeTotal: quantidadeTotal,
        valorItem: valorItem,
        totalCarrinho: totalCarrinho,
        cor: cor,
        jaExistia: jaExistia,
        onDismiss: () => overlayEntry.remove(),
      ),
    );

    Overlay.of(context).insert(overlayEntry);
  }

  /// Notificação elegante no canto superior direito
  void _mostrarNotificacaoSucesso({
    required IconData icone,
    required String titulo,
    required String subtitulo,
    required Color cor,
    String? info,
    String? valorFormatado,
    Duration duracao = const Duration(seconds: 3),
  }) {
    late OverlayEntry overlayEntry;

    overlayEntry = OverlayEntry(
      builder: (context) => _NotificacaoSucesso(
        icone: icone,
        titulo: titulo,
        subtitulo: subtitulo,
        cor: cor,
        info: info,
        valorFormatado: valorFormatado,
        duracao: duracao,
        onDismiss: () => overlayEntry.remove(),
      ),
    );

    Overlay.of(context).insert(overlayEntry);
  }

  void _mostrarSucessoVendaCredito(
    double valor,
    String numeroVenda,
    TipoPagamento tipo,
    DateTime vencimento,
  ) {
    final formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final formatoData = DateFormat('dd/MM/yyyy');
    final tipoNome = tipo == TipoPagamento.crediario ? 'Crediário' : 'Boleto';

    _mostrarNotificacaoSucesso(
      icone: Icons.schedule_rounded,
      titulo: '$tipoNome Registrado',
      subtitulo: numeroVenda,
      cor: Colors.blue,
      valorFormatado: formatoMoeda.format(valor),
      info: 'Vence: ${formatoData.format(vencimento)}',
      duracao: const Duration(seconds: 4),
    );

    // Limpar estado completo da venda
    // _resetarTodaVenda();

    // Limpar carrinho salvo após finalizar venda
    // _limparCarrinhoSalvo();

  }

  void _mostrarSucessoVendaParcelada(
    int parcelas,
    double valorParcela,
    String numeroVenda,
  ) {
    final formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

    _mostrarNotificacaoSucesso(
      icone: Icons.calendar_month_rounded,
      titulo: 'Venda Parcelada',
      subtitulo: numeroVenda,
      cor: Colors.purple,
      valorFormatado: '${parcelas}x ${formatoMoeda.format(valorParcela)}',
      info: 'Total: ${formatoMoeda.format(_totalCarrinho)}',
      duracao: const Duration(seconds: 4),
    );

    // Limpar carrinho
    // Limpar estado completo da venda
    // _resetarTodaVenda();

    // Limpar carrinho salvo após finalizar venda
    // _limparCarrinhoSalvo();

  }

  void _abrirConferenciaItens() {
    if (_carrinho.isEmpty) return;
    
    showDialog(
      context: context,
      builder: (context) => _DialogConferenciaItens(
        carrinho: _carrinho,
        onRemoverItem: (index) {
           _removerItem(index);
        },
      ),
    );
  }

  void _mostrarSucessoVendaParcial(
    double valorPago,
    double valorRestante,
    String numeroVenda,
  ) {
    final formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

    _mostrarNotificacaoSucesso(
      icone: Icons.pending_rounded,
      titulo: 'Pagamento Parcial',
      subtitulo: numeroVenda,
      cor: Colors.orange,
      valorFormatado: formatoMoeda.format(valorPago),
      info: 'Faltando: ${formatoMoeda.format(valorRestante)}',
    );

    // _resetarTodaVenda();

    // Limpar carrinho e cliente salvos após finalizar
    // _limparCarrinhoSalvo();

  }

  void _mostrarSucessoVenda(
  double valor,
  String numeroVenda,
  VendaBalcao vendaBalcao, {
  double? troco,
  IconData? icone,
  Color? corBase,
  String? infoExtra,
  String? titulo,
  bool voltarAoFechar = false, // true quando chamado a partir do controle de mesas
}) {
  // Popup animado com dinheiro caindo
    _estaComPopupAberto = true;
    PopupSucessoVenda.mostrar(
      context,
      valor: valor,
      titulo: titulo ?? 'VENDA CONCLUÍDA!',
      subtitulo: numeroVenda,
      troco: troco,
      icone: icone,
      corBase: corBase,
      infoExtra: infoExtra,
      onDismiss: () {
        _estaComPopupAberto = false;
        // O estado já foi resetado em _concluirVendaComPagamentos antes de mostrar o popup.
        // Apenas garantimos o reset do foco e se necessário voltar para mesas.
        if (mounted) {
          _buscaFocusNode.requestFocus();
          if (voltarAoFechar) {
            Navigator.of(context).pop();
          }
        }
      },
    onEmitirNFCe: () => _emitirNFCe(
      vendaBalcao,
      cpfCnpjOverride: _cpfNfce ?? vendaBalcao.clienteCpfCnpj,
      nomeOverride: _nomeNfce ?? vendaBalcao.clienteNome,
    ),
    onWhatsApp: () => _enviarWhatsAppVenda(vendaBalcao),
    onImprimir: () {
      final authService = Provider.of<AuthService>(context, listen: false);
      final empresa = authService.empresaAtual;
      if (empresa != null) {
        VendaPDFService.imprimirPDFTermico(
          venda: vendaBalcao,
          empresa: empresa,
          context: context,
        );
      }
    },
  );

  // O carrinho e cliente serão limpos quando o popup for fechado (onDismiss)
}

  Future<void> _emitirNFCe(VendaBalcao vendaBalcao, {String? cpfCnpjOverride, String? nomeOverride, String? numeroOverride}) async {
    try {
      // Obter empresa atual
      final authService = Provider.of<AuthService>(context, listen: false);
      var empresa = authService.empresaAtual;

      if (empresa == null) {
        debugPrint('>>> [VendaDireta] ❌ Nenhuma empresa selecionada!');
        _mostrarErro(
          'Nenhuma empresa selecionada.\n\n'
          'SOLUÇÃO: Verifique se você está logado e se uma empresa foi selecionada no início do aplicativo.',
        );
        return;
      }

      // AUTO-RECUPERAÇÃO DE CERTIFICADO/SENHA DO SUPABASE
      final temCertOriginal =
          (empresa.configuracoes?['certificadoDigitalBytes'] != null &&
              (empresa.configuracoes!['certificadoDigitalBytes'] as String)
                  .isNotEmpty) ||
          (empresa.certificadoDigitalUrl != null &&
              empresa.certificadoDigitalUrl!.isNotEmpty) ||
          (empresa.configuracoes?['certificadoWindowsThumbprint'] != null);
      
      final temSenhaOriginal = empresa.senhaCertificado != null && empresa.senhaCertificado!.isNotEmpty;

      if (!temCertOriginal || !temSenhaOriginal) {
        debugPrint('>>> [VendaDireta] ⚠️ Certificado ou senha ausentes localmente. Tentando auto-recuperar do Supabase...');
        try {
          final supabaseService = SupabaseService.instance;
          if (SupabaseService.isAvailable) {
            final empresaSupabase = await supabaseService.buscarEmpresaPorSlug(empresa.slug);
            if (empresaSupabase != null) {
              final temCertSupabase =
                  (empresaSupabase.configuracoes?['certificadoDigitalBytes'] != null &&
                      (empresaSupabase.configuracoes!['certificadoDigitalBytes'] as String)
                          .isNotEmpty) ||
                  (empresaSupabase.certificadoDigitalUrl != null &&
                      empresaSupabase.certificadoDigitalUrl!.isNotEmpty) ||
                  (empresaSupabase.configuracoes?['certificadoWindowsThumbprint'] != null);
              
              final temSenhaSupabase = empresaSupabase.senhaCertificado != null && empresaSupabase.senhaCertificado!.isNotEmpty;

              if (temCertSupabase && temSenhaSupabase) {
                debugPrint('>>> [VendaDireta] ✓ Auto-recuperado do Supabase com sucesso!');
                // MERGE: preserva configurações que existem apenas no cache local
                // (perfis tributários, perfis de preço, bridgeNfceUrl, senha_admin,
                // ultimo_numero_nfce etc.). Sem este merge, a versão do Supabase
                // substituiria a local e essas configs sumiriam (mesmo bug do
                // "perfil tributário não persiste").
                final configLocal = empresa.configuracoes ?? {};
                final configSupabase = empresaSupabase.configuracoes ?? {};
                final configMerged = <String, dynamic>{...configSupabase};
                for (final entry in configLocal.entries) {
                  if (!configMerged.containsKey(entry.key) ||
                      configMerged[entry.key] == null) {
                    configMerged[entry.key] = entry.value;
                  }
                }
                if ((configLocal['perfis_tributarios'] as List?)?.isNotEmpty == true) {
                  configMerged['perfis_tributarios'] = configLocal['perfis_tributarios'];
                }
                if ((configLocal['perfis_preco'] as List?)?.isNotEmpty == true) {
                  configMerged['perfis_preco'] = configLocal['perfis_preco'];
                }
                final empresaComConfig = empresaSupabase.copyWith(configuracoes: configMerged);
                empresa = empresaComConfig;
                
                // Atualiza o AuthService e DataService localmente para corrigir o cache
                await authService.atualizarEmpresa(empresaComConfig);
                final dataService = Provider.of<DataService>(context, listen: false);
                dataService.setEmpresaAtual(empresaComConfig);
              }
            }
          }
        } catch (e) {
          debugPrint('>>> [VendaDireta] ⚠️ Erro na auto-recuperação do Supabase: $e');
        }
      }

      final empresaFinal = empresa!;

      debugPrint('>>> [VendaDireta] ========================================');
      debugPrint(
        '>>> [VendaDireta] Verificando empresa antes de emitir NFC-e...',
      );
      debugPrint(
        '>>> [VendaDireta] empresa: ${empresaFinal.razaoSocial}',
      );

      debugPrint(
        '>>> [VendaDireta] configuracoes: ${empresaFinal.configuracoes != null ? "presente" : "null"}',
      );
      if (empresaFinal.configuracoes != null) {
        debugPrint(
          '>>> [VendaDireta] configuracoes.keys: ${empresaFinal.configuracoes!.keys.toList()}',
        );
        final bytes = empresaFinal.configuracoes!['certificadoDigitalBytes'];
        debugPrint(
          '>>> [VendaDireta] certificadoDigitalBytes: ${bytes != null ? "presente (${(bytes as String).length} chars)" : "null"}',
        );
        debugPrint(
          '>>> [VendaDireta] certificadoWindowsThumbprint: ${empresaFinal.configuracoes!['certificadoWindowsThumbprint'] ?? "null"}',
        );
      }
      debugPrint(
        '>>> [VendaDireta] certificadoDigitalUrl: ${empresaFinal.certificadoDigitalUrl ?? "null"}',
      );
      debugPrint(
        '>>> [VendaDireta] senhaCertificado: ${empresaFinal.senhaCertificado != null && empresaFinal.senhaCertificado!.isNotEmpty ? "presente (${empresaFinal.senhaCertificado!.length} chars)" : "AUSENTE"}',
      );
      debugPrint('>>> [VendaDireta] ========================================');

      // Validar configurações NFC-e
      final temCertificado =
          (empresaFinal.configuracoes?['certificadoDigitalBytes'] != null &&
              (empresaFinal.configuracoes!['certificadoDigitalBytes'] as String)
                  .isNotEmpty) ||
          (empresaFinal.certificadoDigitalUrl != null &&
              empresaFinal.certificadoDigitalUrl!.isNotEmpty) ||
          (empresaFinal.configuracoes?['certificadoWindowsThumbprint'] != null);

      if (!temCertificado ||
          empresaFinal.senhaCertificado == null ||
          empresaFinal.senhaCertificado!.isEmpty) {
        debugPrint('>>> [VendaDireta] ❌ Certificado digital não configurado!');
        _mostrarErro(
          'Certificado digital não configurado. Configure na empresa.\n\n'
          'DIAGNÓSTICO:\n'
          '• Base64: ${empresaFinal.configuracoes?['certificadoDigitalBytes'] != null ? "presente" : "ausente"}\n'
          '• URL: ${empresaFinal.certificadoDigitalUrl != null ? "presente" : "ausente"}\n'
          '• Windows: ${empresaFinal.configuracoes?['certificadoWindowsThumbprint'] != null ? "presente" : "ausente"}\n'
          '• Senha: ${empresaFinal.senhaCertificado != null ? "presente" : "ausente"}',
        );
        return;
      }

      if (empresaFinal.csc == null || empresaFinal.cscIdToken == null) {
        _mostrarErro(
          'CSC (Código de Segurança do Contribuinte) não configurado.\n\n'
          'SOLUÇÃO: Acesse as configurações da empresa e informe o CSC e o ID do Token fornecidos pela SEFAZ.',
        );
        return;
      }

      // Mostrar diálogo de processamento
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const ExodoLoading(
          mensagem: 'Emitindo sua NFC-e...\nPor favor, aguarde.',
        ),
      );

      // Obter produtos da venda com quantidades
      final dataService = Provider.of<DataService>(context, listen: false);
      final produtos = <Produto>[];
      final quantidades = <String, double>{};

      for (final item in vendaBalcao.itens) {
        if (!item.isServico) {
          try {
            final produto = dataService.produtos.firstWhere(
              (p) => p.id == item.id,
            );
            produtos.add(produto);
            quantidades[produto.id] = item.quantidade.toDouble();
          } catch (e) {
            debugPrint('Produto não encontrado: ${item.id}');
          }
        }
      }

      if (produtos.isEmpty) {
        if (mounted) Navigator.pop(context);
        _mostrarErro(
          'Nenhum produto encontrado na venda para emitir NFC-e.\n\n'
          'SOLUÇÃO: Adicione produtos ao carrinho antes de tentar emitir a nota fiscal.',
        );
        return;
      }

      // ===== AJUSTE FISCAL: Taxa de Entrega e Serviço do Garçom =====
      // Configurações da empresa permitem incluir/excluir esses valores do
      // total da NFC-e (emissão fiscal). Quando desligados, o valor da
      // nota fiscal é apenas o subtotal dos produtos, sem os acréscimos.
      double ajusteFiscal = 0.0; // Valor a subtrair do total para a NFC-e

      // Taxa de entrega
      if (!empresaFinal.incluirTaxaEntregaNfce) {
        final taxaEntrega = vendaBalcao.deliveryInfo?.taxaEntrega ?? 0.0;
        if (taxaEntrega > 0.01) {
          ajusteFiscal += taxaEntrega;
          debugPrint('>>> [VendaDireta] NFC-e: taxa de entrega R\$ ${taxaEntrega.toStringAsFixed(2)} EXCLUÍDA do total fiscal');
        }
      }

      // Serviço do garçom (10%)
      if (!empresaFinal.incluirServicoGarcomNfce) {
        final itemGarcom = vendaBalcao.itens
            .where((i) => i.id == 'garcom' && i.isServico)
            .fold(0.0, (sum, i) => sum + i.subtotal);
        if (itemGarcom > 0.01) {
          ajusteFiscal += itemGarcom;
          debugPrint('>>> [VendaDireta] NFC-e: serviço do garçom R\$ ${itemGarcom.toStringAsFixed(2)} EXCLUÍDO do total fiscal');
        }
      }

      final valorTotalNfce = vendaBalcao.valorTotal - ajusteFiscal;

      // Converter pagamentos
      final pagamentos = <NFCePagamento>[];
      String _tipoNFCe(TipoPagamento t) {
        switch (t) {
          case TipoPagamento.dinheiro:
            return '01';
          case TipoPagamento.pix:
            return '99';
          case TipoPagamento.cartaoCredito:
            return '03';
          case TipoPagamento.cartaoDebito:
            return '04';
          default:
            return '99';
        }
      }

      // Se a venda tem múltiplas formas de pagamento, enviar cada uma individualmente
      final pagsSplit = vendaBalcao.pagamentos;
      if (pagsSplit.isNotEmpty) {
        for (final pag in pagsSplit) {
          pagamentos.add(
            NFCePagamento(tipo: _tipoNFCe(pag.tipo), valor: pag.valor),
          );
        }
        // Garantir que o total bata (soma dos splits deve igualar o total fiscal)
        final somaSplits = pagsSplit.fold(0.0, (s, p) => s + p.valor);
        if ((somaSplits - valorTotalNfce).abs() > 0.01 &&
            pagamentos.isNotEmpty) {
          // Ajustar a última parcela para fechar a diferença (arredondamento)
          pagamentos.last = NFCePagamento(
            tipo: pagamentos.last.tipo,
            valor: pagamentos.last.valor + (valorTotalNfce - somaSplits),
          );
        }
      } else {
        pagamentos.add(
          NFCePagamento(
            tipo: _tipoNFCe(vendaBalcao.tipoPagamento),
            valor: valorTotalNfce,
          ),
        );
      }

      // Usar URL configurada na empresa (importante para Túneis como Zrok/Ngrok)
      final configUrl = empresaFinal.configuracoes?['bridgeNfceUrl'] as String?;
      if (configUrl != null && configUrl.isNotEmpty) {
        debugPrint('>>> [VendaDireta] Configurando URL customizada para NFC-e: $configUrl');
        NFCeServiceFactory.configurarBackend(url: configUrl);
      } else {
        // Garantir que use o valor padrão do Factory se não houver config
        NFCeServiceFactory.configurarBackend(url: null);
      }

      // Verificar se backend está disponível (se configurado para usar)
      final backendDisponivel = await NFCeServiceFactory.verificarBackend();
      if (!backendDisponivel) {
        debugPrint(
          '>>> [VendaDireta] ❌ Backend/Bridge não disponível!',
        );
        if (mounted) Navigator.pop(context); // Fecha o loading
        _mostrarErro(
          'O Emissor NFC-e (Bridge) não está respondendo!\n\n'
          'SOLUÇÃO:\n'
          '1. Verifique se o programa ExodoNfceBridge.exe está aberto no seu computador.\n'
          '2. Certifique-se de que o computador tem acesso à internet.\n'
          '3. Tente fechar e abrir o Bridge novamente.',
        );
        return;
      } else {
        debugPrint(
          '>>> [VendaDireta] ✓ Bridge online, prosseguindo com emissão...',
        );
      }

      // Criar serviço via factory (escolhe automaticamente entre backend e local)
      final nfceService = NFCeServiceFactory.criar();

      // Emitir NFC-e
      // Usar ambiente configurado na empresa (padrão: homologação)
      final ambienteHomologacao = empresaFinal.ambienteHomologacao ?? true;

      debugPrint(
        '>>> [VendaDireta] Ambiente: ${ambienteHomologacao ? "Homologação" : "Produção"}',
      );

      // Obter usuário atual
      final usuario = authService.usuarioAtual;
      final serieUsuario = usuario?.serieNfce;

      // Usar número reservado (de emissão com erro anterior) para não pular numeração
      final numeroReservado = await NfceContingenciaService.obterNumeroReservado(empresaFinal.id);
      final numeroFinal = numeroOverride ?? 
          (numeroReservado != null ? numeroReservado.toString() : dataService.getProximoNumeroNfce(
            serie: serieUsuario?.toString() ?? '1',
            numeroInicial: usuario?.numeroInicialNfce ?? 1,
          ).toString());

      // Desconto total da venda (tabela de preços, promoções, desconto manual):
      // soma dos itens pelo preço de tabela/cadastro − total pago. Garante que o
      // XML da NFC-e fique consistente (Σ vProd − Σ vDesc = vNF).
      final somaItensNfce = produtos.fold(
        0.0,
        (sum, p) => sum + (p.preco * (quantidades[p.id] ?? 1.0)),
      );
      final valorDesconto = (somaItensNfce - valorTotalNfce) > 0.01
          ? somaItensNfce - valorTotalNfce
          : 0.0;

      final nfce = await nfceService.emitir(
        empresa: empresaFinal,
        produtos: produtos,
        quantidades: quantidades,
        pagamentos: pagamentos,
        valorTotal: valorTotalNfce,
        valorDesconto: valorDesconto,
        cpfCnpjConsumidor: cpfCnpjOverride ?? vendaBalcao.clienteCpfCnpj,
        nomeConsumidor: nomeOverride ?? vendaBalcao.clienteNome,
        observacoes: vendaBalcao.observacoes,
        vendaId: vendaBalcao.id,
        vendaNumero: numeroFinal,
        ambienteHomologacao: ambienteHomologacao,
        serie: serieUsuario,
      );

      // Salvar NFC-e no DataService
      await dataService.adicionarNFCe(nfce);

      // Salvar XML automaticamente em C:\ExodoNFCe\[CNPJ]\[YYYY-MM]\
      NfceXmlLocalService.salvarXmlAposEmissao(nfce: nfce, empresa: empresaFinal);

      // Fechar diálogo de processamento
      if (mounted) Navigator.pop(context);

      // Mostrar resultado
      if (nfce.status == 'autorizada') {
        // Mostrar mensagem de sucesso em verde bem visível
        _mostrarMensagemSucessoNFCe(nfce);
        _mostrarSucessoNFCe(nfce);
      } else if (nfce.status == 'contingencia') {
        // Modo contingência: aviso amarelo, não bloqueia a venda
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.black, size: 20),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '⚠️ NOTA EM CONTINGÊNCIA\nBridge offline. A nota será transmitida automaticamente quando a conexão retornar.',
                      style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              backgroundColor: Colors.amber,
              duration: const Duration(seconds: 6),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } else {
        _mostrarErro(
          'NFC-e ${nfce.status}: ${nfce.protocolo ?? "Erro desconhecido"}',
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);

        // Extrair mensagem de erro, removendo camadas de "Exception:"
        String mensagemErro = e.toString();
        debugPrint('>>> [NFCe] ========================================');
        debugPrint('>>> [NFCe] ERRO CAPTURADO');
        debugPrint('>>> [NFCe] Tipo: ${e.runtimeType}');
        debugPrint('>>> [NFCe] Mensagem original: $mensagemErro');
        debugPrint('>>> [NFCe] ========================================');

        // Remover múltiplas camadas de "Exception: Exception: ..."
        while (mensagemErro.startsWith('Exception: ')) {
          mensagemErro = mensagemErro.substring(11);
        }

        // Remover prefixo "Erro ao emitir NFC-e: " se existir
        if (mensagemErro.startsWith('Erro ao emitir NFC-e: ')) {
          mensagemErro = mensagemErro.substring(23);
        }

        // Remover prefixo "Erro ao carregar certificado: " se existir
        if (mensagemErro.startsWith('Erro ao carregar certificado: ')) {
          mensagemErro = mensagemErro.substring(31);
        }

        // Se mensagem estiver vazia após limpeza, criar uma genérica
        if (mensagemErro.trim().isEmpty) {
          mensagemErro =
              'Erro desconhecido ao emitir NFC-e.\n\n'
              'Verifique:\n'
              '1. Se o servidor backend está rodando\n'
              '2. Se o certificado está configurado corretamente\n'
              '3. Os logs do servidor para mais detalhes';
          debugPrint(
            '>>> [NFCe] ⚠️ Mensagem vazia detectada, usando mensagem genérica',
          );
        }

        // Verificar se é erro de certificado REAL do Flutter (raro agora com backend Python)
        final isErroCertificadoNoApp =
            (mensagemErro.contains('_Namespace') ||
                mensagemErro.contains('Unsupported operation')) &&
            !mensagemErro.contains('cStat');

        if (isErroCertificadoNoApp) {
          // Mensagem específica para erro de certificado NO FLUTTER
          mensagemErro = '''🔴 ERRO TÉCNICO NO APP
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Este erro ocorreu dentro do aplicativo Flutter ao tentar 
processar o certificado. 

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ POSSÍVEL SOLUÇÃO:
Re-exportar o certificado no formato PKCS#12 (.pfx) seguindo
o padrão padrão (sem opções avançadas).

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🔧 Erro técnico: $mensagemErro''';
        } else {
          // Verificar se é uma mensagem detalhada (contém instruções)
          final isMensagemDetalhada =
              mensagemErro.contains('\n') ||
              mensagemErro.contains('SOLUÇÃO') ||
              mensagemErro.contains('RE-EXPORTAR') ||
              mensagemErro.contains(
                'Biblioteca asn1lib não consegue processar',
              ) ||
              mensagemErro.contains('Erro ao processar certificado digital') ||
              mensagemErro.contains('ERRO:') ||
              mensagemErro.contains('🔴');

          if (!isMensagemDetalhada) {
            // Se não for mensagem detalhada, adicionar contexto
            mensagemErro = 'Erro ao emitir NFC-e: $mensagemErro';
          }
        }

        // Detectar certificado vencido / erro 403 da SEFAZ (mensagem amigável)
        final msgErroLower = mensagemErro.toLowerCase();
        final isCertificadoVencido =
            msgErroLower.contains('certificado digital vencido') ||
            msgErroLower.contains('certificado vencido') ||
            (mensagemErro.contains('403') &&
                (msgErroLower.contains('forbidden') ||
                    msgErroLower.contains('access is denied'))) ||
            msgErroLower.contains('rejeitado pela sefaz');

        // So substitui se a mensagem NAO ja vier do bridge novo (que ja e amigavel e tem a data)
        if (isCertificadoVencido &&
            !msgErroLower.contains('certificado digital')) {
          mensagemErro = '''🔴 CERTIFICADO DIGITAL VENCIDO
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
O certificado digital da empresa venceu e a SEFAZ está
recusando a emissão de NFC-e (erro 403).

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ COMO RENOVAR:
1. Entre em contato com a contabilidade / autoridade
   certificadora (ICP-Brasil) e renove o certificado A1.
2. Envie o novo arquivo (.pfx) e a nova senha para
   atualização no sistema.
3. Assim que o certificado renovado for cadastrado,
   tente emitir a nota novamente.

🔧 Detalhe técnico: $mensagemErro''';
        }

        debugPrint('>>> [NFCe] Mensagem de erro final: $mensagemErro');
        _mostrarErroEmissaoNfce(vendaBalcao, mensagemErro);
      }
    }
  }

  void _mostrarErroEmissaoNfce(VendaBalcao venda, String erro) {
    if (!mounted) return;

    // Detectar duplicidade (539) e extrair número da chave se possível
    String? numeroDuplicado;
    String? sugestaoNumero;
    bool isDuplicidade = erro.contains('[539]') || erro.toLowerCase().contains('duplicidade');

    if (isDuplicidade) {
      try {
        // Exemplo: chNFe:35260304829400000165650010000001211740930534
        final regExp = RegExp(r'chNFe:(\d{44})');
        final match = regExp.firstMatch(erro);
        if (match != null) {
          final chave = match.group(1)!;
          // Posição 25 a 34 da chave de acesso (9 dígitos) é o número da nota
          final numStr = chave.substring(25, 34);
          final numInt = int.tryParse(numStr);
          if (numInt != null) {
            numeroDuplicado = numInt.toString();
            // Próximo maior para encontrar o próximo livre
            sugestaoNumero = (numInt + 1).toString();
          }
        }
      } catch (e) {
        debugPrint('Erro ao extrair número da chave duplicada: $e');
      }
    }

    final dataService = Provider.of<DataService>(context, listen: false);
    final authServiceLocal = Provider.of<AuthService>(context, listen: false);
    final usuarioAtualLocal = authServiceLocal.usuarioAtual;
    final proximoDisponivel = dataService.getProximoNumeroNfce(
      serie: usuarioAtualLocal?.serieNfce.toString() ?? '1',
      numeroInicial: usuarioAtualLocal?.numeroInicialNfce ?? 1,
    ).toString();
    
    final controller = TextEditingController(text: sugestaoNumero ?? proximoDisponivel);

    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.85),
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(
              isDuplicidade ? Icons.warning_amber_rounded : Icons.error_outline,
              color: isDuplicidade ? Colors.orange : Colors.redAccent,
            ),
            const SizedBox(width: 10),
            Text(
              isDuplicidade ? 'Duplicidade de Nota' : 'Erro na NFC-e',
              style: const TextStyle(color: Colors.white),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.redAccent.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.redAccent.withOpacity(0.3)),
              ),
              child: Text(
                erro,
                style: const TextStyle(color: Colors.redAccent, fontSize: 13),
              ),
            ),
            if (isDuplicidade && numeroDuplicado != null) ...[
              const SizedBox(height: 15),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.orange.withOpacity(0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.info_outline, color: Colors.orange, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          'Nº que Duplicou: $numeroDuplicado',
                          style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Tente reemitir com um novo número (ex: o anterior ou o próximo):',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: controller,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'Novo Número da NFC-e',
                        labelStyle: const TextStyle(color: Colors.orange),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.orange.withOpacity(0.5)),
                        ),
                        focusedBorder: const OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.orange),
                        ),
                        isDense: true,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCELAR', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              _emitirNFCe(venda, numeroOverride: controller.text.trim());
            },
            icon: const Icon(Icons.refresh),
            label: const Text('REEMITIR AGORA'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _enviarWhatsAppVenda(VendaBalcao venda) async {
    final dataService = Provider.of<DataService>(context, listen: false);
    final empresa = dataService.empresaAtual;
    
    if (empresa == null) {
      _mostrarErro('Nenhuma empresa selecionada.');
      return;
    }

    // Identificar telefone do cliente
    String? telefone = _clienteSelecionado?.whatsapp ?? _clienteSelecionado?.telefone;
    
    // Se não tiver telefone, pedir ao usuário
    if (telefone == null || telefone.isEmpty) {
      final controller = TextEditingController();
      final result = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E2E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.chat_bubble_outline, color: Color(0xFF25D366)),
              SizedBox(width: 12),
              Text('Enviar Comprovante', style: TextStyle(color: Colors.white)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Digite o WhatsApp do cliente para enviar o recibo digital.',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: controller,
                autofocus: true,
                keyboardType: TextInputType.phone,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Telefone com DDD',
                  hintText: 'ex: 11999999999',
                  labelStyle: const TextStyle(color: Colors.white70),
                  filled: true,
                  fillColor: Colors.black26,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  prefixIcon: const Icon(Icons.phone, color: Colors.white54),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context), 
              child: const Text('CANCELAR', style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, controller.text),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF25D366)),
              child: const Text('ENVIAR AGORA'),
            ),
          ],
        ),
      );
      
      if (result == null || result.isEmpty) return;
      telefone = result;
    }

    // Mostrar loading
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: Card(
          color: Color(0xFF1E1E2E),
          child: Padding(
            padding: EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: Color(0xFF25D366)),
                SizedBox(height: 16),
                Text('Enviando via WhatsApp...', style: TextStyle(color: Colors.white)),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      final hasApi = empresa.whatsappApiUrl != null && empresa.whatsappApiKey != null;
      bool isConnected = false;
      
      if (hasApi) {
        final service = WhatsAppService.fromEmpresa(empresa);
        isConnected = await service.isConectado();
      }

      // Montar mensagem caprichada
      final buffer = StringBuffer();
      buffer.writeln('🛍️ *${empresa.razaoSocial.toUpperCase()}*');
      buffer.writeln('━━━━━━━━━━━━━━━━━━━━');
      buffer.writeln('✅ *VENDA CONCLUÍDA*');
      buffer.writeln('------------------------------------');
      buffer.writeln('📝 Pedido: #${venda.numero}');
      buffer.writeln('📅 Data: ${DateFormat('dd/MM/yyyy HH:mm').format(venda.dataVenda)}');
      buffer.writeln('👤 Cliente: ${venda.clienteNome ?? "Consumidor"}');
      buffer.writeln('------------------------------------');
      buffer.writeln('*DETALHES DA COMPRA:*');
      for (final item in venda.itens) {
        final totalItem = (item.precoUnitario * item.quantidade).toStringAsFixed(2);
        buffer.writeln('• ${item.quantidade}x ${item.nome}');
        buffer.writeln('  └ R\$ $totalItem');
      }
      buffer.writeln('------------------------------------');
      buffer.writeln('💰 *TOTAL: R\$ ${venda.valorTotal.toStringAsFixed(2)}*');
      if (venda.troco != null && venda.troco! > 0) {
        buffer.writeln('💵 Troco: R\$ ${venda.troco!.toStringAsFixed(2)}');
      }
      // 1. Perguntar o formato desejado (A4 ou 80mm)
      String? formato = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E2E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Escolha o Formato', style: TextStyle(color: Colors.white)),
          content: const Text(
            'Como você deseja enviar o comprovante?',
            style: TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, 'texto'),
              child: const Text('SOMENTE TEXTO', style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(context, '80mm'),
              icon: const Icon(Icons.receipt, size: 18),
              label: const Text('RECIBO 80MM'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            ),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(context, 'A4'),
              icon: const Icon(Icons.picture_as_pdf, size: 18),
              label: const Text('PDF A4'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
            ),
          ],
        ),
      );

      if (formato == null) {
        if (mounted) Navigator.pop(context);
        return;
      }

      bool sucesso = false;
      
      if (formato == 'texto') {
        if (hasApi && isConnected) {
          final service = WhatsAppService.fromEmpresa(empresa);
          sucesso = await service.enviarMensagem(telefone, buffer.toString());
        } else {
          // Fallback para link direto se não tiver API ou não estiver conectado
          sucesso = await WhatsAppService.abrirWhatsAppDireto(
            numero: telefone, 
            mensagem: buffer.toString()
          );
        }
      } else {
        if (!hasApi || !isConnected) {
          if (mounted) Navigator.pop(context);
          
          final confirmarManual = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              backgroundColor: const Color(0xFF1E1E2E),
              title: const Text('API Indisponível', style: TextStyle(color: Colors.white)),
              content: const Text(
                'A integração automática não está configurada. Deseja gerar o PDF e compartilhar usando o menu do seu aparelho?',
                style: TextStyle(color: Colors.white70),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('CANCELAR', style: TextStyle(color: Colors.white54)),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                  child: const Text('SIM, COMPARTILHAR'),
                ),
              ],
            ),
          );

          if (confirmarManual != true) return;
          
          // Se confirmou manual, gerar e compartilhar pelo menu nativo
          // Mostrar loading novamente pois o anterior foi fechado
          if (!mounted) return;
          showDialog(context: context, barrierDismissible: false, builder: (context) => const Center(child: CircularProgressIndicator()));
          
          try {
             // Converter VendaBalcao para Pedido temporário para usar o PDF Service
            final pedidoTemp = Pedido(
              id: venda.id,
              numero: venda.numero,
              dataPedido: venda.dataVenda,
              status: 'Pago',
              total: venda.valorTotal,
              produtos: venda.itens.where((i) => !i.isServico).map((i) => ItemPedido(
                id: i.id,
                nome: i.nome,
                quantidade: i.quantidade,
                preco: i.precoUnitario,
                observacao: i.observacao,
                fornecedorNome: i.fornecedorNome,
                adicionais: i.adicionais,
                unidadeVenda: i.unidadeVenda,
                quantidadeBaixa: i.quantidadeBaixa,
                precoSemPromocao: i.precoSemPromocao,
              )).toList(),
              servicos: venda.itens.where((i) => i.isServico).map((i) => ItemServico(
                id: i.id,
                descricao: i.nome,
                valor: i.precoUnitario,
                observacao: i.observacao,
              )).toList(),
              pagamentos: [
                PagamentoPedido(
                  id: 'pg-${venda.id}',
                  tipo: venda.tipoPagamento,
                  valor: venda.valorTotal,
                  recebido: true,
                  dataRecebimento: venda.dataVenda,
                )
              ],
              clienteId: venda.clienteId,
              clienteNome: venda.clienteNome,
              clienteTelefone: venda.clienteTelefone,
              clienteCpfCnpj: venda.clienteCpfCnpj,
              createdAt: venda.createdAt,
            );

            Uint8List pdfBytes;
            if (formato == '80mm') {
              pdfBytes = await PedidoPDFService.gerarPDFTermico(pedido: pedidoTemp, empresa: empresa);
            } else {
              pdfBytes = await PedidoPDFService.gerarPDF(pedido: pedidoTemp, empresa: empresa);
            }

            if (mounted) Navigator.pop(context); // Fecha loading
            
            await Printing.sharePdf(
              bytes: pdfBytes,
              filename: 'comprovante_${venda.numero}.pdf',
            );
            return;
          } catch (e) {
            if (mounted) Navigator.pop(context);
            _mostrarErro('Erro ao gerar PDF para compartilhamento: $e');
            return;
          }
        }

        final service = WhatsAppService.fromEmpresa(empresa);
        // Converter VendaBalcao para Pedido temporário para usar o PDF Service
        final pedidoTemp = Pedido(
          id: venda.id,
          numero: venda.numero,
          dataPedido: venda.dataVenda,
          status: 'Pago',
          total: venda.valorTotal,
          produtos: venda.itens.where((i) => !i.isServico).map((i) => ItemPedido(
            id: i.id,
            nome: i.nome,
            quantidade: i.quantidade,
            preco: i.precoUnitario,
            observacao: i.observacao,
            fornecedorNome: i.fornecedorNome,
            adicionais: i.adicionais,
          )).toList(),
          servicos: venda.itens.where((i) => i.isServico).map((i) => ItemServico(
            id: i.id,
            descricao: i.nome,
            valor: i.precoUnitario,
            observacao: i.observacao,
          )).toList(),
          pagamentos: [
            PagamentoPedido(
              id: 'pg-${venda.id}',
              tipo: venda.tipoPagamento,
              valor: venda.valorTotal,
              recebido: true,
              dataRecebimento: venda.dataVenda,
            )
          ],
          clienteId: venda.clienteId,
          clienteNome: venda.clienteNome,
          clienteTelefone: venda.clienteTelefone,
          clienteCpfCnpj: venda.clienteCpfCnpj,
          createdAt: venda.createdAt,
        );

        Uint8List pdfBytes;
        String fileName;
        
        if (formato == '80mm') {
          pdfBytes = await PedidoPDFService.gerarPDFTermico(pedido: pedidoTemp, empresa: empresa);
          fileName = 'recibo_${venda.numero}.pdf';
        } else {
          pdfBytes = await PedidoPDFService.gerarPDF(pedido: pedidoTemp, empresa: empresa);
          fileName = 'comprovante_${venda.numero}.pdf';
        }

        final base64Pdf = base64Encode(pdfBytes);
        
        sucesso = await service.enviarArquivo(
          numero: telefone,
          base64Content: base64Pdf,
          fileName: fileName,
          caption: 'Olá! Segue o seu comprovante da compra realizada em *${empresa.razaoSocial}*. 🛍️',
        );
      }

      final ok = sucesso;
      
      if (mounted) Navigator.pop(context); // Fecha loading
      
      if (ok) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.white),
                  SizedBox(width: 8),
                  Text('Comprovante enviado com sucesso!'),
                ],
              ), 
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        _mostrarErro('Não foi possível enviar a mensagem.\nVerifique se o número é válido e tem WhatsApp.');
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      _mostrarErro('Erro técnico ao enviar: $e');
    }
  }

  Future<void> _finalizarPedidoDelivery() async {
    if (_carrinho.isEmpty) {
      _mostrarErro('Carrinho está vazio.');
      return;
    }
    if (_enderecoEntrega == null) {
      _mostrarErro('Selecione um endereço para o Delivery.');
      return;
    }

    setState(() => _estaFinalizando = true);
    final dataService = Provider.of<DataService>(context, listen: false);
    final vendedorSelecionadoCapturado = _vendedorSelecionado;
    final uuid = const Uuid();
    
    try {
      final numero = dataService.getProximoNumeroPedido();
      final vendaId = uuid.v4();
      
      final itensVenda = _carrinho.map((item) => ItemVendaBalcao(
        id: item.id,
        nome: item.nome,
        precoUnitario: item.preco,
        precoOriginal: item.precoOriginal,
        precoSemPromocao: item.precoSemPromocao,
        quantidade: item.quantidade,
        isServico: item.isServico,
        fornecedorNome: item.fornecedorNome,
        observacao: item.observacao,
        adicionais: item.adicionais,
        opcoesCombo: item.opcoesCombo,
      baixaProporcional: item.baixaProporcional,
      unidadeVenda: item.unidadeVenda,
      quantidadeBaixa: item.quantidadeBaixa,
      )).toList();

      final deliveryInfo = DeliveryInfo(
        id: uuid.v4(),
        enderecoId: _enderecoEntrega!.id,
        logradouro: _enderecoEntrega!.logradouro,
        numero: _enderecoEntrega!.numero,
        bairro: _enderecoEntrega!.bairro,
        cidade: _enderecoEntrega!.cidade,
        uf: _enderecoEntrega!.uf,
        cep: _enderecoEntrega!.cep,
        taxaEntrega: _taxaEntrega,
        motoristaId: _motoristaId,
        motoristaNome: _motoristaNome,
        status: 'Pendente',
        valorParaTroco: _valorParaTroco,
        previsaoEntrega: _previsaoEntrega.trim().isEmpty ? null : _previsaoEntrega.trim(),
        dataPedido: DateTime.now(),
      );

      // Criar objeto VendaBalcao para facilidade de uso na UI/Impressão 
      // (Não será persistido via dataService.addVendaBalcao para não poluir o histórico antecipadamente)
      final vendaBalcao = VendaBalcao(
        id: vendaId,
        numero: numero,
        dataVenda: DateTime.now(),
        clienteId: _clienteSelecionado?.id,
        clienteNome: _clienteSelecionado?.nome ?? _nomeNfce ?? 'Delivery',
        clienteTelefone: _clienteSelecionado?.telefone,
        clienteCpfCnpj: _clienteSelecionado?.cpfCnpj ?? _cpfNfce,
        vendedorId: vendedorSelecionadoCapturado?.id,
        vendedorNome: vendedorSelecionadoCapturado?.nome,
        itens: itensVenda,
        tipoPagamento: _formaPagamentoDelivery ?? TipoPagamento.outro, // Lançado conforme registrado ou pendente
        valorTotal: _totalCarrinho,
        valorRecebido: 0,
        troco: 0,
        observacoes: _observacoesVenda,
        origem: _mesaComandaVinculada != null ? 'Mesa/Comanda' : 'Delivery',
        deliveryInfo: deliveryInfo,
      );

      // Criar o Pedido também para aparecer na lista de pedidos (obrigatório para delivery)
      final produtosPedido = <ItemPedido>[];
      final servicosPedido = <ItemServico>[];
      for (final item in _carrinho) {
        if (item.isServico) {
          servicosPedido.add(ItemServico(
            id: item.id,
            descricao: item.nome,
            valor: item.preco,
            dataAgendamento: DateTime.now(),
            observacao: item.observacao,
          ));
        } else {
          produtosPedido.add(ItemPedido(
            id: item.id,
            nome: item.nome,
            preco: item.preco,
            quantidade: item.quantidade,
            adicionais: item.adicionais,
            observacao: item.observacao,
            fornecedorNome: item.fornecedorNome,
            unidadeVenda: item.unidadeVenda,
            quantidadeBaixa: item.quantidadeBaixa,
            precoSemPromocao: item.precoSemPromocao,
          ));
        }
      }

      final pedido = Pedido(
        id: vendaId,
        numero: numero,
        clienteId: _clienteSelecionado?.id,
        clienteNome: vendaBalcao.clienteNome?.trim().isEmpty == true ? 'Delivery' : vendaBalcao.clienteNome,
        clienteTelefone: vendaBalcao.clienteTelefone,
        clienteEndereco: _enderecoEntrega != null 
            ? '${_enderecoEntrega!.logradouro}, ${_enderecoEntrega!.numero}' 
            : null,
        dataPedido: vendaBalcao.dataVenda,
        status: 'Pendente',
        total: vendaBalcao.valorTotal,
        produtos: produtosPedido,
        servicos: servicosPedido,
        pagamentos: [
          PagamentoPedido(
            id: uuid.v4(),
            tipo: _formaPagamentoDelivery ?? TipoPagamento.outro,
            valor: vendaBalcao.valorTotal,
            recebido: false,
          )
        ],
        deliveryInfo: deliveryInfo,
        observacoes: vendaBalcao.observacoes,
        vendedorId: vendedorSelecionadoCapturado?.id,
        vendedorNome: vendedorSelecionadoCapturado?.nome,
      );

      // SALVAR TUDO
      await dataService.addPedido(pedido);

      await _registrarComissaoVendedorSeAplicavel(
        dataService: dataService,
        pedidoId: pedido.id,
        pedidoNumero: pedido.numero,
        valorPedido: pedido.total,
        vendedor: vendedorSelecionadoCapturado,
      );
      
      // CRIAR REGISTRO DE ENTREGA (Para aparecer no Controle de Entregas)
      final registroEntrega = Entrega(
        id: uuid.v4(),
        pedidoId: pedido.id,
        pedidoNumero: pedido.numero,
        clienteNome: pedido.clienteNome ?? 'Delivery',
        clienteTelefone: pedido.clienteTelefone,
        enderecoEntrega: '${deliveryInfo.logradouro}, ${deliveryInfo.numero}',
        bairro: deliveryInfo.bairro,
        cidade: deliveryInfo.cidade,
        cep: deliveryInfo.cep,
        status: StatusEntrega.aguardando,
        dataCriacao: DateTime.now(),
        motoristaId: deliveryInfo.motoristaId,
        motoristaNome: deliveryInfo.motoristaNome,
        taxaEntrega: deliveryInfo.taxaEntrega,
        observacoes: pedido.observacoes,
      );
      await dataService.addEntrega(registroEntrega);
      
      // Limpar mesa/comanda vinculada se houver
      if (_mesaComandaVinculada != null) {
          final idMesa = _mesaComandaVinculada!.id;
          dataService.updateMesaComanda(_mesaComandaVinculada!.copyWith(status: 'Fechada'));
          await dataService.deleteMesaComanda(idMesa);
      }

      // Salvar imediatamente no storage
      dataService.salvarImediatamente();

      // Fechar diálogo antes de mostrar sucesso
      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }

      // Mostrar sucesso e opções de impressão
      if (mounted) {
        _mostrarSucessoPedidoGerado(vendaBalcao.numero);
        _mostrarDialogoTipoImpressaoPedido(context, pedido);
      }

    } catch (e) {
      debugPrint('>>> ❌ ERRO AO GERAR PEDIDO DELIVERY: $e');
      _mostrarErro('Erro ao gerar pedido de delivery: $e');
    } finally {
      if (mounted) setState(() => _estaFinalizando = false);
    }
  }

  Widget _buildViewModeOption(String label, IconData icon, bool isSelected, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blueAccent.withOpacity(0.15) : Colors.white.withOpacity(0.02),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? Colors.blueAccent : Colors.white10,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, color: isSelected ? Colors.blueAccent : Colors.white54, size: 24),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.white54,
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _abrirConfiguracoesPDV() async {
    final dataService = Provider.of<DataService>(context, listen: false);
    final authService = Provider.of<AuthService>(context, listen: false);
    final empresa = dataService.empresaAtual;
    if (empresa == null) return;

    // Mostrar dialog de carregamento rápido
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Colors.blueAccent)),
      ),
    );

    // Carregar configurações da balança e portas COM disponíveis
    final balancaService = BalancaService();
    final configBalanca = await balancaService.obterConfiguracao();
    final portasCOM = await balancaService.listarPortasCOM();
    if (configBalanca['diretorioToledo'].isEmpty) {
      configBalanca['diretorioToledo'] = await balancaService.obterDiretorioToledoPadrao();
    }

    // Fechar dialog de carregamento
    if (context.mounted) {
      Navigator.pop(context);
    }

    // Estado local para resposta instantânea
    bool selecionarFornecedorLocal = empresa.configuracoes?['selecionarFornecedorPDV'] == true;
    bool habilitarMesasComandasLocal = empresa.configuracoes?['habilitarMesasComandas'] != false; // true por padrão
    bool habilitarCozinhaLocal = empresa.configuracoes?['habilitarCozinha'] != false; // true por padrão
    bool somHabilitadoLocal = _somHabilitado;
    bool somAdicionarLocal = _somAdicionarHabilitado;
    bool somRemoverLocal = _somRemoverHabilitado;
    bool somFinalizarLocal = _somFinalizarHabilitado;
    bool alertarLimiteLocal = _alertarLimiteGaveta;
    double limiteValorLocal = _limiteGavetaValor;

    // Estados locais da balança
    bool balancaAtiva = configBalanca['ativo'] == true;
    String portaSelecionada = configBalanca['porta'] ?? 'COM1';
    int baudRateSelecionado = configBalanca['baudRate'] ?? 9600;
    bool usarMockBalanca = configBalanca['usarMock'] ?? true;
    double pesoMockBalanca = (configBalanca['pesoMock'] ?? 1.500).toDouble();
    String diretorioToledo = configBalanca['diretorioToledo'];
    String deptoToledo = configBalanca['deptoToledo'] ?? '01';
    int validadeToledo = configBalanca['validadeToledoDias'] ?? 0;

    // Garantir que a porta selecionada esteja na lista de portas válidas
    if (!portasCOM.contains(portaSelecionada)) {
      portasCOM.insert(0, portaSelecionada);
    }

    // Impressora padrão DESTE terminal (salva apenas na máquina local — cada PDV tem a sua)
    String impressoraTerminal =
        await ImpressaoService.getUltimaImpressora(empresaId: empresa.id) ?? '';
    if (impressoraTerminal.isEmpty) {
      impressoraTerminal =
          (empresa.configuracoes?['impressoraSelecionada'] as String?)?.trim() ?? '';
    }

    final TextEditingController pesoMockController = TextEditingController(text: pesoMockBalanca.toStringAsFixed(3));
    final TextEditingController dirToledoController = TextEditingController(text: diretorioToledo);
    final TextEditingController deptoToledoController = TextEditingController(text: deptoToledo);
    final TextEditingController validadeToledoController = TextEditingController(text: validadeToledo.toString());
    final TextEditingController limiteValorController = TextEditingController(text: limiteValorLocal.toStringAsFixed(2).replaceAll('.', ','));

    if (!context.mounted) return;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1E1E2E),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blueAccent.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.settings, color: Colors.blueAccent, size: 20),
                ),
                const SizedBox(width: 12),
                const Text('Configurações do PDV', style: TextStyle(color: Colors.white, fontSize: 18)),
              ],
            ),
            content: SizedBox(
              width: 500,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // --- CONFIGURAÇÕES GERAIS ---
                    const Text(
                      'Configurações do Sistema',
                      style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1.1),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.03),
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(
                          color: selecionarFornecedorLocal 
                              ? Colors.blueAccent.withOpacity(0.3) 
                              : Colors.white.withOpacity(0.05)
                        ),
                      ),
                      child: SwitchListTile(
                        title: const Text('Selecionar Fornecedor', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                        subtitle: const Text(
                          'Permite escolher o fornecedor do produto no momento da venda quando houver estoque particionado.',
                          style: TextStyle(color: Colors.white54, fontSize: 11),
                        ),
                        value: selecionarFornecedorLocal,
                        activeColor: Colors.blueAccent,
                        activeTrackColor: Colors.blueAccent.withOpacity(0.3),
                        inactiveThumbColor: Colors.grey,
                        inactiveTrackColor: Colors.white10,
                        onChanged: (value) {
                          setDialogState(() {
                            selecionarFornecedorLocal = value;
                          });
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.03),
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(
                          color: habilitarMesasComandasLocal 
                              ? Colors.purpleAccent.withOpacity(0.3) 
                              : Colors.white.withOpacity(0.05)
                        ),
                      ),
                      child: SwitchListTile(
                        title: const Text('Mesas e Comandas', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                        subtitle: const Text(
                          'Habilita os botões e rotinas de controle de mesas e comandas de clientes.',
                          style: TextStyle(color: Colors.white54, fontSize: 11),
                        ),
                        value: habilitarMesasComandasLocal,
                        activeColor: Colors.purpleAccent,
                        activeTrackColor: Colors.purpleAccent.withOpacity(0.3),
                        inactiveThumbColor: Colors.grey,
                        inactiveTrackColor: Colors.white10,
                        onChanged: (value) {
                          setDialogState(() {
                            habilitarMesasComandasLocal = value;
                          });
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.03),
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(
                          color: habilitarCozinhaLocal 
                              ? Colors.greenAccent.withOpacity(0.3) 
                              : Colors.white.withOpacity(0.05)
                        ),
                      ),
                      child: SwitchListTile(
                        title: const Text('Painel de Cozinha', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                        subtitle: const Text(
                          'Exibe o atalho para monitorar pedidos e preparos na Cozinha/Bar.',
                          style: TextStyle(color: Colors.white54, fontSize: 11),
                        ),
                        value: habilitarCozinhaLocal,
                        activeColor: Colors.greenAccent,
                        activeTrackColor: Colors.greenAccent.withOpacity(0.3),
                        inactiveThumbColor: Colors.grey,
                        inactiveTrackColor: Colors.white10,
                        onChanged: (value) {
                          setDialogState(() {
                            habilitarCozinhaLocal = value;
                          });
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.03),
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(
                          color: somHabilitadoLocal 
                              ? Colors.amberAccent.withOpacity(0.3) 
                              : Colors.white.withOpacity(0.05)
                        ),
                      ),
                      child: Column(
                        children: [
                          SwitchListTile(
                            title: const Text('Efeitos Sonoros do PDV', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                            subtitle: const Text(
                              'Ativa ou desativa os bips ao bipar itens, deletar e finalizar vendas.',
                              style: TextStyle(color: Colors.white54, fontSize: 11),
                            ),
                            value: somHabilitadoLocal,
                            activeColor: Colors.amberAccent,
                            activeTrackColor: Colors.amberAccent.withOpacity(0.3),
                            inactiveThumbColor: Colors.grey,
                            inactiveTrackColor: Colors.white10,
                            onChanged: (value) {
                              setDialogState(() {
                                somHabilitadoLocal = value;
                              });
                            },
                          ),
                          if (somHabilitadoLocal) ...[
                            const Divider(color: Colors.white10, height: 1),
                            Padding(
                              padding: const EdgeInsets.only(left: 16.0),
                              child: SwitchListTile(
                                title: const Text('Som ao Adicionar Item', style: TextStyle(color: Colors.white, fontSize: 13)),
                                value: somAdicionarLocal,
                                activeColor: Colors.amberAccent,
                                inactiveThumbColor: Colors.grey,
                                inactiveTrackColor: Colors.white10,
                                onChanged: (value) {
                                  setDialogState(() {
                                    somAdicionarLocal = value;
                                  });
                                },
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(left: 16.0),
                              child: SwitchListTile(
                                title: const Text('Som ao Remover Item', style: TextStyle(color: Colors.white, fontSize: 13)),
                                value: somRemoverLocal,
                                activeColor: Colors.amberAccent,
                                inactiveThumbColor: Colors.grey,
                                inactiveTrackColor: Colors.white10,
                                onChanged: (value) {
                                  setDialogState(() {
                                    somRemoverLocal = value;
                                  });
                                },
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(left: 16.0),
                              child: SwitchListTile(
                                title: const Text('Som ao Finalizar Venda', style: TextStyle(color: Colors.white, fontSize: 13)),
                                value: somFinalizarLocal,
                                activeColor: Colors.amberAccent,
                                inactiveThumbColor: Colors.grey,
                                inactiveTrackColor: Colors.white10,
                                onChanged: (value) {
                                  setDialogState(() {
                                    somFinalizarLocal = value;
                                  });
                                },
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.03),
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(
                          color: alertarLimiteLocal 
                              ? Colors.redAccent.withOpacity(0.3) 
                              : Colors.white.withOpacity(0.05)
                        ),
                      ),
                      child: Column(
                        children: [
                          SwitchListTile(
                            title: const Text('Aviso de Limite em Dinheiro', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                            subtitle: const Text(
                              'Alerta na tela quando o valor total em dinheiro na gaveta atingir o limite definido.',
                              style: TextStyle(color: Colors.white54, fontSize: 11),
                            ),
                            value: alertarLimiteLocal,
                            activeColor: Colors.redAccent,
                            activeTrackColor: Colors.redAccent.withOpacity(0.3),
                            inactiveThumbColor: Colors.grey,
                            inactiveTrackColor: Colors.white10,
                            onChanged: (value) {
                              setDialogState(() {
                                alertarLimiteLocal = value;
                              });
                            },
                          ),
                          if (alertarLimiteLocal) ...[
                            const Divider(color: Colors.white10, height: 1),
                            Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: TextFormField(
                                controller: limiteValorController,
                                style: const TextStyle(color: Colors.white, fontSize: 14),
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                decoration: const InputDecoration(
                                  labelText: 'Valor Limite na Gaveta (R\$)',
                                  labelStyle: TextStyle(color: Colors.redAccent, fontSize: 12),
                                  enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white10)),
                                  focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.redAccent)),
                                  prefixText: 'R\$ ',
                                  prefixStyle: TextStyle(color: Colors.white70),
                                ),
                                onChanged: (val) {
                                  final clean = val.replaceAll('.', '').replaceAll(',', '.');
                                  final valDouble = double.tryParse(clean);
                                  if (valDouble != null && valDouble > 0) {
                                    limiteValorLocal = valDouble;
                                  }
                                },
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.03),
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(color: Colors.white.withOpacity(0.05)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Visualização de Produtos',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                          const Text(
                            'Escolha como os produtos são exibidos no catálogo',
                            style: TextStyle(color: Colors.white54, fontSize: 11),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: _buildViewModeOption(
                                  'Grade de Quadros', 
                                  Icons.grid_view_rounded, 
                                  _viewMode == ViewMode.grid,
                                  () {
                                    setDialogState(() {
                                      _viewMode = ViewMode.grid;
                                    });
                                    setState(() {});
                                  }
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _buildViewModeOption(
                                  'Lista de Linhas', 
                                  Icons.view_headline_rounded, 
                                  _viewMode == ViewMode.list,
                                  () {
                                    setDialogState(() {
                                      _viewMode = ViewMode.list;
                                    });
                                    setState(() {});
                                  }
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),
                    // --- IMPRESSORA DESTE TERMINAL (local, por máquina) ---
                    const Text(
                      'Impressora deste Terminal',
                      style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1.1),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.03),
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(color: Colors.white.withOpacity(0.05)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.print_rounded, color: Colors.greenAccent, size: 20),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Impressora padrão deste terminal',
                                      style: TextStyle(color: Colors.white54, fontSize: 11),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      impressoraTerminal.isEmpty
                                          ? 'Nenhuma configurada (usará a padrão da empresa)'
                                          : impressoraTerminal,
                                      style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () async {
                                    final escolhida = await ImpressaoService.selecionarImpressoraPadrao(
                                      context,
                                      empresa: empresa,
                                      somenteLocal: true, // fica APENAS nesta máquina
                                    );
                                    if (escolhida != null && context.mounted) {
                                      setDialogState(() => impressoraTerminal = escolhida);
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text('✓ Impressora deste terminal: $escolhida'),
                                          backgroundColor: Colors.greenAccent,
                                          behavior: SnackBarBehavior.floating,
                                        ),
                                      );
                                    }
                                  },
                                  icon: const Icon(Icons.swap_horiz, size: 16),
                                  label: const Text('Trocar Impressora'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.greenAccent,
                                    side: BorderSide(color: Colors.greenAccent.withOpacity(0.5)),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: impressoraTerminal.isEmpty
                                      ? null
                                      : () async {
                                          final ok = await ImpressaoService.testarImpressora(impressoraTerminal, empresa: empresa);
                                          if (context.mounted) {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  ok
                                                      ? '✓ Teste enviado para: $impressoraTerminal'
                                                      : '✗ Falha ao testar: $impressoraTerminal',
                                                ),
                                                backgroundColor: ok ? Colors.greenAccent : Colors.redAccent,
                                                behavior: SnackBarBehavior.floating,
                                              ),
                                            );
                                          }
                                        },
                                  icon: const Icon(Icons.play_arrow, size: 16),
                                  label: const Text('Testar'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.greenAccent,
                                    side: BorderSide(color: Colors.greenAccent.withOpacity(0.5)),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),
                    // --- CONFIGURAÇÕES DA BALANÇA ---
                    const Text(
                      'Balança (Leitura Serial / COM)',
                      style: TextStyle(color: Colors.tealAccent, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1.1),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.02),
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(
                          color: balancaAtiva ? Colors.tealAccent.withOpacity(0.3) : Colors.white.withOpacity(0.05)
                        ),
                      ),
                      child: Column(
                        children: [
                          SwitchListTile(
                            title: const Text('Ativar Integração com Balança', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                            subtitle: const Text(
                              'Efetua leitura automática do peso ao selecionar produtos pesáveis.',
                              style: TextStyle(color: Colors.white54, fontSize: 11),
                            ),
                            value: balancaAtiva,
                            activeColor: Colors.tealAccent,
                            activeTrackColor: Colors.tealAccent.withOpacity(0.3),
                            inactiveThumbColor: Colors.grey,
                            inactiveTrackColor: Colors.white10,
                            onChanged: (value) {
                              setDialogState(() {
                                balancaAtiva = value;
                              });
                            },
                          ),
                          if (balancaAtiva) ...[
                            const Divider(color: Colors.white10, height: 16),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              child: Column(
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: DropdownButtonFormField<String>(
                                          value: portaSelecionada,
                                          dropdownColor: const Color(0xFF1E1E2E),
                                          style: const TextStyle(color: Colors.white, fontSize: 13),
                                          decoration: InputDecoration(
                                            labelText: 'Porta Serial',
                                            labelStyle: const TextStyle(color: Colors.tealAccent, fontSize: 12),
                                            enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white10)),
                                            focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.tealAccent)),
                                          ),
                                          items: portasCOM.map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(),
                                          onChanged: (val) {
                                            if (val != null) {
                                              setDialogState(() => portaSelecionada = val);
                                            }
                                          },
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: DropdownButtonFormField<int>(
                                          value: baudRateSelecionado,
                                          dropdownColor: const Color(0xFF1E1E2E),
                                          style: const TextStyle(color: Colors.white, fontSize: 13),
                                          decoration: InputDecoration(
                                            labelText: 'Baud Rate',
                                            labelStyle: const TextStyle(color: Colors.tealAccent, fontSize: 12),
                                            enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white10)),
                                            focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.tealAccent)),
                                          ),
                                          items: [2400, 4800, 9600, 19200, 38400, 115200]
                                              .map((b) => DropdownMenuItem(value: b, child: Text('$b bps')))
                                              .toList(),
                                          onChanged: (val) {
                                            if (val != null) {
                                              setDialogState(() => baudRateSelecionado = val);
                                            }
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  SwitchListTile(
                                    title: const Text('Modo Simulador (Sem Balança Física)', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                                    subtitle: const Text(
                                      'Retorna peso predefinido para testes sem conexão serial real.',
                                      style: TextStyle(color: Colors.white54, fontSize: 11),
                                    ),
                                    value: usarMockBalanca,
                                    activeColor: Colors.orangeAccent,
                                    activeTrackColor: Colors.orangeAccent.withOpacity(0.3),
                                    onChanged: (value) {
                                      setDialogState(() {
                                        usarMockBalanca = value;
                                      });
                                    },
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                  if (usarMockBalanca)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 8),
                                      child: TextFormField(
                                        controller: pesoMockController,
                                        style: const TextStyle(color: Colors.white),
                                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                        decoration: const InputDecoration(
                                          labelText: 'Peso Simulado Padrão (kg)',
                                          labelStyle: TextStyle(color: Colors.orangeAccent, fontSize: 12),
                                          enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white10)),
                                          focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.orangeAccent)),
                                          hintText: '1.500',
                                        ),
                                        onChanged: (val) {
                                          final clean = val.replaceAll(',', '.');
                                          final valDouble = double.tryParse(clean);
                                          if (valDouble != null && valDouble > 0) {
                                            pesoMockBalanca = valDouble;
                                          }
                                        },
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),
                    // --- EXPORTAÇÃO BALANÇA TOLEDO ---
                    const Text(
                      'Balanças Toledo (Carga de Produtos)',
                      style: TextStyle(color: Colors.purpleAccent, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1.1),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.02),
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(color: Colors.white.withOpacity(0.05)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextFormField(
                            controller: dirToledoController,
                            style: const TextStyle(color: Colors.white, fontSize: 13),
                            decoration: InputDecoration(
                              labelText: 'Diretório de Destino (txtitens.txt)',
                              labelStyle: const TextStyle(color: Colors.purpleAccent, fontSize: 12),
                              enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white10)),
                              focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.purpleAccent)),
                              suffixIcon: const Icon(Icons.folder, color: Colors.purpleAccent),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: deptoToledoController,
                                  style: const TextStyle(color: Colors.white, fontSize: 13),
                                  maxLength: 2,
                                  decoration: InputDecoration(
                                    labelText: 'Departamento (MGV)',
                                    labelStyle: const TextStyle(color: Colors.purpleAccent, fontSize: 12),
                                    enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white10)),
                                    focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.purpleAccent)),
                                    counterText: '',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: TextFormField(
                                  controller: validadeToledoController,
                                  style: const TextStyle(color: Colors.white, fontSize: 13),
                                  keyboardType: TextInputType.number,
                                  decoration: InputDecoration(
                                    labelText: 'Validade em Dias',
                                    labelStyle: const TextStyle(color: Colors.purpleAccent, fontSize: 12),
                                    enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white10)),
                                    focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.purpleAccent)),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed: () async {
                              final dir = dirToledoController.text.trim();
                              final depto = deptoToledoController.text.trim().isEmpty ? '01' : deptoToledoController.text.trim();
                              final validade = int.tryParse(validadeToledoController.text.trim()) ?? 0;

                              // Salva temporariamente para exportação consistente
                              final tempConfig = {
                                'ativo': balancaAtiva,
                                'porta': portaSelecionada,
                                'baudRate': baudRateSelecionado,
                                'usarMock': usarMockBalanca,
                                'pesoMock': pesoMockBalanca,
                                'diretorioToledo': dir,
                                'deptoToledo': depto,
                                'validadeToledoDias': validade,
                              };
                              await balancaService.salvarConfiguracao(tempConfig);

                              try {
                                final filePath = await balancaService.exportarItensToledo(dataService.produtos, dir);
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Arquivo exportado com sucesso em: $filePath'),
                                      backgroundColor: Colors.purple,
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                }
                              } catch (e) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Erro ao exportar arquivo: $e'),
                                      backgroundColor: Colors.redAccent,
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                }
                              }
                            },
                            icon: const Icon(Icons.scale, color: Colors.white, size: 18),
                            label: const Text('GERAR E EXPORTAR ARQUIVO TXTITENS.TXT', style: TextStyle(fontWeight: FontWeight.bold)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.purple,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),
                    const Text(
                      'As alterações do sistema são aplicadas em nuvem, e as configurações de impressora e balança são mantidas apenas neste computador/terminal.',
                      style: TextStyle(color: Colors.white38, fontSize: 11, fontStyle: FontStyle.italic),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('CANCELAR', style: TextStyle(color: Colors.white54)),
              ),
              ElevatedButton(
                onPressed: () async {
                  // 1. Salvar configurações na Empresa (Global)
                  final config = Map<String, dynamic>.from(empresa.configuracoes ?? {});
                  config['selecionarFornecedorPDV'] = selecionarFornecedorLocal;
                  config['venda_direta_view_mode'] = _viewMode == ViewMode.list ? 'list' : 'grid';
                  config['habilitarMesasComandas'] = habilitarMesasComandasLocal;
                  config['habilitarCozinha'] = habilitarCozinhaLocal;
                  
                  final novaEmpresa = empresa.copyWith(configuracoes: config);
                  await authService.atualizarEmpresa(novaEmpresa);
                  dataService.setEmpresaAtual(novaEmpresa);

                  // 2. Salvar configurações locais da balança
                  final depto = deptoToledoController.text.trim().isEmpty ? '01' : deptoToledoController.text.trim();
                  final validade = int.tryParse(validadeToledoController.text.trim()) ?? 0;
                  final novaConfigBalanca = {
                    'ativo': balancaAtiva,
                    'porta': portaSelecionada,
                    'baudRate': baudRateSelecionado,
                    'dataBits': 8,
                    'paridade': 'None',
                    'stopBits': 1,
                    'usarMock': usarMockBalanca,
                    'pesoMock': pesoMockBalanca,
                    'diretorioToledo': dirToledoController.text.trim(),
                    'deptoToledo': depto,
                    'validadeToledoDias': validade,
                  };
                  await balancaService.salvarConfiguracao(novaConfigBalanca);
                  
                    // Salvar se som está ativo
                    await _storage.salvar(_keySomPDV, somHabilitadoLocal);
                    await _storage.salvar(_keySomAdicionar, somAdicionarLocal);
                    await _storage.salvar(_keySomRemover, somRemoverLocal);
                    await _storage.salvar(_keySomFinalizar, somFinalizarLocal);
                    await _storage.salvar(_keyAlertarLimiteGaveta, alertarLimiteLocal);
                    await _storage.salvar(_keyLimiteGavetaValor, limiteValorLocal);

                    // Atualizar o estado da própria VendaDiretaPage
                    if (mounted) {
                      setState(() {
                        _somHabilitado = somHabilitadoLocal;
                        _somAdicionarHabilitado = somAdicionarLocal;
                        _somRemoverHabilitado = somRemoverLocal;
                        _somFinalizarHabilitado = somFinalizarLocal;
                        _alertarLimiteGaveta = alertarLimiteLocal;
                        _limiteGavetaValor = limiteValorLocal;
                      });
                    }
                  
                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Row(
                          children: [
                            const Icon(Icons.check_circle, color: Colors.white),
                            const SizedBox(width: 10),
                            const Text('Configurações salvas com sucesso!'),
                          ],
                        ),
                        backgroundColor: Colors.blueAccent,
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 5,
                  shadowColor: Colors.blueAccent.withOpacity(0.4),
                ),
                child: const Text('SALVAR ALTERAÇÕES', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _calcularTaxaAutomatica(EnderecoCliente end, DataService dataService, StateSetter setDialogState, TextEditingController taxaController) async {
    // 1. Prioridade: verificar se há taxa de entrega fixa por Bairro
    final taxaBairro = dataService.getTaxaEntregaPorBairro(end.bairro, cidade: end.cidade);
    if (taxaBairro != null) {
      setState(() {
        _taxaEntrega = taxaBairro.valor;
        _infoCalculoTaxa = 'Automática por bairro: ${end.bairro}';
        _calculandoTaxa = false;
      });
      taxaController.text = _taxaEntrega.toStringAsFixed(2);
      setDialogState(() {});
      return;
    }

    // 2. Segunda Prioridade: verificar se há configuração de Taxa por KM ativa
    final empresa = dataService.empresaAtual;
    final config = empresa?.configuracoes?['taxa_km_config'] as Map<String, dynamic>?;
    final habilitarKm = config?['habilitar'] as bool? ?? false;

    if (!habilitarKm) {
      setState(() {
        _infoCalculoTaxa = 'Bairro sem taxa cadastrada';
        _calculandoTaxa = false;
      });
      setDialogState(() {});
      return;
    }

    final cepOrigem = empresa?.cep?.replaceAll(RegExp(r'[^\d]'), '');
    final cepDestino = end.cep?.replaceAll(RegExp(r'[^\d]'), '');

    setState(() {
      _calculandoTaxa = true;
      _infoCalculoTaxa = 'Calculando distância...';
    });
    setDialogState(() {});

    try {
      double? dist;
      bool isGoogle = false;

      final googleKey = config?['google_maps_api_key'] as String?;
      if (googleKey != null && googleKey.isNotEmpty) {
        final addressOrigem = '${empresa?.endereco ?? ""}, ${empresa?.numero ?? ""}, ${empresa?.bairro ?? ""}, ${empresa?.cidade ?? ""}, ${empresa?.estado ?? ""}';
        final addressDestino = '${end.logradouro}, ${end.numero}, ${end.bairro}, ${end.cidade}, ${end.uf}';

        dist = await FreteService.obterDistanciaGoogleMaps(
          origem: addressOrigem,
          destino: addressDestino,
          apiKey: googleKey,
        );
        if (dist != null) {
          isGoogle = true;
        }
      }

      if (dist == null) {
        Map<String, double>? coordOrigem;
        Map<String, double>? coordDestino;

        if (cepOrigem != null && cepOrigem.length == 8) {
          coordOrigem = await FreteService.obterCoordenadasPorCEP(cepOrigem);
        }
        if (coordOrigem == null && empresa?.endereco != null && empresa!.endereco!.isNotEmpty) {
          final addressStr = '${empresa.endereco}, ${empresa.numero ?? ""}, ${empresa.cidade ?? ""}, ${empresa.estado ?? ""}';
          coordOrigem = await FreteService.obterCoordenadasPorEndereco(addressStr);
        }

        if (cepDestino != null && cepDestino.length == 8) {
          coordDestino = await FreteService.obterCoordenadasPorCEP(cepDestino);
        }
        if (coordDestino == null) {
          final addressStr = '${end.logradouro}, ${end.numero}, ${end.cidade}, ${end.uf}';
          coordDestino = await FreteService.obterCoordenadasPorEndereco(addressStr);
        }

        if (coordOrigem != null && coordDestino != null) {
          dist = FreteService.calcularDistancia(
            coordOrigem['lat']!,
            coordOrigem['lon']!,
            coordDestino['lat']!,
            coordDestino['lon']!,
          );
        }
      }

      if (dist != null) {
        final baseFee = (config?['valor_base'] as num?)?.toDouble() ?? 5.0;
        final valPerKm = (config?['valor_km'] as num?)?.toDouble() ?? 1.5;
        final valorMaximo = (config?['valor_maximo'] as num?)?.toDouble();
        final distLimite = (config?['distancia_maxima'] as num?)?.toDouble();
        final freteGratisMin = (config?['valor_minimo_frete_gratis'] as num?)?.toDouble();

        // Verificar limite de distância
        if (distLimite != null && dist > distLimite) {
          setState(() {
            _infoCalculoTaxa = 'Fora da área de entrega (${dist!.toStringAsFixed(1)} km - Limite: ${distLimite} km)';
            _calculandoTaxa = false;
          });
          setDialogState(() {});
          return;
        }

        // Verificar frete grátis por valor
        final subtotalItens = _carrinho.fold(0.0, (sum, item) => sum + item.subtotal);
        final valorTotalPedido = subtotalItens - _descontoTotal;
        
        if (freteGratisMin != null && valorTotalPedido >= freteGratisMin) {
          setState(() {
            _taxaEntrega = 0.0;
            _infoCalculoTaxa = 'Frete grátis por valor (${dist!.toStringAsFixed(1)} km)';
            _calculandoTaxa = false;
          });
          taxaController.text = '0.00';
          setDialogState(() {});
          return;
        }

        var valorCalculado = baseFee + (dist * valPerKm);
        if (valorMaximo != null && valorCalculado > valorMaximo) {
          valorCalculado = valorMaximo;
        }

        setState(() {
          _taxaEntrega = double.parse(valorCalculado.toStringAsFixed(2));
          _infoCalculoTaxa = isGoogle 
              ? 'Google Maps (Rota Real): ${dist!.toStringAsFixed(1)} km'
              : 'Automática por KM (Linha Reta): ${dist!.toStringAsFixed(1)} km';
          _calculandoTaxa = false;
        });
        taxaController.text = _taxaEntrega.toStringAsFixed(2);
        setDialogState(() {});
      } else {
        setState(() {
          _infoCalculoTaxa = 'Não foi possível obter a distância';
          _calculandoTaxa = false;
        });
        setDialogState(() {});
      }
    } catch (e) {
      debugPrint('>>> Erro ao calcular taxa automática por distância: $e');
      setState(() {
        _infoCalculoTaxa = 'Erro ao obter distância';
        _calculandoTaxa = false;
      });
      setDialogState(() {});
    }
  }

  void _abrirDialogDelivery() {
    if (_clienteSelecionado == null) {
      _mostrarErro('Selecione um cliente antes de configurar a Entrega.');
      return;
    }

    final dataService = Provider.of<DataService>(context, listen: false);
    final taxaController = TextEditingController(text: _taxaEntrega > 0 ? _taxaEntrega.toStringAsFixed(2) : '');
    final previsaoController = TextEditingController(text: _previsaoEntrega);
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final cliente = dataService.getClienteById(_clienteSelecionado!.id) ?? _clienteSelecionado!;
          
          if (_enderecoEntrega != null && _taxaEntrega == 0.0 && _infoCalculoTaxa.isEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _calcularTaxaAutomatica(_enderecoEntrega!, dataService, setDialogState, taxaController);
            });
          }
          
          // Combinar endereços da lista com o endereço principal se este estiver preenchido
          final List<EnderecoCliente> enderecos = [];
          
          // 1. Adicionar o endereço principal do cadastro base se existir
          if (cliente.endereco != null && cliente.endereco!.trim().isNotEmpty) {
            enderecos.add(EnderecoCliente(
              id: 'principal',
              tipo: 'Principal (Cadastro)',
              logradouro: cliente.endereco!,
              numero: cliente.numero ?? '',
              complemento: cliente.complemento,
              bairro: cliente.bairro ?? '',
              cidade: cliente.cidade ?? '',
              uf: cliente.estado ?? 'SP',
              cep: cliente.cep,
              isDefault: true,
            ));
          }
          
          // 2. Adicionar os outros endereços cadastrados na lista adicional
          for (final end in cliente.enderecos) {
            // Evitar duplicar se o principal for igual a um da lista
            bool duplicado = enderecos.any((e) => 
               e.logradouro.trim().toLowerCase() == end.logradouro.trim().toLowerCase() && 
               e.numero.trim().toLowerCase() == end.numero.trim().toLowerCase()
            );
            if (!duplicado) {
              enderecos.add(end);
            }
          }

          return AlertDialog(
            backgroundColor: const Color(0xFF1E1E2E),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orangeAccent.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.delivery_dining, color: Colors.orangeAccent, size: 24),
                ),
                const SizedBox(width: 12),
                const Text('Configurar Entrega', style: TextStyle(color: Colors.white, fontSize: 18)),
              ],
            ),
            content: SizedBox(
              width: 500,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Switch de Ativação
                    SwitchListTile(
                      title: const Text('Entrega em Domicílio', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      subtitle: const Text('Ativa as taxas e informações de entrega para esta venda.', style: TextStyle(color: Colors.white54, fontSize: 11)),
                      value: _isDelivery,
                      activeColor: Colors.orangeAccent,
                      onChanged: (value) {
                         setState(() => _isDelivery = value);
                         setDialogState(() {});
                      },
                    ),
                    const Divider(color: Colors.white10),
                    
                    if (_isDelivery) ...[
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8.0),
                        child: Text('ENDEREÇO DE ENTREGA', style: TextStyle(color: Colors.orangeAccent, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                      ),
                      
                      if (enderecos.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.03),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white10),
                          ),
                          child: const Text('Este cliente não possui endereços cadastrados.', style: TextStyle(color: Colors.white38, fontSize: 13)),
                        )
                      else
                        ...enderecos.map((end) {
                          final isSelected = _enderecoEntrega?.id == end.id;
                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              color: isSelected ? Colors.orangeAccent.withOpacity(0.1) : Colors.white.withOpacity(0.03),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: isSelected ? Colors.orangeAccent : Colors.white.withOpacity(0.05)),
                            ),
                            child: ListTile(
                              onTap: () {
                                setState(() => _enderecoEntrega = end);
                                setDialogState(() {});
                                _calcularTaxaAutomatica(end, dataService, setDialogState, taxaController);
                              },
                              leading: Icon(
                                end.tipo.contains('Principal') ? Icons.star_outline : (end.tipo == 'Trabalho' ? Icons.work_outline : (end.tipo == 'Casa' ? Icons.home_outlined : Icons.location_on_outlined)),
                                color: isSelected ? Colors.orangeAccent : Colors.white38,
                              ),
                              title: Text('${end.logradouro}, ${end.numero}', style: const TextStyle(color: Colors.white, fontSize: 14)),
                              subtitle: Text('${end.bairro} - ${end.cidade}/${end.uf}', style: const TextStyle(color: Colors.white54, fontSize: 12)),
                              trailing: isSelected ? const Icon(Icons.check_circle, color: Colors.orangeAccent, size: 20) : null,
                            ),
                          );
                        }),
                      
                      const SizedBox(height: 12),
                      // Botão Adicionar Endereço
                      TextButton.icon(
                        onPressed: () => _abrirDialogNovoEndereco(cliente, setDialogState),
                        icon: const Icon(Icons.add_location_alt_outlined, size: 18, color: Colors.orangeAccent),
                        label: const Text('ADICIONAR NOVO ENDEREÇO', style: TextStyle(color: Colors.orangeAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                      ),
                      
                      const SizedBox(height: 20),
                      const Text('LOGÍSTICA', style: TextStyle(color: Colors.orangeAccent, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                      const SizedBox(height: 12),
                      
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              onChanged: (value) {
                                setState(() {
                                  _taxaEntrega = double.tryParse(value) ?? 0.0;
                                  _infoCalculoTaxa = 'Manual';
                                });
                              },
                              controller: taxaController,
                              keyboardType: TextInputType.number,
                              style: const TextStyle(color: Colors.white),
                              decoration: InputDecoration(
                                labelText: 'Taxa de Entrega',
                                labelStyle: const TextStyle(color: Colors.white54),
                                prefixText: 'R\$ ',
                                helperText: _infoCalculoTaxa.isNotEmpty ? _infoCalculoTaxa : null,
                                helperStyle: TextStyle(
                                  color: _infoCalculoTaxa.contains('Erro') || _infoCalculoTaxa.contains('fora') || _infoCalculoTaxa.contains('Não foi')
                                      ? Colors.redAccent 
                                      : (_infoCalculoTaxa.contains('grátis') ? Colors.greenAccent : Colors.orangeAccent),
                                  fontSize: 10,
                                ),
                                suffixIcon: _calculandoTaxa 
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: Padding(
                                          padding: EdgeInsets.all(12),
                                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.orangeAccent),
                                        ),
                                      )
                                    : (_enderecoEntrega != null && _enderecoEntrega!.bairro.isNotEmpty && (_infoCalculoTaxa == 'Bairro sem taxa cadastrada' || _infoCalculoTaxa == 'Manual'))
                                        ? Tooltip(
                                            message: 'Salvar esta taxa como padrão para o bairro ${_enderecoEntrega!.bairro}',
                                            child: IconButton(
                                              icon: const Icon(Icons.save_outlined, color: Colors.greenAccent),
                                              onPressed: () async {
                                                final novaTaxa = TaxaEntrega(
                                                  id: const Uuid().v4(),
                                                  bairro: _enderecoEntrega!.bairro,
                                                  cidade: _enderecoEntrega!.cidade,
                                                  valor: _taxaEntrega,
                                                  createdAt: DateTime.now(),
                                                  updatedAt: DateTime.now(),
                                                );
                                                await dataService.addTaxaEntrega(novaTaxa);
                                                setState(() {
                                                  _infoCalculoTaxa = 'Automática por bairro: ${_enderecoEntrega!.bairro}';
                                                });
                                                setDialogState(() {});
                                                if (context.mounted) {
                                                  ScaffoldMessenger.of(context).showSnackBar(
                                                    SnackBar(
                                                      content: Text('Taxa padrão cadastrada para ${_enderecoEntrega!.bairro}!'),
                                                      backgroundColor: Colors.green,
                                                    ),
                                                  );
                                                }
                                              },
                                            ),
                                          )
                                        : null,
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white10)),
                                focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.orangeAccent)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: dataService.motoristas.any((m) => m.id == _motoristaId) ? _motoristaId : null,
                              decoration: InputDecoration(
                                labelText: 'Motorista / Motoboy',
                                labelStyle: const TextStyle(color: Colors.white54),
                                prefixIcon: const Icon(Icons.motorcycle, color: Colors.white24),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                enabledBorder: const OutlineInputBorder(borderSide: BorderSide(color: Colors.white10)),
                                focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: Colors.orangeAccent)),
                              ),
                              dropdownColor: const Color(0xFF1E1E2E),
                              style: const TextStyle(color: Colors.white),
                              items: [
                                const DropdownMenuItem(value: null, child: Text('Nenhum')),
                                ...dataService.motoristas.map((m) => DropdownMenuItem(
                                  value: m.id,
                                  child: Text(m.nome),
                                )),
                              ],
                              onChanged: (value) {
                                setState(() {
                                  _motoristaId = value;
                                  _motoristaNome = value != null ? dataService.motoristas.firstWhere((m) => m.id == value).nome : null;
                                });
                                setDialogState(() {});
                              },
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.add_circle, color: Colors.orangeAccent),
                            tooltip: 'Cadastrar Motorista',
                            onPressed: () => _abrirDialogCadastroMotorista(dataService, setDialogState),
                          ),
                        ],
                      ),
                      
                      const SizedBox(height: 16),
                      TextField(
                        controller: previsaoController,
                        onChanged: (value) {
                          setState(() => _previsaoEntrega = value);
                        },
                        keyboardType: TextInputType.text,
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        decoration: InputDecoration(
                          labelText: 'Previsão de Entrega',
                          hintText: 'Ex: 30-45 min ou 18:30',
                          hintStyle: const TextStyle(color: Colors.white24, fontSize: 12),
                          labelStyle: const TextStyle(color: Colors.white54, fontSize: 12),
                          prefixIcon: const Icon(Icons.schedule, color: Colors.orangeAccent, size: 18),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          enabledBorder: const OutlineInputBorder(borderSide: BorderSide(color: Colors.white10)),
                          focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: Colors.orangeAccent)),
                          filled: true,
                          fillColor: Colors.white.withOpacity(0.02),
                        ),
                      ),
                      
                      const SizedBox(height: 20),
                      const Text('FORMA DE RECEBIMENTO (PREFERENCIAL)', style: TextStyle(color: Colors.orangeAccent, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: TipoPagamento.values.map((tipo) {
                          final isSelected = _formaPagamentoDelivery == tipo;
                          return GestureDetector(
                            onTap: () {
                              setState(() => _formaPagamentoDelivery = tipo);
                              setDialogState(() {});
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: isSelected ? Colors.orangeAccent.withOpacity(0.2) : Colors.white.withOpacity(0.05),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: isSelected ? Colors.orangeAccent : Colors.white.withOpacity(0.1)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    _getIconeTipo(tipo), 
                                    size: 14, 
                                    color: isSelected ? Colors.orangeAccent : Colors.white38
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    tipo.nome, 
                                    style: TextStyle(
                                      color: isSelected ? Colors.orangeAccent : Colors.white70, 
                                      fontSize: 11,
                                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                    )
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      
                      if (_formaPagamentoDelivery == TipoPagamento.dinheiro) ...[
                        const SizedBox(height: 16),
                        TextField(
                          onChanged: (value) {
                            setState(() => _valorParaTroco = double.tryParse(value.replaceAll(',', '.')) ?? 0.0);
                          },
                          controller: TextEditingController(text: _valorParaTroco > 0 ? _valorParaTroco.toStringAsFixed(2).replaceFirst('.', ',') : ''),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          style: const TextStyle(color: Colors.white, fontSize: 13),
                          decoration: InputDecoration(
                            labelText: 'Troco para quanto?',
                            labelStyle: const TextStyle(color: Colors.white54, fontSize: 12),
                            prefixText: r'R$ ',
                            prefixStyle: const TextStyle(color: Colors.orangeAccent),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            enabledBorder: const OutlineInputBorder(borderSide: BorderSide(color: Colors.white10)),
                            focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: Colors.orangeAccent)),
                            filled: true,
                            fillColor: Colors.white.withOpacity(0.02),
                          ),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('FECHAR', style: TextStyle(color: Colors.white54)),
              ),
              if (_isDelivery) ...[
                OutlinedButton(
                  onPressed: () {
                    if (_isDelivery && _enderecoEntrega == null) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Selecione um endereço para a Entrega')));
                      return;
                    }
                    if (_estaFinalizando) return;
                    
                    Navigator.pop(context);
                    // Salva diretamente usando a forma de pagamento selecionada no diálogo de delivery
                    _salvarVendaPendente(dataService, [], mostrarPromptImpressao: true);
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.orangeAccent,
                    side: const BorderSide(color: Colors.orangeAccent),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('SALVAR PEDIDO', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () {
                    if (_isDelivery && _enderecoEntrega == null) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Selecione um endereço para a Entrega')));
                      return;
                    }
                    if (_estaFinalizando) return;
                    
                    // Abre o diálogo de pagamento para lançar pagamentos detalhados
                    Navigator.pop(context);
                    _mostrarDialogPagamento(dataService);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orangeAccent,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('IR PARA PAGAMENTO', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  void _abrirDialogCadastroMotorista(DataService dataService, StateSetter setDeliveryDialogState) {
    final nomeC = TextEditingController();
    final telefoneC = TextEditingController();
    final placaC = TextEditingController();
    String tipoComissao = 'Fixo por Entrega';
    final valorComissaoC = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: const Text('Cadastrar Motorista', style: TextStyle(color: Colors.white)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nomeC, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: 'Nome do Motorista', labelStyle: TextStyle(color: Colors.white54))),
              TextField(controller: telefoneC, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: 'Telefone', labelStyle: TextStyle(color: Colors.white54))),
              TextField(controller: placaC, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: 'Placa do Veículo (Opcional)', labelStyle: TextStyle(color: Colors.white54))),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: tipoComissao,
                dropdownColor: const Color(0xFF1E1E2E),
                items: ['Fixo por Entrega', 'Diária', 'Porcentagem'].map((t) => DropdownMenuItem(value: t, child: Text(t, style: const TextStyle(color: Colors.white)))).toList(),
                onChanged: (v) => tipoComissao = v ?? 'Fixo por Entrega',
                decoration: const InputDecoration(labelText: 'Tipo de Comissão', labelStyle: TextStyle(color: Colors.white54)),
              ),
              TextField(
                controller: valorComissaoC, 
                style: const TextStyle(color: Colors.white), 
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Valor Comissão/Diária (R\$ ou %)', labelStyle: TextStyle(color: Colors.white54)),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCELAR', style: TextStyle(color: Colors.white54))),
          ElevatedButton(
            onPressed: () async {
              if (nomeC.text.isEmpty) return;
              final novoMotoboy = Motorista(
                nome: nomeC.text,
                telefone: telefoneC.text,
                placaVeiculo: placaC.text,
                tipoComissao: tipoComissao,
                valorComissao: double.tryParse(valorComissaoC.text.replaceAll(',', '.')) ?? 0.0,
                taxaPadrao: double.tryParse(valorComissaoC.text.replaceAll(',', '.')) ?? 0.0, // fallback table
              );
              
              await dataService.addMotorista(novoMotoboy);
              
              setState(() {
                _motoristaId = novoMotoboy.id;
                _motoristaNome = novoMotoboy.nome;
              });
              setDeliveryDialogState(() {});
              if (mounted) Navigator.pop(context);
            },
            child: const Text('SALVAR'),
          ),
        ],
      ),
    );
  }

  void _abrirDialogNovoEndereco(Cliente cliente, StateSetter setDialogState) {
    final logradouroC = TextEditingController();
    final numeroC = TextEditingController();
    final bairroC = TextEditingController();
    final cidadeC = TextEditingController();
    final ufC = TextEditingController(text: 'SP');
    final cepC = TextEditingController();
    String tipo = 'Casa';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: const Text('Novo Endereço', style: TextStyle(color: Colors.white)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: tipo,
                dropdownColor: const Color(0xFF1E1E2E),
                items: ['Casa', 'Trabalho', 'Outro'].map((t) => DropdownMenuItem(value: t, child: Text(t, style: const TextStyle(color: Colors.white)))).toList(),
                onChanged: (v) => tipo = v ?? 'Casa',
                decoration: InputDecoration(labelText: 'Tipo', labelStyle: const TextStyle(color: Colors.white54)),
              ),
              TextField(controller: logradouroC, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: 'Rua/Logradouro', labelStyle: TextStyle(color: Colors.white54))),
              Row(
                children: [
                  Expanded(child: TextField(controller: numeroC, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: 'Número', labelStyle: TextStyle(color: Colors.white54)))),
                  const SizedBox(width: 8),
                  Expanded(child: TextField(controller: bairroC, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: 'Bairro', labelStyle: TextStyle(color: Colors.white54)))),
                ],
              ),
              Row(
                children: [
                  Expanded(child: TextField(controller: cidadeC, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: 'Cidade', labelStyle: TextStyle(color: Colors.white54)))),
                  const SizedBox(width: 8),
                  Expanded(child: TextField(controller: ufC, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: 'UF', labelStyle: TextStyle(color: Colors.white54)))),
                ],
              ),
              TextField(controller: cepC, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: 'CEP', labelStyle: TextStyle(color: Colors.white54))),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCELAR', style: TextStyle(color: Colors.white54))),
          ElevatedButton(
            onPressed: () {
              if (logradouroC.text.isEmpty) return;
              final novoEnd = EnderecoCliente(
                id: const Uuid().v4(),
                logradouro: logradouroC.text,
                numero: numeroC.text,
                bairro: bairroC.text,
                cidade: cidadeC.text,
                uf: ufC.text,
                cep: cepC.text,
                tipo: tipo,
              );
              
              final dataService = Provider.of<DataService>(context, listen: false);
              final List<EnderecoCliente> novosEnds = [...cliente.enderecos, novoEnd];
              dataService.updateCliente(cliente.copyWith(enderecos: novosEnds));
              
              setState(() {
                _clienteSelecionado = dataService.getClienteById(cliente.id) ?? cliente.copyWith(enderecos: novosEnds);
                _enderecoEntrega = novoEnd;
              });
              
              setDialogState(() {});
              Navigator.pop(context);
            },
            child: const Text('SALVAR ENDEREÇO'),
          ),
        ],
      ),
    );
  }

  void _mostrarErro(String mensagem) {
    if (!mounted) return;

    // Tentar extrair solução se houver (padrões variados)
    String? solucao;
    String mensagemLimpa = mensagem;
    
    final patterns = [
      'SOLUÇÃO:',
      'POSSÍVEL SOLUÇÃO:',
      'SOLUÇÃO SUGERIDA:',
      '✅ POSSÍVEL SOLUÇÃO:',
      'DICA:',
    ];

    for (var pattern in patterns) {
      if (mensagem.contains(pattern)) {
        final partes = mensagem.split(pattern);
        mensagemLimpa = partes[0].trim();
        solucao = partes[1].trim();
        // Limpar separadores visuais comuns se ficarem na mensagem
        mensagemLimpa = mensagemLimpa.replaceAll('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━', '').trim();
        solucao = solucao.replaceAll('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━', '').trim();
        break;
      }
    }

    // Se a mensagem for longa ou contiver quebras de linha, usar novo diálogo premium
    final isMensagemLonga =
        mensagem.length > 80 ||
        mensagem.contains('\n') ||
        mensagem.contains('cStat') ||
        mensagem.contains('Erro ao');

    if (isMensagemLonga) {
      ExodoErrorDialog.mostrar(
        context,
        titulo: mensagem.contains('cStat') ? 'Status da NFC-e' : 'Erro na Emissão',
        mensagem: mensagemLimpa,
        solucao: solucao,
        detalhes: mensagem.contains('traceback') || mensagem.contains('Exception') ? mensagem : null,
      );
    } else {
      // Usar SnackBar para mensagens curtas
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(mensagem),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  /// Mostra mensagem de sucesso em verde bem visível quando NFC-e é emitida
  void _mostrarMensagemSucessoNFCe(NFCe nfce) {
    if (!mounted) return;

    // Limpar mensagens anteriores
    ScaffoldMessenger.of(context).clearSnackBars();

    // Mostrar mensagem de sucesso em verde bem visível
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_circle,
                  color: Colors.white,
                  size: 32,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '✅ NFC-e EMITIDA COM SUCESSO!',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (nfce.numero != null)
                      Text(
                        'Número: ${nfce.numero}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    if (nfce.chaveAcesso != null)
                      Text(
                        'Chave: ${nfce.chaveAcesso!.substring(0, 20)}...',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.9),
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        backgroundColor: Colors.green.shade600,
        duration: const Duration(seconds: 5),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        elevation: 8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _mostrarSucessoNFCe(NFCe nfce) {
    if (!mounted) return;
    final authService = Provider.of<AuthService>(context, listen: false);
    final empresa = authService.empresaAtual;
    ExodoSuccessDialog.mostrar(context, nfce, empresa: empresa);
  }

  IconData _getIconeTipo(TipoPagamento tipo) {
    switch (tipo) {
      case TipoPagamento.dinheiro:
        return Icons.money;
      case TipoPagamento.pix:
        return Icons.qr_code;
      case TipoPagamento.cartaoCredito:
        return Icons.credit_card;
      case TipoPagamento.cartaoDebito:
        return Icons.credit_card;
      case TipoPagamento.boleto:
        return Icons.receipt;
      case TipoPagamento.crediario:
        return Icons.calendar_today;
      case TipoPagamento.fiado:
        return Icons.handshake;
      case TipoPagamento.outro:
        return Icons.more_horiz;
      case TipoPagamento.alimentacao:
        return Icons.restaurant;
      case TipoPagamento.transferencia:
        return Icons.swap_horiz;
    }
  }

  Widget _buildSeletorCliente(DataService dataService) {
    return _SeletorClienteWidget(
      dataService: dataService,
      clienteSelecionadoId: _clienteSelecionado?.id,
      onClienteSelecionado: (cliente) {
        setState(() {
          _clienteSelecionado = cliente;
          if (cliente.perfilPreco != null && cliente.perfilPreco!.isNotEmpty) {
            _tabelaPrecoAtiva = cliente.perfilPreco;
          }
        });
        _salvarClienteSelecionado();
        _salvarTabelaPreco();
        _recalcularPrecosCarrinho();
      },
      onRemoverCliente: () {
        setState(() => _clienteSelecionado = null);
        _salvarClienteSelecionado();
      },
    );
  }

  void _mostrarDetalhesCliente(Cliente cliente, DataService dataService) {
    // Buscar pedidos do cliente
    final pedidosCliente = dataService.pedidos
        .where((p) => p.clienteId == cliente.id)
        .toList();

    // Calcular estatísticas
    double totalCompras = 0;
    double totalAPrazo = 0;
    double totalPendente = 0;
    Map<String, double> produtosContagem = {};
    Map<String, int> servicosContagem = {};

    for (final pedido in pedidosCliente) {
      totalCompras += pedido.totalGeral;

      // Verificar se é venda a prazo
      final isPrazo = pedido.pagamentos.any(
        (p) =>
            p.tipo == TipoPagamento.crediario ||
            p.tipo == TipoPagamento.boleto ||
            p.tipo == TipoPagamento.outro,
      );

      if (isPrazo) {
        totalAPrazo += pedido.totalGeral;
        totalPendente += pedido.totalGeral - pedido.totalRecebido;
      }

      // Contar produtos
      for (final prod in pedido.produtos) {
        produtosContagem[prod.nome] =
            (produtosContagem[prod.nome] ?? 0) + prod.quantidade;
      }

      // Contar serviços
      for (final serv in pedido.servicos) {
        servicosContagem[serv.descricao] =
            (servicosContagem[serv.descricao] ?? 0) + 1;
      }
    }

    // Ordenar produtos por quantidade
    final produtosOrdenados = produtosContagem.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // Ordenar serviços por quantidade
    final servicosOrdenados = servicosContagem.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: const BoxDecoration(
          color: Color(0xFF1E1E2E),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            // Handle
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Cabeçalho com dados do cliente
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.blue.withOpacity(0.2),
                    Colors.purple.withOpacity(0.1),
                  ],
                ),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 30,
                        backgroundColor: Colors.blue.withOpacity(0.3),
                        child: Text(
                          cliente.nome.isNotEmpty
                              ? cliente.nome[0].toUpperCase()
                              : '?',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              cliente.nome,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(
                                  Icons.phone,
                                  size: 14,
                                  color: Colors.white.withOpacity(0.6),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  cliente.telefone,
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.7),
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                            if (cliente.email != null &&
                                cliente.email!.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  Icon(
                                    Icons.email,
                                    size: 14,
                                    color: Colors.white.withOpacity(0.6),
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      cliente.email!,
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.7),
                                        fontSize: 14,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      // Botão selecionar
                      ElevatedButton.icon(
                        onPressed: () {
                          setState(() => _clienteSelecionado = cliente);
                          _recalcularPrecosCarrinho();
                          _salvarClienteSelecionado();
                          Navigator.pop(context);
                        },
                        icon: const Icon(Icons.check, size: 18),
                        label: const Text('Selecionar'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Cards de estatísticas
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: _buildCardEstatisticaCliente(
                      'Total Compras',
                      formatoMoeda.format(totalCompras),
                      Icons.shopping_cart,
                      Colors.green,
                      '${pedidosCliente.length} pedidos',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildCardEstatisticaCliente(
                      'Vendas a Prazo',
                      formatoMoeda.format(totalAPrazo),
                      Icons.schedule,
                      Colors.orange,
                      totalPendente > 0
                          ? 'Pendente: ${formatoMoeda.format(totalPendente)}'
                          : 'Tudo pago',
                    ),
                  ),
                ],
              ),
            ),

            // Limite de crédito se existir
            if (cliente.limiteCredito != null && cliente.limiteCredito! > 0)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.amber.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.account_balance_wallet,
                      color: Colors.amber,
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Limite de Crédito',
                          style: TextStyle(
                            color: Colors.amber,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          formatoMoeda.format(cliente.limiteCredito),
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.8),
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Text(
                          'Disponível',
                          style: TextStyle(color: Colors.white54, fontSize: 12),
                        ),
                        Text(
                          formatoMoeda.format(
                            cliente.limiteCredito! - totalPendente,
                          ),
                          style: TextStyle(
                            color: (cliente.limiteCredito! - totalPendente) > 0
                                ? Colors.greenAccent
                                : Colors.redAccent,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 16),

            // Título seção produtos
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Icon(Icons.trending_up, color: Colors.white.withOpacity(0.7)),
                  const SizedBox(width: 8),
                  const Text(
                    'Produtos Mais Comprados',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 8),

            // Lista de produtos mais comprados
            Expanded(
              child: produtosOrdenados.isEmpty && servicosOrdenados.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.shopping_bag_outlined,
                            size: 48,
                            color: Colors.white.withOpacity(0.2),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Nenhuma compra registrada',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.5),
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      children: [
                        // Top produtos
                        ...produtosOrdenados.take(50).map((entry) {
                          final porcentagem = produtosOrdenados.isNotEmpty
                              ? entry.value / produtosOrdenados.first.value
                              : 0.0;
                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.05),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(
                                    Icons.inventory_2,
                                    color: Colors.blue,
                                    size: 18,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        entry.key,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w500,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 4),
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(4),
                                        child: LinearProgressIndicator(
                                          value: porcentagem,
                                          backgroundColor: Colors.white
                                              .withOpacity(0.1),
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(
                                                Colors.blue.withOpacity(0.7),
                                              ),
                                          minHeight: 4,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '${entry.value}x',
                                    style: const TextStyle(
                                      color: Colors.blue,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),

                        // Top serviços
                        if (servicosOrdenados.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Icon(
                                Icons.build,
                                color: Colors.white.withOpacity(0.7),
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                'Serviços Mais Utilizados',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          ...servicosOrdenados.take(50).map((entry) {
                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.purple.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.build,
                                    color: Colors.purple,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      entry.key,
                                      style: const TextStyle(
                                        color: Colors.white,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.purple.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      '${entry.value}x',
                                      style: const TextStyle(
                                        color: Colors.purple,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                        ],

                        const SizedBox(height: 16),
                      ],
                    ),
            ),

            // Botão de editar cadastro
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E2E),
                border: Border(
                  top: BorderSide(color: Colors.white.withOpacity(0.1)),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        Navigator.pop(context);
                        final clienteAtualizado = await Navigator.push<Cliente>(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                ClienteDetalhesPage(cliente: cliente),
                          ),
                        );
                        if (clienteAtualizado != null) {
                          setState(
                            () => _clienteSelecionado = clienteAtualizado,
                          );
                          _salvarClienteSelecionado();
                        }
                      },
                      icon: const Icon(Icons.edit),
                      label: const Text('Editar Cadastro'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white70,
                        side: const BorderSide(color: Colors.white24),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        setState(() => _clienteSelecionado = cliente);
                        _salvarClienteSelecionado();
                        Navigator.pop(context);
                      },
                      icon: const Icon(Icons.shopping_cart),
                      label: const Text('Usar nesta Venda'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCardEstatisticaCliente(
    String titulo,
    String valor,
    IconData icone,
    Color cor,
    String subtitulo,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cor.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icone, color: cor, size: 20),
              const SizedBox(width: 8),
              Text(
                titulo,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.7),
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            valor,
            style: TextStyle(
              color: cor,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitulo,
            style: TextStyle(
              color: Colors.white.withOpacity(0.5),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  /// Constrói o logo da empresa ou o logo padrão
  Widget _buildLogoEmpresa(BuildContext context) {
    final authService = Provider.of<AuthService>(context, listen: false);
    final empresa = authService.empresaAtual;

    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final isMobile = screenWidth < 600;
    final isSmallHeight = screenHeight < 750;

    // Se a empresa tem logoUrl, mostrar a logo da empresa
    if (empresa?.logoUrl != null && empresa!.logoUrl!.isNotEmpty) {
      return Container(
        height: isSmallHeight ? 32 : 40,
        constraints: BoxConstraints(maxWidth: isMobile ? 120 : 200),
        child: Image.network(
          empresa.logoUrl!,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) {
            // Se der erro ao carregar, mostrar logo padrão
            return ExodoLogoCompact(fontSize: isSmallHeight ? 22 : 28);
          },
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return SizedBox(
              width: isSmallHeight ? 32 : 40,
              height: isSmallHeight ? 32 : 40,
              child: const Center(
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.orange),
                ),
              ),
            );
          },
        ),
      );
    }

    // Caso contrário, mostrar logo padrão "êxodo systems"
    return ExodoLogo(
      fontSize: isSmallHeight ? 20 : 24,
      showSubtitle: !isSmallHeight,
      isVertical: false,
      showPhoenix: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final dataService = Provider.of<DataService>(context);
    final authService = Provider.of<AuthService>(context, listen: false);
    final usuarioLogado = authService.usuarioAtual;
    dataService.responsavelAtivo = usuarioLogado?.email ?? usuarioLogado?.nome;

    // OTIMIZAÇÃO CRÍTICA: Se o popup de sucesso está aberto, não re-processamos nada em background.
    // Isso evita que o clique nos botões do popup (Imprimir/Fechar) pareça travado
    // enquanto o Firebase sincroniza 6.5k produtos no fundo.
    if (_estaComPopupAberto && _cachedItens != null) {
       return _buildScaffoldContexto(context, dataService, _cachedItens!, _cachedCategorias!, _cachedProdutosCategoria!);
    }

    // MEMOIZATION: Só re-processar busca se o termo, categoria ou o próprio DataService mudou significativamente
    final agora = DateTime.now();
    final termoAtual = _termoBusca;
    final catAtiva = _categoriaAtiva;
    
    // Se o cache é recente (< 1s) e os parâmetros são iguais, usamos o cache
    if (_cachedItens != null && 
        _ultimoTermoCache == termoAtual && 
        _ultimaCategoriaCache == catAtiva &&
        _ultimaAtualizacaoCache != null &&
        agora.difference(_ultimaAtualizacaoCache!).inMilliseconds < 1000) {
       return _buildScaffoldContexto(context, dataService, _cachedItens!, _cachedCategorias!, _cachedProdutosCategoria!);
    }

    final itensEncontrados = _buscarItens(dataService);
    final categorias = _getCategorias(dataService);
    final produtosCategoria = _getProdutosPorCategoria(dataService);
    
    // Atualizar cache
    _cachedItens = itensEncontrados;
    _cachedCategorias = categorias;
    _cachedProdutosCategoria = produtosCategoria;
    _ultimoTermoCache = termoAtual;
    _ultimaCategoriaCache = catAtiva;
    _ultimaAtualizacaoCache = agora;

    return _buildScaffoldContexto(context, dataService, itensEncontrados, categorias, produtosCategoria);
  }

  Widget _buildScaffoldContexto(
    BuildContext context, 
    DataService dataService, 
    List<dynamic> itensEncontrados,
    List<String> categorias,
    List<Produto> produtosCategoria
  ) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final isVerySmallHeight = screenHeight < 650;
    final isSmallHeight = screenHeight < 750;

    // Calcular colunas dinamicamente para navegação por teclado
    int crossAxisCount = 2;
    if (screenWidth >= 1600) {
      crossAxisCount = 5;
    } else if (screenWidth >= 1100) {
      crossAxisCount = 4;
    } else if (screenWidth >= 800) {
      crossAxisCount = 3;
    }

    // Verificar se já existe um Scaffold no contexto
    final hasScaffold = Scaffold.maybeOf(context) != null;

    final content = GestureDetector(
      onTap: () {
        if (!_atalhosFocusNode.hasFocus &&
            !_buscaFocusNode.hasFocus) {
          _atalhosFocusNode.requestFocus();
        }
      },
      child: Focus(
        focusNode: _atalhosFocusNode,
        autofocus: true,
        onFocusChange: (hasFocus) {
          // Garante que o estado de foco visual seja atualizado se necessário
        },
        onKeyEvent: (node, event) {
        if (event is KeyRepeatEvent) return KeyEventResult.ignored;
        if (event is! KeyDownEvent) return KeyEventResult.ignored;

        final key = event.logicalKey;
        
        // Debug: mostrar tecla pressionada
        debugPrint('[PDV TECLADO] Tecla: ${key.debugName}, focoNoCarrinho: $_focoNoCarrinho, focoNasCategorias: $_focoNasCategorias, gridIndex: $_gridSelectedIndex');

        // Tecla ESC - Limpar carrinho
        if (key == LogicalKeyboardKey.escape) {
          _limparCarrinho();
          return KeyEventResult.handled;
        }

        // Tecla F6 - Selecionar Cliente
        if (key == LogicalKeyboardKey.f6) {
          _selecionarCliente(dataService);
          return KeyEventResult.handled;
        }

        // Tecla F7 - Registrar Despesa (Sangria / CP)
        if (key == LogicalKeyboardKey.f7) {
          _abrirLancamentoDespesa();
          return KeyEventResult.handled;
        }




        // Tecla F2 - Focar Campo de Busca
        if (key == LogicalKeyboardKey.f2) {
          _buscaFocusNode.requestFocus();
          setState(() {
            _focoNoCarrinho = false;
            _focoNasCategorias = false;
            _gridSelectedIndex = -1;
            _cartSelectedIndex = -1;
            _categoriaSelectedIndex = -1;
          });
          return KeyEventResult.handled;
        }

        // Tecla F4 - Focar Categorias
        if (key == LogicalKeyboardKey.f4) {
          setState(() {
            _focoNasCategorias = true;
            _categoriaSelectedIndex = 0;
            _focoNoCarrinho = false;
            _gridSelectedIndex = -1;
            _cartSelectedIndex = -1;
            _atalhosFocusNode.requestFocus();
          });
          return KeyEventResult.handled;
        }

        // Tecla CONTROL + Shift - Focar Carrinho rapidamente (removido Shift puro por conflito com asterisco)
        if ((key == LogicalKeyboardKey.shiftLeft || key == LogicalKeyboardKey.shiftRight) && HardwareKeyboard.instance.isControlPressed) {
          if (_carrinho.isNotEmpty) {
            setState(() {
              _focoNoCarrinho = true;
              _cartSelectedIndex = 0;
              _focoNasCategorias = false;
              _gridSelectedIndex = -1;
              _categoriaSelectedIndex = -1;
              _atalhosFocusNode.requestFocus();
            });
          }
          return KeyEventResult.handled;
        }

        // Tecla CONTROL - Conferência de Itens
        if (key == LogicalKeyboardKey.controlLeft || key == LogicalKeyboardKey.controlRight) {
           _abrirConferenciaItens();
           return KeyEventResult.handled;
        }

        // Teclas F8, F9, etc agora são tratadas pelo handler do HardwareKeyboard global para maior confiabilidade
        if (key == LogicalKeyboardKey.f8) {
          if (_carrinho.isNotEmpty) {
            _salvarVendaPendente(dataService, [], mostrarPromptImpressao: true);
          }
          return KeyEventResult.handled;
        }

        // Navegação por Setas
        if (key == LogicalKeyboardKey.arrowRight) {
          if (_focoNasCategorias) {
            final numCategorias = categorias.length + 1;
            if (_categoriaSelectedIndex < numCategorias - 1) {
              setState(() => _categoriaSelectedIndex++);
              return KeyEventResult.handled;
            } else if (_carrinho.isNotEmpty) {
              setState(() {
                _focoNasCategorias = false;
                _focoNoCarrinho = true;
                _cartSelectedIndex = 0;
                _categoriaSelectedIndex = -1;
                _gridSelectedIndex = -1;
              });
              return KeyEventResult.handled;
            }
          }
          // Navegação dentro do grid (quando já está navegando nele)
          if (!_focoNoCarrinho && !_focoNasCategorias && _gridSelectedIndex >= 0) {
            final screenWidth = MediaQuery.of(context).size.width;
            final isList = _viewMode == ViewMode.list;
            final crossAxisCount = isList ? 1 : _getGridCrossAxisCount(screenWidth);
            final maxItems = _termoBusca.isNotEmpty
                ? _buscarItens(dataService).length
                : _getProdutosPorCategoria(dataService).length;

            final isEndOfRow = isList ? true : ((_gridSelectedIndex + 1) % crossAxisCount == 0);

            if (_gridSelectedIndex < maxItems - 1 && !isEndOfRow) {
              setState(() => _gridSelectedIndex++);
              // Auto-scroll após navegação lateral
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _scrollToSelectedGridItem(_gridSelectedIndex, crossAxisCount, 0); // altura será decidida na função
              });
              return KeyEventResult.handled;
            } else if (!isList && _carrinho.isNotEmpty) {
              // Somente no modo GRADE (grid) a seta direita pula para o carrinho ao fim da linha
              setState(() {
                _focoNoCarrinho = true;
                _cartSelectedIndex = 0;
                _gridSelectedIndex = -1;
              });
              return KeyEventResult.handled;
            }
          }

          // Fora do grid/carrinho/categorias (“modo lançar novo item”): seta → incrementa QTD
          if (!_focoNoCarrinho && !_focoNasCategorias && _gridSelectedIndex < 0) {
            setState(() => _quantidadeDigitada++);
            return KeyEventResult.handled;
          }
        }

        if (key == LogicalKeyboardKey.arrowLeft) {
          if (_focoNasCategorias) {
            if (_categoriaSelectedIndex > 0) {
              setState(() => _categoriaSelectedIndex--);
              return KeyEventResult.handled;
            } else {
              // Se estiver na primeira categoria, foca na busca
              _buscaFocusNode.requestFocus();
              setState(() {
                _focoNasCategorias = false;
                _categoriaSelectedIndex = -1;
              });
              return KeyEventResult.handled;
            }
          }
          // Navegação lateral esquerda no grid (quando já está navegando nele)
          if (!_focoNoCarrinho && !_focoNasCategorias && _gridSelectedIndex > 0) {
            final screenWidth = MediaQuery.of(context).size.width;
            final crossAxisCount = _viewMode == ViewMode.list ? 1 : _getGridCrossAxisCount(screenWidth);
            
            // Na lista, seta esquerda volta para categorias
            if (_viewMode == ViewMode.list) {
              setState(() {
                _gridSelectedIndex = -1;
                _focoNasCategorias = true;
                _categoriaSelectedIndex = 0;
              });
              return KeyEventResult.handled;
            }

            setState(() => _gridSelectedIndex--);
            // Auto-scroll após navegação lateral
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _scrollToSelectedGridItem(_gridSelectedIndex, crossAxisCount, 0);
            });
            return KeyEventResult.handled;
          } else if (!_focoNoCarrinho && !_focoNasCategorias && _gridSelectedIndex == 0) {
            // Primeiro item do grid: volta para categorias
            setState(() {
              _gridSelectedIndex = -1;
              _focoNasCategorias = true;
              _categoriaSelectedIndex = 0;
            });
            return KeyEventResult.handled;
          }

          // Estando no carrinho: seta esquerda volta para busca
          if (_focoNoCarrinho) {
            _buscaFocusNode.requestFocus();
            setState(() {
              _focoNoCarrinho = false;
              _focoNasCategorias = false;
              _cartSelectedIndex = -1;
              _gridSelectedIndex = -1;
              _categoriaSelectedIndex = -1;
            });
            return KeyEventResult.handled;
          }

          // Fora do grid/carrinho/categorias (“modo lançar novo item”): seta ← decrementa QTD
          if (!_focoNoCarrinho && !_focoNasCategorias && _gridSelectedIndex < 0 && _quantidadeDigitada > 1) {
            setState(() => _quantidadeDigitada--);
            return KeyEventResult.handled;
          }
        }

        if (key == LogicalKeyboardKey.arrowDown) {
          setState(() {
            if (_focoNoCarrinho) {
              // No carrinho reversedIndex = length - 1 - index
              // Para IR PARA BAIXO visualmente, o index do carrinho deve DIMINUIR
              if (_cartSelectedIndex > 0) {
                _cartSelectedIndex--;
                _scrollToSelectedCartItem(_cartSelectedIndex);
              }
            } else if (_focoNasCategorias) {
              final maxItemsCat = _termoBusca.isNotEmpty
                  ? _buscarItens(dataService).length
                  : _getProdutosPorCategoria(dataService).length;
              // So sai das categorias para a grade se houver itens (grade vazia por padrao)
              if (maxItemsCat > 0) {
                _focoNasCategorias = false;
                _categoriaSelectedIndex = -1;
                _gridSelectedIndex = 0;
              }
            } else if (_buscaFocusNode.hasFocus) {
              _focoNasCategorias = true;
              _categoriaSelectedIndex = 0;
              _gridSelectedIndex = -1;
              _cartSelectedIndex = -1;
              _atalhosFocusNode.requestFocus();
            } else {
              final screenWidth = MediaQuery.of(context).size.width;
              final crossAxisCount = _viewMode == ViewMode.list ? 1 : _getGridCrossAxisCount(screenWidth);
              final maxItems = _termoBusca.isNotEmpty
                  ? _buscarItens(dataService).length
                  : _getProdutosPorCategoria(dataService).length;

              if (_gridSelectedIndex < 0 && maxItems > 0) {
                _gridSelectedIndex = 0;
              } else if (_gridSelectedIndex + crossAxisCount < maxItems) {
                _gridSelectedIndex += crossAxisCount;
                
                // Expansão Antecipada: Se chegarmos perto do fim dos itens visíveis, carregamos mais 500
                if (_termoBusca.isEmpty && _gridSelectedIndex >= _itensVisiveisPDV - 50) {
                   _itensVisiveisPDV += 500;
                   debugPrint('>>> ArrowDown Expansão: Agora com $_itensVisiveisPDV itens');
                }
              } else if (_gridSelectedIndex >= 0 && _gridSelectedIndex + crossAxisCount >= maxItems) {
                if (_gridSelectedIndex < maxItems - 1) {
                   _gridSelectedIndex = maxItems - 1;
                }
              }
            }
          });
          // Auto-scroll após navegação
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final screenWidth = MediaQuery.of(context).size.width;
            final crossAxisCount = _viewMode == ViewMode.list ? 1 : _getGridCrossAxisCount(screenWidth);
            _scrollToSelectedGridItem(_gridSelectedIndex, crossAxisCount, 0);
          });
          return KeyEventResult.handled;
        }

        if (key == LogicalKeyboardKey.arrowUp) {
          setState(() {
            if (_focoNoCarrinho) {
              // No carrinho reversedIndex = length - 1 - index
              // Para IR PARA CIMA visualmente, o index do carrinho deve AUMENTAR
              if (_cartSelectedIndex < _carrinho.length - 1) {
                _cartSelectedIndex++;
                _scrollToSelectedCartItem(_cartSelectedIndex);
              }
            } else if (_focoNasCategorias) {
              _focoNasCategorias = false;
              _buscaFocusNode.requestFocus();
            } else {
              final screenWidth = MediaQuery.of(context).size.width;
              final crossAxisCount = _viewMode == ViewMode.list ? 1 : _getGridCrossAxisCount(screenWidth);
              if (_gridSelectedIndex >= crossAxisCount) {
                _gridSelectedIndex -= crossAxisCount;
              } else {
                // Se estiver na primeira linha, sobe para categorias
                _gridSelectedIndex = -1;
                _focoNasCategorias = true;
                _categoriaSelectedIndex = 0;
                _atalhosFocusNode.requestFocus();
              }
            }
          });
          // Auto-scroll para cima também
          if (_focoNoCarrinho) {
            _scrollToSelectedCartItem(_cartSelectedIndex);
          } else if (!_focoNoCarrinho && (_focoNasCategorias || _gridSelectedIndex >= -1)) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              final screenWidth = MediaQuery.of(context).size.width;
              final crossAxisCount = _viewMode == ViewMode.list ? 1 : _getGridCrossAxisCount(screenWidth);
              _scrollToSelectedGridItem(_gridSelectedIndex, crossAxisCount, 0);
            });
          }
          return KeyEventResult.handled;
        }

        // Enter - Adicionar ao carrinho ou Ações
        if (key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.numpadEnter) {
          if (_focoNasCategorias) {
            final index = _categoriaSelectedIndex;
            if (index == 0) {
              // "Todos": toggle (mostra tudo; clicar/Enter de novo desmarca)
              setState(() {
                _categoriaAtiva = (_categoriaAtiva == 'Todos') ? null : 'Todos';
                _termoBusca = '';
                _buscaController.clear();
                _gridSelectedIndex = -1; // Evita RangeError com grade vazia
                _focoNoCarrinho = false;
              });
            } else if (index > 0 && index <= categorias.length) {
              final cat = categorias[index - 1];
              setState(() {
                _categoriaAtiva = cat; // Remove toggle (não deseleciona)
                _termoBusca = '';
                _buscaController.clear();
              });
            }
            return KeyEventResult.handled;
          }

          // Se a busca estiver focada, NÃO tratar o Enter aqui, deixar o TextField.onSubmitted tratar
          if (_buscaFocusNode.hasFocus) {
            debugPrint('[PDV ENTER] Busca focada, permitindo processamento do TextField');
            return KeyEventResult.ignored;
          }

          if (!_focoNoCarrinho && _gridSelectedIndex >= 0) {
            final itens = _termoBusca.isNotEmpty
                ? _buscarItens(dataService)
                : _getProdutosPorCategoria(dataService);
            debugPrint('[PDV ENTER] Grid selecionado, index: $_gridSelectedIndex, total itens: ${itens.length}');
            if (_gridSelectedIndex < itens.length) {
              debugPrint('[PDV ENTER] Adicionando item ${itens[_gridSelectedIndex].nome} ao carrinho');
              _adicionarAoCarrinho(itens[_gridSelectedIndex], manterFoco: true);
              return KeyEventResult.handled;
            }
          } else {
            debugPrint('[PDV ENTER] Ignorando - focoNoCarrinho: $_focoNoCarrinho, gridIndex: $_gridSelectedIndex');
          }
        }

        // Delete/Backspace - Remover do carrinho
        if (key == LogicalKeyboardKey.delete ||
            key == LogicalKeyboardKey.backspace) {
          // Shift + Del → limpar TODO o carrinho
          final shiftPressed = HardwareKeyboard.instance.isShiftPressed;
          if (key == LogicalKeyboardKey.delete && shiftPressed) {
            if (_carrinho.isNotEmpty) {
              _limparCarrinho();
            }
            return KeyEventResult.handled;
          }
          // Del normal → remover item selecionado no carrinho
          if (_focoNoCarrinho &&
              _cartSelectedIndex >= 0 &&
              _cartSelectedIndex < _carrinho.length) {
            _removerItem(_cartSelectedIndex);
            setState(() {
              if (_carrinho.isEmpty) {
                _focoNoCarrinho = false;
                _cartSelectedIndex = -1;
              } else if (_cartSelectedIndex >= _carrinho.length) {
                _cartSelectedIndex = _carrinho.length - 1;
              }
            });
            return KeyEventResult.handled;
          }
        }

        // Teclas + e - para alterar quantidade no carrinho
        if (_focoNoCarrinho &&
            _cartSelectedIndex >= 0 &&
            _cartSelectedIndex < _carrinho.length) {
          if (key == LogicalKeyboardKey.numpadAdd ||
              key == LogicalKeyboardKey.equal) {
            _alterarQuantidade(_cartSelectedIndex, 1);
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.minus ||
              key == LogicalKeyboardKey.numpadSubtract) {
            _alterarQuantidade(_cartSelectedIndex, -1);
            return KeyEventResult.handled;
          }
        }

        return KeyEventResult.ignored;
      },
      child: Column(
        children: [
          // Barra superior com busca, quantidade e cliente
          _buildBarraSuperior(dataService),
          // Alerta de limite de dinheiro na gaveta
          _buildAlertaLimiteDinheiro(dataService),
          // Área principal
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Lado esquerdo: Categorias + Produtos
                Expanded(
                  flex: 3,
                  child: Column(
                    children: [
                      // Categorias
                      _buildCategorias(categorias),
                      // Área de produtos
                      Expanded(
                        child: _termoBusca.isNotEmpty
                            ? (itensEncontrados.isEmpty
                                  ? _buildNenhumResultado()
                                  : _buildGridItens(itensEncontrados))
                            : _buildGridProdutos(produtosCategoria),
                      ),
                    ],
                  ),
                ),
                // Lado direito: Carrinho com efeito glow
                screenWidth < 1100
                    ? Expanded(
                        flex: 2,
                        child: Container(
                          margin: const EdgeInsets.only(right: 16, bottom: 16),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                const Color(0xFF0D0D15),
                                const Color(0xFF12121C),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.cyanAccent.withOpacity(0.15),
                                blurRadius: 40,
                                spreadRadius: 5,
                              ),
                              BoxShadow(
                                color: Colors.black.withOpacity(0.5),
                                blurRadius: 30,
                                offset: const Offset(0, 15),
                              ),
                            ],
                          ),
                          child: _buildCarrinhoMelhorado(dataService),
                        ),
                      )
                    : Container(
                        width: 400,
                        margin: const EdgeInsets.only(right: 16, bottom: 16),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: isDark ? [
                              const Color(0xFF0D0D15),
                              const Color(0xFF12121C),
                            ] : [
                              Colors.white,
                              const Color(0xFFF1F5F9),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            // Glow ciano externo
                            BoxShadow(
                              color: Colors.cyanAccent.withOpacity(0.15),
                              blurRadius: 40,
                              spreadRadius: 5,
                            ),
                            // Glow interno sutil
                            BoxShadow(
                              color: Colors.cyan.withOpacity(0.08),
                              blurRadius: 20,
                              spreadRadius: -5,
                            ),
                            // Sombra de profundidade
                            BoxShadow(
                              color: Colors.black.withOpacity(0.5),
                              blurRadius: 30,
                              offset: const Offset(0, 15),
                            ),
                          ],
                        ),
                        child: _buildCarrinhoMelhorado(dataService),
                      ),
              ],
            ),
          ),
          // Barra inferior de atalhos (Legenda)
          _buildBarraAtalhosLegenda(),
        ],
      ),
    ),
   );

    // Na versão mobile (muito estreita), mudar Row para Column
    if (screenWidth < 750) {
      return AppTheme.appBackground(
        child: Stack(
          children: [
            _buildPhoenixTraces(),
            Scaffold(
              backgroundColor: Colors.transparent,
              appBar: AppBar(
                title: _buildLogoEmpresa(context),
                backgroundColor: Colors.transparent,
                elevation: 0,
                centerTitle: true,
                actions: [
                  const SyncStatusWidget(),
                  // Botão Configurações PDV
                  IconButton(
                    onPressed: () => _abrirConfiguracoesPDV(),
                    icon: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white.withOpacity(0.2)),
                      ),
                      child: Icon(Icons.settings, color: Colors.white70, size: isSmallHeight ? 18 : 20),
                    ),
                    tooltip: 'Configurações do PDV',
                  ),
                  if (kIsWeb)
                    IconButton(
                      onPressed: () => _toggleTelaCheia(),
                      icon: Icon(
                        !html_helper.isFullscreen()
                            ? Icons.fullscreen
                            : Icons.fullscreen_exit,
                        color: Colors.white70,
                      ),
                      tooltip: 'Tela Cheia',
                    ),
                ],
              ),
              body: Column(
                children: [
                  _buildBarraSuperior(dataService),
                  _buildAlertaLimiteDinheiro(dataService),
                  Expanded(
                    child: DefaultTabController(
                      length: 2,
                      child: Column(
                        children: [
                          TabBar(
                            indicatorSize: TabBarIndicatorSize.tab,
                            indicator: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              color: Colors.blue.withOpacity(0.1),
                            ),
                            labelColor: Colors.blueAccent,
                            unselectedLabelColor: Colors.white54,
                            labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            indicatorColor: Colors.blueAccent,
                            tabs: [
                              const Tab(
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.grid_view_rounded, size: 20),
                                    SizedBox(width: 8),
                                    Text('PRODUTOS'),
                                  ],
                                ),
                              ),
                              Tab(
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.shopping_cart_rounded, size: 20),
                                    const SizedBox(width: 8),
                                    const Text('CARRINHO'),
                                    if (_carrinho.isNotEmpty) ...[
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.orangeAccent,
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: Text(
                                          '${_carrinho.length}',
                                          style: const TextStyle(
                                            color: Colors.black,
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                          Expanded(
                            child: TabBarView(
                              children: [
                                Column(
                                  children: [
                                    _buildCategorias(categorias),
                                    Expanded(
                                      child: _termoBusca.isNotEmpty
                                          ? (itensEncontrados.isEmpty
                                                ? _buildNenhumResultado()
                                                : _buildGridItens(itensEncontrados))
                                            : _buildGridProdutos(produtosCategoria),
                                    ),
                                  ],
                                ),
                                Container(
                                  margin: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: isDark ? const Color(0xFF0D0D15) : Colors.white,
                                    borderRadius: BorderRadius.circular(20),
                                    border: isDark ? null : Border.all(color: Colors.black12),
                                  ),
                                  child: _buildCarrinhoMelhorado(dataService),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              bottomNavigationBar: _carrinho.isNotEmpty ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                height: isSmallHeight ? 60 : 70,
                decoration: BoxDecoration(
                  color: const Color(0xFF161624),
                  border: const Border(top: BorderSide(color: Colors.white10)),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 10, offset: const Offset(0, -2))
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                     Column(
                       mainAxisSize: MainAxisSize.min,
                       crossAxisAlignment: CrossAxisAlignment.start,
                       children: [
                         Text('${_totalItens} ITENS', style: const TextStyle(color: Colors.grey, fontSize: 9, fontWeight: FontWeight.bold)),
                         Text(
                           NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(_totalCarrinho), 
                           style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 16)
                         ),
                       ],
                     ),
                     ElevatedButton.icon(
                       onPressed: () => _finalizarVenda(dataService),
                       icon: const Icon(Icons.payments_outlined, size: 16),
                       label: const Text('FINALIZAR', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                       style: ElevatedButton.styleFrom(
                         backgroundColor: Colors.green,
                         foregroundColor: Colors.white,
                         padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                         shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                       ),
                     )
                  ],
                ),
              ) : null,
            ),
          ],
        ),
      );
    }

    // Se não há Scaffold no contexto (chamado diretamente da home), envolver em um
    if (!hasScaffold) {
      return AppTheme.appBackground(
        child: Stack(
          children: [
            _buildPhoenixTraces(),
            Scaffold(
              backgroundColor: Colors.transparent,
              appBar: AppBar(
                title: _buildLogoEmpresa(context),
                backgroundColor: Colors.transparent,
                elevation: 0,
                centerTitle: true,
                toolbarHeight: isSmallHeight ? 48 : 56,
                actions: [
                  const SyncStatusWidget(),
                  // Botão Configurações PDV
                  IconButton(
                    onPressed: () => _abrirConfiguracoesPDV(),
                    icon: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white.withOpacity(0.2)),
                      ),
                      child: Icon(Icons.settings, color: Colors.white70, size: isSmallHeight ? 18 : 20),
                    ),
                    tooltip: 'Configurações do PDV',
                  ),
                  // Botão Tela Cheia
                  if (kIsWeb)
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () => _toggleTelaCheia(),
                      icon: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white.withOpacity(0.2)),
                        ),
                        child: Icon(
                          !html_helper.isFullscreen()
                              ? Icons.fullscreen
                              : Icons.fullscreen_exit,
                          color: Colors.white70,
                          size: isSmallHeight ? 18 : 20,
                        ),
                      ),
                      tooltip: 'Tela Cheia',
                    ),
                  // Botão Sangria (menor, apenas ícone)
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => _abrirDialogPagamento(),
                    icon: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.withOpacity(0.5)),
                      ),
                      child: Icon(
                        Icons.remove_circle_outline,
                        color: Colors.red.withOpacity(0.9),
                        size: isSmallHeight ? 18 : 20,
                      ),
                    ),
                    tooltip: 'Fazer Pagamento',
                  ),
                  // Botão Suprimento (menor, apenas ícone)
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => _abrirDialogSuprimento(),
                    icon: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.green.withOpacity(0.5)),
                      ),
                      child: Icon(
                        Icons.add_circle_outline,
                        color: Colors.green.withOpacity(0.9),
                        size: isSmallHeight ? 18 : 20,
                      ),
                    ),
                    tooltip: 'Suprimento',
                  ),
                  // Botão Observações
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => _abrirDialogObservacoes(),
                    icon: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color:
                            _observacoesVenda != null &&
                                _observacoesVenda!.isNotEmpty
                            ? Colors.blue.withOpacity(0.3)
                            : Colors.blue.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color:
                              _observacoesVenda != null &&
                                  _observacoesVenda!.isNotEmpty
                              ? Colors.blue.withOpacity(0.7)
                              : Colors.blue.withOpacity(0.5),
                          width:
                              _observacoesVenda != null &&
                                  _observacoesVenda!.isNotEmpty
                              ? 2
                              : 1,
                        ),
                      ),
                      child: Icon(
                        Icons.note_outlined,
                        color:
                            _observacoesVenda != null &&
                                _observacoesVenda!.isNotEmpty
                            ? Colors.blueAccent
                            : Colors.blue.withOpacity(0.9),
                        size: isSmallHeight ? 18 : 20,
                      ),
                    ),
                    tooltip: 'Observações da Venda',
                  ),
                  const SizedBox(width: 8),
                ],
              ),
              body: content,
            ),
          ],
        ),
      );
    }

    // Se já existe Scaffold (dentro do TabBarView), retornar apenas o conteúdo
    return Stack(
      children: [
        _buildPhoenixTraces(),
        content,
      ],
    );
  }

  Widget _buildPhoenixTraces() {
    return IgnorePointer(
      child: Stack(
        children: [
          // Traço da Asa Superior Esquerda - Posicionado para esconder o rosto
          Positioned(
            top: -150,
            left: -200,
            child: Opacity(
              opacity: 0.015,
              child: Transform.rotate(
                angle: 0.4,
                child: Image.asset(
                  'assets/images/phoenix.png',
                  width: 800,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
          // Traço da Calda Inferior Direita - Posicionado para focar na calda
          Positioned(
            bottom: -250,
            right: -150,
            child: Opacity(
              opacity: 0.012,
              child: Transform.rotate(
                angle: -0.8,
                child: Image.asset(
                  'assets/images/phoenix.png',
                  width: 900,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAlertaLimiteDinheiro(DataService dataService) {
    if (!_alertarLimiteGaveta || !dataService.caixaAberto) {
      return const SizedBox.shrink();
    }

    final totalDinheiro = dataService.calcularDinheiroEmCaixa();
    if (totalDinheiro < _limiteGavetaValor) {
      return const SizedBox.shrink();
    }

    final formatoMoeda = NumberFormat.currency(
      locale: 'pt_BR',
      symbol: 'R\$',
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      margin: const EdgeInsets.only(bottom: 12, left: 16, right: 16, top: 4),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFE94A4A), Color(0xFFC62828)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.redAccent.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'ATENÇÃO: LIMITE DE DINHEIRO NO CAIXA EXCEDIDO!',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'O saldo em dinheiro é de ${formatoMoeda.format(totalDinheiro)}, superando o limite seguro configurado de ${formatoMoeda.format(_limiteGavetaValor)}.',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton.icon(
            onPressed: () => _abrirDialogPagamento(),
            icon: const Icon(Icons.money_off, size: 16, color: Color(0xFFC62828)),
            label: const Text(
              'REALIZAR SANGRIA',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12,
                color: Color(0xFFC62828),
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              elevation: 2,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBarraSuperior(DataService dataService) {
    final isSmallHeight = MediaQuery.of(context).size.height < 750;
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 800;

    // Elementos da barra
    final searchField = Expanded(
      flex: 3,
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isDark ? Colors.blue.withOpacity(0.3) : Colors.black12),
        ),
        child: Focus(
          onKeyEvent: (node, event) {
            if (event is! KeyDownEvent) return KeyEventResult.ignored;
            final key = event.logicalKey;
            
            // F9 tratado globalmente
        
            
            // Seta para baixo: sair do campo e ir para categorias/grid
            if (key == LogicalKeyboardKey.arrowDown) {
              _atalhosFocusNode.requestFocus();
              setState(() {
                _focoNasCategorias = true;
                _categoriaSelectedIndex = 0;
                _gridSelectedIndex = -1;
              });
              return KeyEventResult.handled;
            }

            // Backspace no campo vazio: resetar quantidade para 1.0
            if (key == LogicalKeyboardKey.backspace && _buscaController.text.isEmpty && _quantidadeDigitada != 1.0) {
              setState(() {
                _quantidadeDigitada = 1.0;
              });
              return KeyEventResult.handled;
            }

            // Seta para direita: se o campo estiver vazio, incrementa a quantidade. Se contiver texto, navega para o fim e vai para o grid.
            if (key == LogicalKeyboardKey.arrowRight) {
              final text = _buscaController.text;
              if (text.isEmpty) {
                setState(() {
                  _quantidadeDigitada++;
                });
                return KeyEventResult.handled;
              }
              final selection = _buscaController.selection;
              if (selection.baseOffset >= text.length) {
                _atalhosFocusNode.requestFocus();
                final itens = _buscarItens(dataService);
                if (itens.isNotEmpty) {
                  setState(() {
                    _gridSelectedIndex = 0;
                  });
                }
                return KeyEventResult.handled;
              }
            }

            // Seta para esquerda: se o campo estiver vazio, decrementa a quantidade
            if (key == LogicalKeyboardKey.arrowLeft) {
              final text = _buscaController.text;
              if (text.isEmpty) {
                if (_quantidadeDigitada > 1.0) {
                  setState(() {
                    _quantidadeDigitada--;
                  });
                }
                return KeyEventResult.handled;
              }
            }
            return KeyEventResult.ignored;
          },
          child: TextField(
            controller: _buscaController,
            focusNode: _buscaFocusNode,
            style: TextStyle(color: textColor, fontSize: isSmallHeight ? 14 : 15),
            decoration: InputDecoration(
              hintText: _categoriaAtiva != null ? '🔍 $_categoriaAtiva...' : '🔍 Buscar...',
              hintStyle: TextStyle(color: textColor.withOpacity(0.4), fontSize: isSmallHeight ? 12 : 13),
              prefixIcon: GestureDetector(
                onTap: () => _abrirBuscaFacilitada(context),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(width: 12),
                    Icon(Icons.search,
                        color: Colors.blue, size: isSmallHeight ? 18 : 22),
                    if (_quantidadeDigitada != 1.0) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.orange,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '${_quantidadeDigitada.toStringAsFixed(_quantidadeDigitada.truncateToDouble() == _quantidadeDigitada ? 0 : 3)}x',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              suffixIcon: _termoBusca.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, color: Colors.white54),
                      onPressed: () {
                        _buscaController.clear();
                        setState(() => _termoBusca = '');
                      },
                    )
                  : null,
              filled: true,
              fillColor: Colors.transparent,
              border: InputBorder.none,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
            onChanged: (value) {
              if (_debounce?.isActive ?? false) _debounce!.cancel();
              _debounce = Timer(const Duration(milliseconds: 150), () {
                if (!mounted) return;
                setState(() {
                  _termoBusca = value;
                  
                  // Se terminar com '*' ou ' ', tenta extrair a quantidade
                  if ((value.endsWith('*') || value.endsWith(' ')) && value.length > 1) {
                    final valorSemPrefixo = value.substring(0, value.length - 1).replaceAll(',', '.');
                    final double? qtd = double.tryParse(valorSemPrefixo);
                    if (qtd != null && qtd > 0) {
                      _quantidadeDigitada = qtd;
                      _termoBusca = '';
                      
                      _buscaController.clear();
                      _buscaFocusNode.requestFocus();
                      
                      _mostrarNotificacaoSucesso(
                        icone: Icons.scale,
                        titulo: 'Quantidade: ${qtd.toStringAsFixed(3)}',
                        subtitulo: 'Próximo item será multiplicado',
                        cor: Colors.orange,
                      );
                      return;
                    }
                  }
                });
              });
            },
            onSubmitted: (value) {
              if (value.isEmpty) {
                if (_carrinho.isNotEmpty && !_estaFinalizando && !_dialogAberto) {
                  // Se o carrinho tem itens e o campo está vazio, Enter finaliza a venda
                  _finalizarVenda(Provider.of<DataService>(context, listen: false));
                } else {
                  _buscaFocusNode.requestFocus();
                }
                return;
              }

              // Pattern de Multiplicação: 5*COCA -> Qtd 5, busca COCA
              String termo = value;
              double qtd = 1.0;
              bool temMultiplicador = false;

              if (value.contains('*')) {
                final partes = value.split('*');
                if (partes.length >= 2) {
                  qtd = double.tryParse(partes[0].replaceAll(',', '.')) ?? 1.0;
                  termo = partes.sublist(1).join('*');
                  temMultiplicador = true;
                }
              }

              final termoLimpoNum = termo.replaceAll(',', '.').trim();
              final double? numPuro = double.tryParse(termoLimpoNum);

              // 1. VERIFICAÇÃO DE PREÇO COM VÍRGULA (ex: "10,00", "15,50", "5,00"):
              // Se o termo contém VÍRGULA e é um número (ex: "10,00"), DEVE ABRIR A JANELA DE DIVERSOS DIRETO!
              // Não pode buscar código de produto "1000" tirando a vírgula!
              final bool ehValorComVirgula = (termo.contains(',') || value.contains(',')) && numPuro != null && numPuro > 0;

              if (ehValorComVirgula) {
                final valorDigitado = numPuro;
                setState(() {
                  if (temMultiplicador) {
                    _quantidadeDigitada = qtd;
                  }
                  _termoBusca = '';
                });
                _buscaController.clear();
                _lancarDiversosRapido(precoInicial: valorDigitado);
                return;
              }

              // 2. BUSCA NORMAL DE PRODUTOS SE NÃO FOR UM VALOR COM VÍRGULA
              final itens = _buscarItens(dataService, termoOverride: termo);

              if (itens.isNotEmpty) {
                final primeiroItem = itens.first;
                setState(() => _quantidadeDigitada = temMultiplicador ? qtd : _quantidadeDigitada);
                _adicionarAoCarrinho(primeiroItem, manterFoco: true);
                _buscaController.clear();
                setState(() => _termoBusca = '');
                _buscaFocusNode.requestFocus();
                return;
              }

              // Se não encontrou nenhum item e o termo for APENAS um número de quantidade puro sem vírgula (ex: "5*"):
              final bool ehQtdValida = !temMultiplicador && numPuro != null && numPuro > 0 && numPuro <= 100 && !value.contains(',');

              if (ehQtdValida) {
                setState(() {
                  _quantidadeDigitada = numPuro;
                  _termoBusca = '';
                });
                _buscaController.clear();
                _buscaFocusNode.requestFocus();
                _mostrarNotificacaoSucesso(
                  icone: Icons.scale,
                  titulo: 'Quantidade Definida',
                  subtitulo: 'Próximo item será adicionado com: ${numPuro.toStringAsFixed(3)}',
                  cor: Colors.blueAccent,
                );
                return;
              }
              
              // Se não encontrou nenhum item e não é uma quantidade válida (ex: código inexistente 22222)
              _buscaFocusNode.requestFocus();
              _mostrarNotificacaoSucesso(
                icone: Icons.error_outline_rounded,
                titulo: 'Código Inexistente',
                subtitulo: 'Produto "$value" não cadastrado.',
                cor: Colors.redAccent,
              );
            },
          ),
        ),
      ),
    );

    // Obter configurações de visibilidade dos botões da empresa
    final empresa = dataService.empresaAtual;
    final config = empresa?.configuracoes;
    final mostrarCliente = config?['mostrarBotaoCliente'] ?? true;
    final mostrarVendedor = config?['mostrarBotaoVendedor'] ?? true;
    final mostrarEntregas = config?['mostrarBotaoEntregas'] ?? true;
    final mostrarHistorico = config?['mostrarBotaoHistorico'] ?? true;
    final mostrarCentral = config?['mostrarBotaoCentral'] ?? true;
    final mostrarDespesa = config?['mostrarBotaoDespesa'] ?? true;

    final actionButtons = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (mostrarCliente) ...[
            _buildCompactHeaderButton(icon: Icons.person, label: _clienteSelecionado?.nome ?? 'Cliente', color: _clienteSelecionado != null ? Colors.greenAccent : Colors.white54, onTap: () => _selecionarCliente(dataService)),
            const SizedBox(width: 8),
          ],
          if (_obterTabelasPrecoEmpresa().isNotEmpty) ...[
            _buildCompactHeaderButton(
              icon: Icons.price_change,
              label: _tabelaPrecoAtiva ?? 'Tabela',
              color: _tabelaPrecoAtiva != null ? Colors.orangeAccent : Colors.white54,
              onTap: () => _selecionarTabelaPreco(dataService),
            ),
            const SizedBox(width: 8),
          ],
          if (mostrarVendedor) ...[
            _buildCompactHeaderButton(
              icon: Icons.badge, 
              label: _vendedorSelecionado?.nome ?? 'Vendedor', 
              color: _vendedorSelecionado != null ? Colors.purpleAccent : Colors.white54, 
              onTap: () => _selecionarVendedor(dataService)
            ),
            const SizedBox(width: 8),
          ],
          if (mostrarEntregas) ...[
            _buildCompactHeaderButton(
              icon: Icons.delivery_dining, 
              label: _isDelivery ? 'Entrega Ativa' : 'Entregas', 
              color: _isDelivery ? Colors.orangeAccent : Colors.white54, 
              onTap: () => _abrirDialogDelivery()
            ),
            const SizedBox(width: 8),
          ],
          if (mostrarHistorico) ...[
            _buildCompactHeaderButton(icon: Icons.history, label: 'Histórico', color: Colors.amber, onTap: () => _abrirHistoricoVendas()),
            const SizedBox(width: 8),
          ],
          if (mostrarCentral) ...[
            _buildCompactHeaderButton(icon: Icons.assignment, label: 'Central', color: Colors.blueAccent, onTap: () => _abrirPedidos()),
            const SizedBox(width: 8),
          ],
          if (mostrarDespesa)
            _buildCompactHeaderButton(icon: Icons.money_off, label: 'Despesa', color: Colors.redAccent, onTap: () => _abrirLancamentoDespesa()),
        ],
      ),
    );

    final habilitarMesasComandas = dataService.empresaAtual?.configuracoes?['habilitarMesasComandas'] != false;
    final habilitarCozinha = dataService.empresaAtual?.configuracoes?['habilitarCozinha'] != false;

    return Container(
      padding: EdgeInsets.fromLTRB(16, isSmallHeight ? 4 : 8, 16, isSmallHeight ? 4 : 8),
      child: isMobile 
        ? Column(
            children: [
              Row(
                children: [
                  if (habilitarMesasComandas) ...[
                    _buildBotaoMapaMesas(dataService, compact: true),
                    const SizedBox(width: 4),
                    _buildBotaoComandas(dataService, compact: true),
                    const SizedBox(width: 4),
                  ],
                  if (habilitarCozinha) ...[
                    _buildBotaoCozinha(dataService, compact: true),
                    const SizedBox(width: 8),
                  ],
                  searchField,
                ],
              ),
              const SizedBox(height: 8),
              actionButtons,
            ],
          )
        : Row(
            children: [
              if (habilitarMesasComandas) ...[
                _buildBotaoMapaMesas(dataService, compact: true),
                const SizedBox(width: 4),
                _buildBotaoComandas(dataService, compact: true),
                const SizedBox(width: 4),
              ],
              if (habilitarCozinha) ...[
                _buildBotaoCozinha(dataService, compact: true),
                const SizedBox(width: 8),
              ],
              if (_mesaComandaVinculada != null) ...[
                _buildBadgeVinculoHeader(),
                const SizedBox(width: 8),
              ],
              searchField,
              const SizedBox(width: 8),
              _buildBotaoOrdenacao(dataService), // Novo botão de ordenação
              const SizedBox(width: 8),
              actionButtons,
            ],
          ),
    );
  }

  Widget _buildCompactHeaderButton({required IconData icon, required String label, required Color color, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(color: const Color(0xFF1E1E2E), borderRadius: BorderRadius.circular(12)),
        child: Row(children: [Icon(icon, color: color, size: 18), const SizedBox(width: 6), Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12), overflow: TextOverflow.ellipsis)]),
      ),
    );
  }

  Widget _buildBadgeVinculoHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: _mesaComandaVinculada!.tipo == TipoControle.comanda ? Colors.purple.withOpacity(0.2) : Colors.orange.withOpacity(0.2), borderRadius: BorderRadius.circular(12), border: Border.all(color: _mesaComandaVinculada!.tipo == TipoControle.comanda ? Colors.purple : Colors.orange)),
      child: Row(children: [Icon(_mesaComandaVinculada!.tipo == TipoControle.comanda ? Icons.receipt_long : Icons.table_restaurant, size: 14, color: _mesaComandaVinculada!.tipo == TipoControle.comanda ? Colors.purpleAccent : Colors.orangeAccent), const SizedBox(width: 6), Text(_mesaComandaVinculada!.numero, style: TextStyle(color: _mesaComandaVinculada!.tipo == TipoControle.comanda ? Colors.purpleAccent : Colors.orangeAccent, fontWeight: FontWeight.bold, fontSize: 12))]),
    );
  }

  Widget _buildBotaoOrdenacao(DataService dataService) {
    return PopupMenuButton<SortOption>(
      initialValue: _sortOption,
      tooltip: 'Ordenar produtos',
      icon: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E2E),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
        ),
        child: const Icon(Icons.sort_rounded, color: Colors.blueAccent, size: 20),
      ),
      onSelected: (option) {
        setState(() {
          _sortOption = option;
          _cachedProdutosCategoria = []; // Limpa cache para reordenar
        });
      },
      color: const Color(0xFF1E1E2E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: SortOption.nome,
          child: Row(
            children: [
              Icon(Icons.sort_by_alpha_rounded, color: Colors.white70, size: 18),
              SizedBox(width: 12),
              Text('Ordem Alfabética (A-Z)', style: TextStyle(color: Colors.white)),
            ],
          ),
        ),
        const PopupMenuItem(
          value: SortOption.recentes,
          child: Row(
            children: [
              Icon(Icons.history_rounded, color: Colors.white70, size: 18),
              SizedBox(width: 12),
              Text('Últimos Cadastrados', style: TextStyle(color: Colors.white)),
            ],
          ),
        ),
        const PopupMenuItem(
          value: SortOption.codigo,
          child: Row(
            children: [
              Icon(Icons.tag_rounded, color: Colors.white70, size: 18),
              SizedBox(width: 12),
              Text('Pelo Código', style: TextStyle(color: Colors.white)),
            ],
          ),
        ),
        const PopupMenuItem(
          value: SortOption.grupo,
          child: Row(
            children: [
              Icon(Icons.category_rounded, color: Colors.white70, size: 18),
              SizedBox(width: 12),
              Text('Por Categoria/Grupo', style: TextStyle(color: Colors.white)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCategorias(List<String> categorias) {
    final isSmallHeight = MediaQuery.of(context).size.height < 750;

    return Container(
      height: isSmallHeight ? 40 : 50,
      margin: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: isSmallHeight ? 4 : 8,
      ),
      child: Row(
        children: [
          // Ícone indicando scroll
          Container(
            padding: const EdgeInsets.only(right: 8),
            child: Icon(
              Icons.chevron_left_rounded,
              color: Colors.white.withOpacity(0.3),
              size: 20,
            ),
          ),
          // Lista de categorias com scroll
          Expanded(
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(context).copyWith(
                dragDevices: {
                  PointerDeviceKind.touch,
                  PointerDeviceKind.mouse,
                  PointerDeviceKind.trackpad,
                },
              ),
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                itemCount: categorias.length + 1,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    // Botão "Todos": destaca apenas quando selecionado explicitamente.
                    // Estado limpo (null) = nenhuma categoria selecionada (grade vazia até escolher).
                    final isActive = _categoriaAtiva == 'Todos';
                    final isSelected =
                        _focoNasCategorias && _categoriaSelectedIndex == 0;
                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          // Toggle: clicar de novo em "Todos" desmarca (volta ao estado inicial vazio)
                          _categoriaAtiva = (_categoriaAtiva == 'Todos') ? null : 'Todos';
                          _termoBusca = '';
                          _buscaController.clear();
                          _focoNasCategorias = true;
                          _categoriaSelectedIndex = 0;
                          _gridSelectedIndex = -1; // Evita RangeError com grade vazia
                          _focoNoCarrinho = false;
                        });
                        _buscaFocusNode.requestFocus();
                      },
                      child: Container(
                        margin: const EdgeInsets.only(right: 8),
                        padding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: isSmallHeight ? 6 : 10,
                        ),
                        decoration: BoxDecoration(
                          gradient: isActive
                              ? LinearGradient(
                                  colors: [
                                    Colors.blue.shade600,
                                    Colors.blue.shade400,
                                  ],
                                )
                              : null,
                          color: isActive ? null : const Color(0xFF1E1E2E),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected
                                ? Colors.cyanAccent
                                : (isActive
                                      ? Colors.blue
                                      : (isDark ? Colors.white.withOpacity(0.1) : Colors.black12)),
                            width: isSelected ? 3 : 1,
                          ),
                          boxShadow: isSelected
                              ? [
                                  BoxShadow(
                                    color: Colors.cyanAccent.withOpacity(0.3),
                                    blurRadius: 10,
                                  ),
                                ]
                              : (isActive
                                    ? [
                                        BoxShadow(
                                          color: Colors.blue.withOpacity(0.3),
                                          blurRadius: 8,
                                          offset: const Offset(0, 2),
                                        ),
                                      ]
                                    : null),
                        ),
                        alignment: Alignment.center,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.apps_rounded,
                              color: isActive ? Colors.white : Colors.white60,
                              size: 16,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Todos',
                              style: TextStyle(
                                color: isActive ? Colors.white : Colors.white70,
                                fontWeight: isActive
                                    ? FontWeight.bold
                                    : FontWeight.w500,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  final categoria = categorias[index - 1];
                  final isActive = _categoriaAtiva == categoria;
                  final isSelected =
                      _focoNasCategorias && _categoriaSelectedIndex == index;
                  return GestureDetector(
                    onTap: () {
                      if (_categoriaAtiva == categoria) {
                        // Se já está selecionada, apenas foca mas não limpa busca nem reseta grid
                        setState(() {
                          _focoNasCategorias = true;
                          _categoriaSelectedIndex = index;
                        });
                      } else {
                        setState(() {
                          _categoriaAtiva = categoria; // Remove toggle
                          _termoBusca = '';
                          _buscaController.clear();
                          _focoNasCategorias = true;
                          _categoriaSelectedIndex = index;
                          _gridSelectedIndex = -1;
                          _focoNoCarrinho = false;
                        });
                      }
                      _buscaFocusNode.requestFocus();
                    },
                    child: Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: isSmallHeight ? 6 : 10,
                      ),
                      decoration: BoxDecoration(
                        gradient: isActive
                            ? LinearGradient(
                                colors: [
                                  Colors.purple.shade600,
                                  Colors.purple.shade400,
                                ],
                              )
                            : null,
                        color: isActive ? null : const Color(0xFF1E1E2E),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected
                              ? Colors.cyanAccent
                              : (isActive
                                    ? Colors.purple
                                    : Colors.white.withOpacity(0.1)),
                          width: isSelected ? 3 : 1,
                        ),
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                  color: Colors.cyanAccent.withOpacity(0.3),
                                  blurRadius: 10,
                                ),
                              ]
                            : (isActive
                                  ? [
                                      BoxShadow(
                                        color: Colors.purple.withOpacity(0.3),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2),
                                      ),
                                    ]
                                  : null),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        categoria,
                        style: TextStyle(
                          color: isActive ? Colors.white : Colors.white70,
                          fontWeight: isActive
                              ? FontWeight.bold
                              : FontWeight.w500,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          // Ícone indicando mais itens à direita
          Container(
            padding: const EdgeInsets.only(left: 8),
            child: Icon(
              Icons.chevron_right_rounded,
              color: Colors.white.withOpacity(0.3),
              size: 20,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEstadoInicial(DataService dataService) {
    return Column(
      children: [
        // Conteúdo central
        Expanded(
          child: Center(
            child: TweenAnimationBuilder<double>(
              duration: const Duration(seconds: 1),
              tween: Tween(begin: 0.0, end: 1.0),
              builder: (context, value, child) {
                return Opacity(
                  opacity: value,
                  child: Transform.translate(
                    offset: Offset(0, 20 * (1 - value)),
                    child: child,
                  ),
                );
              },
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Logo êxodo systems com glow sutil
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.blue.withOpacity(0.05),
                          blurRadius: 50,
                          spreadRadius: 10,
                        ),
                      ],
                    ),
                    child: const ExodoLogo(fontSize: 48, showSubtitle: true),
                  ),
                  const SizedBox(height: 32),
                  // Dicas de uso visual
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildDicaInicial(Icons.search, 'Busque Produtos'),
                      const SizedBox(width: 24),
                      _buildDicaInicial(
                        Icons.touch_app,
                        'Use o Touch ou Mouse',
                      ),
                      const SizedBox(width: 24),
                      _buildDicaInicial(Icons.keyboard, 'Atalhos Rápidos'),
                    ],
                  ),
                  const SizedBox(height: 48),
                  Text(
                    'SISTEMA PRONTO PARA VENDER',
                    style: TextStyle(
                      color: Colors.blueAccent.withOpacity(0.5),
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 4,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.03),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(color: Colors.white.withOpacity(0.05)),
                    ),
                    child: Text(
                      'Clique no campo de busca ou pressione F2',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.4),
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDicaInicial(IconData icon, String text) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            icon,
            color: Colors.blueAccent.withOpacity(0.6),
            size: 24,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          text,
          style: TextStyle(
            color: Colors.white.withOpacity(0.3),
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  // ============ Métodos Auxiliares de Navegação ============

  Widget _buildBotaoMapaMesas(DataService dataService, {bool compact = false}) {
    return IconButton(
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
      onPressed: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const CozinhaMesasFuncionarioPage()),
        );
      },
      icon: Container(
        padding: EdgeInsets.all(compact ? 6 : 8),
        decoration: BoxDecoration(
          color: Colors.orange.withOpacity(0.15),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.orange.withOpacity(0.4)),
        ),
        child: Icon(Icons.table_bar, color: Colors.orange, size: compact ? 18 : 22),
      ),
      tooltip: 'Mapa de Mesas',
    );
  }

  Widget _buildBotaoComandas(DataService dataService, {bool compact = false}) {
    return IconButton(
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
      onPressed: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const CozinhaMesasFuncionarioPage(abaInicial: 1)),
        );
      },
      icon: Container(
        padding: EdgeInsets.all(compact ? 6 : 8),
        decoration: BoxDecoration(
          color: Colors.purpleAccent.withOpacity(0.15),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.purpleAccent.withOpacity(0.4)),
        ),
        child: Icon(Icons.receipt_long, color: Colors.purpleAccent, size: compact ? 18 : 22),
      ),
      tooltip: 'Comandas',
    );
  }

  Widget _buildBotaoCozinha(DataService dataService, {bool compact = false}) {
    return IconButton(
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
      onPressed: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const CozinhaBarPage()),
        );
      },
      icon: Container(
        padding: EdgeInsets.all(compact ? 6 : 8),
        decoration: BoxDecoration(
          color: Colors.greenAccent.withOpacity(0.15),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.greenAccent.withOpacity(0.4)),
        ),
        child: Icon(Icons.kitchen, color: Colors.greenAccent, size: compact ? 18 : 22),
      ),
      tooltip: 'Cozinha / Preparos',
    );
  }

  Widget _buildBarraAtalhosLegenda() {
    final screenWidth = MediaQuery.of(context).size.width;
    if (screenWidth < 900) return const SizedBox.shrink();

    return MouseRegion(
      onEnter: (_) => setState(() => _mostrarBarraLegenda = true),
      onExit: (_) => setState(() => _mostrarBarraLegenda = false),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        child: Container(
          width: double.infinity,
          height: _mostrarBarraLegenda ? null : 6, // 6 pixels de 'sensor' no rodapé
          decoration: BoxDecoration(
            color: const Color(0xFF0D0D15),
            border: Border(top: BorderSide(color: Colors.white.withOpacity(_mostrarBarraLegenda ? 0.1 : 0.05))),
          ),
          child: _mostrarBarraLegenda 
            ? AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: 1.0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 0,
                    runSpacing: 8,
                    children: [
                      _buildItemLegenda('SETAS', 'NAVEGAR'),
                      _buildItemLegenda('F2', 'BUSCA'),
                      _buildItemLegenda('F6', 'CLIENTE'),
                      _buildItemLegenda('F7', 'DESPESA'),

                      _buildItemLegenda('F4', 'CATEGORIAS'),
                      _buildItemLegenda('SHIFT', 'CARRINHO'),
                      _buildItemLegenda('CTRL', 'CONFERIR'),
                      _buildItemLegenda('ENTER', 'ADICIONAR'),
                      _buildItemLegenda('+', 'QUANTIDADE'),
                      _buildItemLegenda('DEL', 'REMOVER'),
                      _buildItemLegenda('⇧+DEL', 'LIMPAR TUDO'),
                      _buildItemLegenda('F8', 'SALVAR'),
                      _buildItemLegenda('F9', 'FINALIZAR', isPrimary: true),
                    ],
                  ),
                ),
              )
            : const SizedBox.shrink(),
        ),
      ),
    );
  }

  Widget _buildItemLegenda(String key, String label, {bool isPrimary = false}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: isPrimary
                  ? Colors.greenAccent
                  : Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              key,
              style: TextStyle(
                color: isPrimary ? Colors.black : Colors.white70,
                fontSize: 10,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: isPrimary ? Colors.greenAccent : Colors.white38,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNenhumResultado() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.search_off,
            size: 60,
            color: Colors.white.withOpacity(0.3),
          ),
          const SizedBox(height: 16),
          Text(
            'Nenhum item encontrado',
            style: TextStyle(
              color: Colors.white.withOpacity(0.5),
              fontSize: 16,
            ),
          ),
          Text(
            'para "$_termoBusca"',
            style: TextStyle(
              color: Colors.white.withOpacity(0.3),
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 32),
          // Botão rápido para lançar como Diversos
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 32),
            child: ElevatedButton.icon(
              onPressed: () {
                // Verificar se o termo de busca é um número (preço)
                final valorDigitado = double.tryParse(
                  _termoBusca.replaceAll(',', '.').trim(),
                );
                _lancarDiversosRapido(precoInicial: valorDigitado);
              },
              icon: const Icon(Icons.add_circle_outline, size: 24),
              label: const Text(
                'Lançar como Diversos (9999)',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orangeAccent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 16,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 4,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Adicione itens não cadastrados rapidamente',
            style: TextStyle(
              color: Colors.white.withOpacity(0.4),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _lancarDiversosRapido({double? precoInicial}) async {
    final dataService = Provider.of<DataService>(context, listen: false);

    // Garantir que o produto Diversos existe
    final produtoDiversos = await dataService.garantirProdutoDiversos();

    // Se o termo de busca for um número, usar como preço e limpar descrição
    // Caso contrário, usar o termo como descrição
    final termoEhNumero =
        double.tryParse(_termoBusca.replaceAll(',', '.').trim()) != null;
    final descricaoInicial = termoEhNumero ? '' : _termoBusca;
    final precoInicialValor =
        precoInicial ??
        (termoEhNumero
            ? double.tryParse(_termoBusca.replaceAll(',', '.').trim())
            : null);

    final descricaoController = TextEditingController(text: descricaoInicial);
    final precoController = TextEditingController(
      text: precoInicialValor != null
          ? precoInicialValor.toStringAsFixed(2)
          : '',
    );

    // Focar na descrição se o preço já foi preenchido, senão focar no preço
    final focusDescricao = precoInicialValor != null;
    final focusNodeDescricao = FocusNode();
    final focusNodePreco = FocusNode();

    await showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.add_circle_outline,
                color: Colors.orangeAccent,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Lançar Diversos',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Descrição:',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: descricaoController,
                focusNode: focusNodeDescricao,
                style: const TextStyle(color: Colors.white, fontSize: 16),
                decoration: InputDecoration(
                  hintText: 'Ex: Parafuso especial...',
                  hintStyle: TextStyle(color: Colors.white.withOpacity(0.4)),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: Colors.white.withOpacity(0.3),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                      color: Colors.orangeAccent,
                      width: 2,
                    ),
                  ),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.05),
                ),
                autofocus: focusDescricao,
                maxLines: 2,
                textInputAction: TextInputAction.next,
                onSubmitted: (value) {
                  final descInput = value.trim();
                  final descricao = descInput.isNotEmpty ? descInput : 'Diversos';

                  // Se o preço já estiver preenchido, adicionar diretamente
                  if (precoController.text.isNotEmpty) {
                    final preco =
                        double.tryParse(
                          precoController.text.replaceAll(',', '.'),
                        ) ??
                        0.0;
                    if (preco > 0) {
                      Navigator.pop(dialogContext);
                      _adicionarDiversosAoCarrinho(
                        produtoDiversos,
                        descricao,
                        preco,
                      );
                      return;
                    }
                  }

                  // Se não tem preço, focar no campo de preço
                  focusNodePreco.requestFocus();
                },
              ),
              const SizedBox(height: 20),
              const Text(
                'Preço:',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: precoController,
                focusNode: focusNodePreco,
                style: const TextStyle(color: Colors.white, fontSize: 18),
                decoration: InputDecoration(
                  prefixText: 'R\$ ',
                  prefixStyle: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: Colors.white.withOpacity(0.3),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                      color: Colors.orangeAccent,
                      width: 2,
                    ),
                  ),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.05),
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                textInputAction: TextInputAction.done,
                autofocus: !focusDescricao,
                onSubmitted: (value) {
                  final descInput = descricaoController.text.trim();
                  final descricao = descInput.isNotEmpty ? descInput : 'Diversos';
                  final preco =
                      double.tryParse(value.replaceAll(',', '.')) ?? 0.0;

                  if (preco <= 0) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      const SnackBar(
                        content: Text('Informe um preço válido'),
                        backgroundColor: Colors.red,
                      ),
                    );
                    return;
                  }

                  Navigator.pop(dialogContext);
                  _adicionarDiversosAoCarrinho(
                    produtoDiversos,
                    descricao,
                    preco,
                  );
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text(
              'Cancelar',
              style: TextStyle(color: Colors.white54),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              final descInput = descricaoController.text.trim();
              final descricao = descInput.isNotEmpty ? descInput : 'Diversos';
              final preco =
                  double.tryParse(precoController.text.replaceAll(',', '.')) ??
                  0.0;

              if (preco <= 0) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(
                    content: Text('Informe um preço válido'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }

              Navigator.pop(dialogContext);
              _adicionarDiversosAoCarrinho(produtoDiversos, descricao, preco);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orangeAccent,
            ),
            child: const Text('Adicionar'),
          ),
        ],
      ),
    );
  }

  void _adicionarDiversosAoCarrinho(
    Produto produtoDiversos,
    String descricao,
    double preco,
  ) async {
    final dataService = Provider.of<DataService>(context, listen: false);
    final descLimpa = descricao.trim();
    final nomeFormatado = descLimpa.isNotEmpty 
        ? (descLimpa.toLowerCase().startsWith('diversos') ? descLimpa : 'Diversos $descLimpa') 
        : 'Diversos R\$ ${preco.toStringAsFixed(2)}';

    // Cadastrar produto automaticamente no catálogo de produtos do sistema
    try {
      final jaExiste = dataService.produtos.any(
        (p) => p.nome.toLowerCase() == nomeFormatado.toLowerCase() && (p.precoAtual - preco).abs() < 0.01,
      );
      if (!jaExiste) {
        final timestampStr = DateTime.now().millisecondsSinceEpoch.toString();
        final codigoNovo = 'DIV-${timestampStr.substring(timestampStr.length - 4)}';
        final novoProduto = Produto(
          id: const Uuid().v4(),
          codigo: codigoNovo,
          nome: nomeFormatado,
          descricao: 'Produto cadastrado automaticamente via lançamento Diversos',
          preco: preco,
          unidade: 'UN',
          grupo: 'Diversos',
          estoque: 9999,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        await dataService.addProduto(novoProduto);
        debugPrint('>>> [Diversos] ✅ Produto "$nomeFormatado" (R\$ ${preco.toStringAsFixed(2)}) cadastrado automaticamente no catálogo!');
      }
    } catch (e) {
      debugPrint('>>> [Diversos] Erro ao cadastrar produto automático: $e');
    }

    // Adicionar ao carrinho
    final id = '${produtoDiversos.id}-${DateTime.now().millisecondsSinceEpoch}';
    final nome = nomeFormatado;

    final index = _carrinho.indexWhere((c) => c.nome == nome);
    if (index >= 0) {
      setState(() {
        // Mover para o fim da lista (topo no visual invertido)
        final itemExistente = _carrinho.removeAt(index);
        itemExistente.quantidade += _quantidadeDigitada;
        _carrinho.add(itemExistente);
      });
    } else {
      setState(() {
        _carrinho.add(
          ItemCarrinho(
            id: id,
            nome: nome,
            descricao: descLimpa.isNotEmpty ? descLimpa : 'Diversos R\$ ${preco.toStringAsFixed(2)}',
            preco: preco,
            quantidade: _quantidadeDigitada,
            isServico: false,
          ),
        );
      });
    }

    // Notificação
    final qtdAtual = index >= 0
        ? _carrinho[index].quantidade
        : _quantidadeDigitada;
    _mostrarNotificacaoItemAdicionado(
      nome: nome,
      quantidade: _quantidadeDigitada,
      quantidadeTotal: qtdAtual,
      preco: preco,
      jaExistia: index >= 0,
      isServico: false,
      totalCarrinho: _totalCarrinho,
    );

    // Limpar
    setState(() {
      _quantidadeDigitada = 1;
      _termoBusca = '';
    });
    _buscaController.clear();
    _buscaFocusNode.requestFocus();
    _salvarCarrinho();

    // Scroll para o topo
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_carrinhoScrollController.hasClients) {
        _carrinhoScrollController.animateTo(
          0.0,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutQuart,
        );
      }
    });
  }

  Widget _buildGridItens(List<dynamic> itens) {
    if (_viewMode == ViewMode.list) {
      return Scrollbar(
        controller: _gridScrollController,
        thumbVisibility: true,
        child: ListView.builder(
          controller: _gridScrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(left: 8, right: 8, top: 4, bottom: 100),
          itemCount: itens.length,
          itemBuilder: (context, index) {
            final item = itens[index];
            final isProduto = item is Produto;
            return _buildLinhaProduto(item, isProduto, index: index);
          },
        ),
      );
    }
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final crossAxisCount = _getGridCrossAxisCount(screenWidth);
    final aspectRatio = _getGridItemAspectRatio(screenHeight);

    return Scrollbar(
      controller: _gridScrollController,
      thumbVisibility: true,
      child: GridView.builder(
        controller: _gridScrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(left: 4, right: 4, top: 4, bottom: 100),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        childAspectRatio: aspectRatio,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
      ),
      itemCount: itens.length,
        itemBuilder: (context, index) {
          final item = itens[index];
          final isProduto = item is Produto;
          return _buildCardProduto(item, isProduto, index: index);
        },
      ),
    );
  }

  Widget _buildGridProdutos(List<Produto> produtos) {
    if (produtos.isEmpty && _termoBusca.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_rounded, size: 64, color: Colors.white.withOpacity(0.1)),
            const SizedBox(height: 16),
            Text(
              'Pronto para vender!',
              style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Busque um produto ou selecione uma categoria acima.',
              style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 14),
            ),
          ],
        ),
      );
    }
    
    Widget corpo;
    if (_viewMode == ViewMode.list) {
      corpo = Scrollbar(
        controller: _gridScrollController,
        thumbVisibility: true,
        child: ListView.builder(
          controller: _gridScrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(left: 8, right: 8, top: 20, bottom: 100),
          itemExtent: 82.0, // Altura fixa garantida para precisão de scroll
          itemCount: _termoBusca.isNotEmpty 
              ? produtos.length 
              : (_itensVisiveisPDV > produtos.length ? produtos.length : _itensVisiveisPDV),
          itemBuilder: (context, index) {
            return _buildLinhaProduto(produtos[index], true, index: index);
          },
        ),
      );
    } else {
      final screenWidth = MediaQuery.of(context).size.width;
      final screenHeight = MediaQuery.of(context).size.height;
      final crossAxisCount = _getGridCrossAxisCount(screenWidth);

      final aspectRatio = _getGridItemAspectRatio(screenHeight);

      corpo = Scrollbar(
        controller: _gridScrollController,
        thumbVisibility: true,
        child: GridView.builder(
          controller: _gridScrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(left: 4, right: 4, top: 4, bottom: 100),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            childAspectRatio: aspectRatio,
            crossAxisSpacing: 4,
            mainAxisSpacing: 4,
          ),
          itemCount: _termoBusca.isNotEmpty 
              ? produtos.length 
              : (_itensVisiveisPDV > produtos.length ? produtos.length : _itensVisiveisPDV),
          itemBuilder: (context, index) {
            return _buildCardProduto(produtos[index], true, index: index);
          },
        ),
      );
    }

    return corpo;
  }

  Widget _buildLinhaProduto(dynamic item, bool isProduto, {int index = -1}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isSelected = index >= 0 && index == _gridSelectedIndex;
    final nome = item.nome as String;
    final preco = isProduto
        ? (item as Produto).precoAtual
        : (item as Servico).preco;
    final codigo = isProduto ? (item as Produto).codigo : null;
    final estoque = isProduto ? (item as Produto).estoque : null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        onTap: () => _adicionarAoCarrinho(item, manterFoco: true),
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected 
                ? Colors.blueAccent.withOpacity(0.15) 
                : (isDark ? Colors.white.withOpacity(0.04) : Colors.white),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? Colors.blueAccent : (isDark ? Colors.white.withOpacity(0.05) : Colors.black12),
              width: isSelected ? 3 : 1,
            ),
            boxShadow: isSelected ? [
              BoxShadow(
                color: Colors.blueAccent.withOpacity(0.5),
                blurRadius: 15,
                spreadRadius: 4,
                offset: const Offset(0, 0),
              )
            ] : [
              if (!isDark)
                BoxShadow(
                  color: Colors.black.withOpacity(0.03),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
            ],
          ),
          child: Row(
            children: [
              // Avatar ou Ícone
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isProduto ? Colors.blueAccent.withOpacity(0.1) : Colors.purpleAccent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  isProduto ? Icons.inventory_2_rounded : Icons.miscellaneous_services_rounded,
                  color: isProduto ? Colors.blueAccent : Colors.purpleAccent,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (codigo != null && codigo.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            margin: const EdgeInsets.only(right: 6),
                            decoration: BoxDecoration(
                              color: Colors.blueAccent.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              codigo,
                              style: const TextStyle(color: Colors.blueAccent, fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          ),
                        Expanded(
                          child: Text(
                            nome,
                            style: TextStyle(
                              color: isDark ? Colors.white.withOpacity(0.9) : Colors.black87,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (isProduto && (item as Produto).grupo.isNotEmpty)
                      Text(
                        item.grupo,
                        style: TextStyle(color: isDark ? Colors.white.withOpacity(0.4) : Colors.black54, fontSize: 11),
                      ),
                  ],
                ),
              ),
              // Preço e Estoque
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _formatoMoeda.format(preco),
                    style: TextStyle(color: isDark ? Colors.greenAccent : const Color(0xFF15803D), fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  if (isProduto && estoque != null)
                    Text(
                      'Estoque: ${estoque.toInt()}',
                      style: TextStyle(
                        color: (estoque <= 0) ? (isDark ? Colors.redAccent.withOpacity(0.7) : Colors.red.shade800) : (isDark ? Colors.white.withOpacity(0.4) : Colors.black54),
                        fontSize: 11,
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 8),
              // Botão de adicionar
              IconButton(
                icon: const Icon(Icons.add_circle_outline_rounded, color: Colors.blueAccent, size: 24),
                onPressed: () => _adicionarAoCarrinho(item, manterFoco: true),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCardProduto(dynamic item, bool isProduto, {int index = -1}) {
    final nome = item.nome as String;
    final preco = isProduto
        ? (item as Produto).precoAtual
        : (item as Servico).preco;
    final promocao = isProduto ? (item as Produto).promocaoAtiva : false;
    final codigo = isProduto ? (item as Produto).codigo : null;
    final estoque = isProduto ? (item as Produto).estoque : null;

    final screenHeight = MediaQuery.of(context).size.height;
    final isSmallHeight = screenHeight < 750;
    final isSelected =
        !_focoNoCarrinho && _gridSelectedIndex == index && index != -1;

    return RepaintBoundary(
      child: InkWell(
        onTap: () {
          setState(() {
            _focoNoCarrinho = false;
            _gridSelectedIndex = index;
          });
          final isDiversos = isProduto && codigo == '9999';
          if (isDiversos) {
            final valorDigitado = double.tryParse(
              _termoBusca.replaceAll(',', '.').trim(),
            );
            _lancarDiversosRapido(precoInicial: valorDigitado);
          } else {
            _adicionarAoCarrinho(item, manterFoco: true);
          }
        },
        hoverColor: Colors.blueAccent.withOpacity(0.1),
        splashColor: Colors.blueAccent.withOpacity(0.2),
        borderRadius: BorderRadius.circular(isSmallHeight ? 10 : 12),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isProduto
                  ? (isDark ? [const Color(0xFF1E3A5F), const Color(0xFF2C3E50)] : [Colors.white, const Color(0xFFF1F5F9)])
                  : (isDark ? [const Color(0xFF4A1E5F), const Color(0xFF3E2C50)] : [Colors.white, const Color(0xFFF3E8FF)]),
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(isSmallHeight ? 10 : 12),
            border: Border.all(
              color: isSelected
                  ? Colors.cyanAccent
                  : (promocao
                        ? Colors.orange.withOpacity(0.5)
                        : (isDark ? Colors.transparent : Colors.black12)),
              width: isSelected ? 3 : (isDark ? 2 : 1),
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.cyanAccent.withOpacity(0.3),
                      blurRadius: 15,
                      spreadRadius: 2,
                    ),
                  ]
                : [
                    if (!isDark)
                      BoxShadow(
                        color: Colors.black.withOpacity(0.04),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                  ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(5),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      isProduto ? Icons.inventory_2 : Icons.build,
                      color: isProduto
                          ? (isDark ? Colors.lightBlueAccent : Colors.blue.shade700)
                          : (isDark ? Colors.purpleAccent : Colors.purple.shade700),
                      size: 14,
                    ),
                    const SizedBox(width: 4),
                    if (codigo != null && codigo.isNotEmpty)
                      Flexible(
                        child: Text(
                          codigo,
                          style: TextStyle(
                            color: isDark ? Colors.white70 : Colors.black87,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    if (isProduto && estoque != null) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: (estoque <= 0) 
                              ? Colors.red.withOpacity(0.2) 
                              : (isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.04)),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: (estoque <= 0) 
                                ? Colors.redAccent.withOpacity(0.5) 
                                : (isDark ? Colors.white10 : Colors.black12),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.inventory_2_outlined,
                              size: 8,
                              color: (estoque <= 0) ? (isDark ? Colors.redAccent : Colors.red.shade800) : (isDark ? Colors.white54 : Colors.black54),
                            ),
                            const SizedBox(width: 2),
                            Text(
                              estoque.toStringAsFixed(0),
                              style: TextStyle(
                                color: (estoque <= 0) ? (isDark ? Colors.redAccent : Colors.red.shade800) : (isDark ? Colors.white70 : Colors.black87),
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (promocao) ...[
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: Colors.orange,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'PROMO',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 8,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                    const Spacer(),
                    Icon(
                      Icons.add_circle,
                      color: isDark ? Colors.greenAccent.withOpacity(0.6) : Colors.green.shade700,
                      size: 18,
                    ),
                  ],
                ),
                const Spacer(),
                Text(
                  nome.toUpperCase(),
                  style: TextStyle(
                    color: isDark ? Colors.yellow.shade200 : const Color(0xFF0F172A),
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                    height: 1.1,
                    letterSpacing: 0.3,
                    shadows: isDark ? const [
                      Shadow(
                        color: Colors.black87,
                        blurRadius: 3,
                        offset: Offset(0, 1),
                      ),
                    ] : null,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  'R\$ ${preco.toStringAsFixed(2)}',
                  style: TextStyle(
                    color: promocao ? Colors.orange.shade800 : (isDark ? Colors.greenAccent : const Color(0xFF15803D)),
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCarrinhoMelhorado(DataService dataService) {
    return Column(
      children: [
        // Cabeçalho do carrinho - compacto e elegante
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              // Ícone com glow
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      Colors.cyanAccent.withOpacity(0.3),
                      Colors.cyanAccent.withOpacity(0.0),
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.cyanAccent.withOpacity(0.4),
                      blurRadius: 15,
                      spreadRadius: 2,
                    ),
                    BoxShadow(
                      color: Colors.cyanAccent.withOpacity(0.2),
                      blurRadius: 25,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.shopping_cart_rounded,
                  color: Colors.cyanAccent,
                  size: 22,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'CARRINHO',
                style: TextStyle(
                  color: textColor.withOpacity(0.9),
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  letterSpacing: 1.5,
                ),
              ),
              if (_mesaComandaVinculada != null) ...[
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _mesaComandaVinculada!.tipo == TipoControle.comanda 
                        ? Colors.purple.withOpacity(0.2) 
                        : Colors.orange.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _mesaComandaVinculada!.tipo == TipoControle.comanda 
                          ? Colors.purple.withOpacity(0.5) 
                          : Colors.orange.withOpacity(0.5),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _mesaComandaVinculada!.tipo == TipoControle.comanda 
                            ? Icons.receipt_long 
                            : Icons.table_restaurant,
                        size: 14,
                        color: _mesaComandaVinculada!.tipo == TipoControle.comanda 
                            ? Colors.purpleAccent 
                            : Colors.orangeAccent,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _mesaComandaVinculada!.numero,
                        style: TextStyle(
                          color: _mesaComandaVinculada!.tipo == TipoControle.comanda 
                              ? Colors.purpleAccent 
                              : Colors.orangeAccent,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const Spacer(),
              // Badge de itens com glow
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: isDark ? Colors.cyanAccent.withOpacity(0.2) : const Color(0xFFE0F2FE),
                  borderRadius: BorderRadius.circular(12),
                  border: isDark ? null : Border.all(color: const Color(0xFFBAE6FD)),
                  boxShadow: isDark ? [
                    BoxShadow(
                      color: Colors.cyanAccent.withOpacity(0.4),
                      blurRadius: 10,
                      spreadRadius: 1,
                    ),
                    BoxShadow(
                      color: Colors.cyanAccent.withOpacity(0.2),
                      blurRadius: 20,
                    ),
                  ] : null,
                ),
                child: Row(
                  children: [
                    Text(
                      '$_totalItens',
                      style: TextStyle(
                        color: isDark ? Colors.cyanAccent : const Color(0xFF0369A1),
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _totalItens == 1 ? 'ITEM' : 'ITENS',
                      style: TextStyle(
                        color: isDark ? Colors.cyanAccent : const Color(0xFF0369A1),
                        fontWeight: FontWeight.bold,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
              if (_carrinho.isNotEmpty || _mesaComandaVinculada != null) ...[
                const SizedBox(width: 8),
                if (_mesaComandaVinculada != null) ...[
                  Tooltip(
                    message: 'Limpar ${_mesaComandaVinculada!.tipo == TipoControle.comanda ? 'Comanda' : 'Mesa'} e Salvar Histórico',
                    child: GestureDetector(
                      onTap: _limparMesaComandaVinculada,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.cleaning_services_rounded,
                          color: Colors.blueAccent,
                          size: 18,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Tooltip(
                  message: 'Resetar Venda / Limpar Tudo',
                  child: GestureDetector(
                    onTap: () {
                      if (_mesaComandaVinculada != null) {
                        _resetarTodaVenda();
                      } else {
                        _limparCarrinho();
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.delete_sweep_rounded,
                        color: Colors.redAccent,
                        size: 18,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        // Linha divisória sutil com glow
        Container(
          height: 1,
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.transparent,
                Colors.cyanAccent.withOpacity(0.3),
                Colors.transparent,
              ],
            ),
          ),
        ),
        // Lista de itens
        Expanded(
          child: _carrinho.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.shopping_cart_outlined,
                        size: 64,
                        color: isDark ? Colors.white.withOpacity(0.15) : Colors.black26,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Carrinho vazio',
                        style: TextStyle(
                          color: isDark ? Colors.white.withOpacity(0.4) : Colors.black54,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Adicione produtos para começar',
                        style: TextStyle(
                          color: isDark ? Colors.white.withOpacity(0.25) : Colors.black38,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  controller: _carrinhoScrollController,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  itemCount: _carrinho.length,
                  itemBuilder: (context, index) {
                    // Reversed: index 0 = último adicionado (mais novo no topo)
                    final reversedIndex = _carrinho.length - 1 - index;
                    final item = _carrinho[reversedIndex];
                    final isNewest = index == 0;

                    return Dismissible(
                      key: Key('${item.id}_${reversedIndex}_${item.quantidade}'),
                      direction: DismissDirection.endToStart,
                      onDismissed: (_) => _removerItem(reversedIndex),
                      background: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.red.shade900.withOpacity(0.8),
                              Colors.red.shade700.withOpacity(0.9),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 16),
                        child: const Icon(
                          Icons.delete_forever_rounded,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 350),
                        curve: Curves.easeOut,
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isNewest
                                ? Colors.greenAccent.withOpacity(0.75)
                                : (_focoNoCarrinho && _cartSelectedIndex == reversedIndex
                                    ? Colors.cyanAccent
                                    : Colors.transparent),
                            width: 2,
                          ),
                          boxShadow: isNewest
                              ? [
                                  BoxShadow(
                                    color: Colors.greenAccent.withOpacity(0.2),
                                    blurRadius: 10,
                                    spreadRadius: 1,
                                  )
                                ]
                              : null,
                        ),
                        child: _ItemCarrinhoComHover(
                          item: item,
                          index: reversedIndex,
                          onAlterarQuantidade: (delta) =>
                              _alterarQuantidade(reversedIndex, delta),
                          onAplicarDesconto: () => _aplicarDescontoItem(reversedIndex),
                          onAlterarPreco: () => _alterarPrecoItem(reversedIndex),
                          onRemover: () => _removerItem(reversedIndex),
                          onRemoverDescontoDirect: () {
                            setState(() {
                              _carrinho[reversedIndex].desconto = 0.0;
                            });
                            _salvarCarrinho();
                          },
                          onDarBaixa: () => _darBaixaEstoqueItem(reversedIndex),
                          onAdicionarObservacao: () => _adicionarObservacaoItem(reversedIndex),
                          onToggleBrinde: () {
                            setState(() {
                              _carrinho[reversedIndex].isBrinde = !_carrinho[reversedIndex].isBrinde;
                              if (_carrinho[reversedIndex].isBrinde) {
                                _carrinho[reversedIndex].desconto = 0.0; // Reseta o desconto normal se virar brinde
                              }
                            });
                            _salvarCarrinho();
                          },
                          onToggleBaixaProporcional: () {
                            setState(() {
                              _carrinho[reversedIndex].baixaProporcional =
                                  !_carrinho[reversedIndex].baixaProporcional;
                            });
                            _salvarCarrinho();
                          },
                          onTrocarFormaVenda: _produtoTemMultiplasFormas(item)
                              ? () => _trocarFormaVendaItem(reversedIndex)
                              : null,
                        ),
                      ),
                    );
                  },
                ),
        ),
        // Linha divisória sutil antes do rodapé
        Container(
          height: 1,
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.transparent,
                Colors.greenAccent.withOpacity(0.3),
                Colors.transparent,
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.greenAccent.withOpacity(0.2),
                blurRadius: 4,
              ),
            ],
          ),
        ),
        // Rodapé compacto com glow - Ajustado para ser responsivo e não sumir o botão
        LayoutBuilder(
          builder: (context, constraints) {
            final screenHeight = MediaQuery.of(context).size.height;
            final isVerySmallHeight = screenHeight < 650;
            final isSmallHeight = screenHeight < 750;

            return Container(
              padding: EdgeInsets.symmetric(
                horizontal: isSmallHeight ? 8 : 14,
                vertical: isVerySmallHeight ? 4 : (isSmallHeight ? 8 : 14),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Cliente selecionado - mais compacto
                  if (_clienteSelecionado != null)
                    Container(
                      margin: EdgeInsets.only(
                        bottom: isVerySmallHeight ? 4 : 10,
                      ),
                      padding: EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: isVerySmallHeight ? 4 : 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.greenAccent.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.person_rounded,
                            color: Colors.greenAccent.withOpacity(0.7),
                            size: 16,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              _clienteSelecionado!.nome,
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.8),
                                fontSize: 12,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Botão EDITAR
                          GestureDetector(
                            onTap: () {
                              final dataService = Provider.of<DataService>(context, listen: false);
                               _editarCliente(dataService, _clienteSelecionado!);
                            },
                            child: Icon(
                              Icons.edit,
                              color: Colors.orangeAccent.withOpacity(0.7),
                              size: 14,
                            ),
                          ),
                          const SizedBox(width: 12),
                          GestureDetector(
                            onTap: () {
                              setState(() => _clienteSelecionado = null);
                              _salvarClienteSelecionado();
                            },
                            child: Icon(
                              Icons.close_rounded,
                              color: Colors.white.withOpacity(0.4),
                              size: 16,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (_tabelaPrecoAtiva != null)
                    GestureDetector(
                      onTap: () {
                        final dataService = Provider.of<DataService>(context, listen: false);
                        _selecionarTabelaPreco(dataService);
                      },
                      child: Container(
                        margin: EdgeInsets.only(
                          bottom: isVerySmallHeight ? 4 : 10,
                        ),
                        padding: EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: isVerySmallHeight ? 4 : 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.orangeAccent.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.orangeAccent.withOpacity(0.2)),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.price_change,
                              color: Colors.orangeAccent.withOpacity(0.8),
                              size: 16,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Tabela: $_tabelaPrecoAtiva',
                                style: TextStyle(
                                  color: Colors.orangeAccent.withOpacity(0.9),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Icon(
                              Icons.swap_horiz,
                              color: Colors.orangeAccent.withOpacity(0.6),
                              size: 14,
                            ),
                          ],
                        ),
                      ),
                    ),
                  // Desconto total e Total com efeito glow
                  // Painel de Total Vibrante e Gigante
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(
                      isVerySmallHeight ? 8 : (isSmallHeight ? 12 : 20),
                    ),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          const Color(0xFF0D0D15),
                          const Color(0xFF1A1A2E),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(
                        isSmallHeight ? 12 : 20,
                      ),
                      border: Border.all(
                        color: Colors.greenAccent.withOpacity(0.3),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.greenAccent.withOpacity(0.15),
                          blurRadius: isSmallHeight ? 15 : 30,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        // Subtotal e Descontos pequenos acima
                        if (_descontoTotal > 0) ...[
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'SUBTOTAL',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.4),
                                  fontSize: isVerySmallHeight ? 8 : 10,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1,
                                ),
                              ),
                              Text(
                                'R\$ ${_totalCarrinhoSemDesconto.toStringAsFixed(2)}',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.4),
                                  fontSize: isVerySmallHeight ? 9 : 11,
                                  decoration: TextDecoration.lineThrough,
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: isVerySmallHeight ? 2 : 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E4620).withOpacity(0.2), // Fundo verde escuro sutil
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: Colors.greenAccent.withOpacity(0.4),
                                width: 1,
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      Icons.local_offer_rounded,
                                      color: Colors.greenAccent[400],
                                      size: 14,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      'DESCONTO TOTAL',
                                      style: TextStyle(
                                        color: Colors.greenAccent[400],
                                        fontSize: isVerySmallHeight ? 10 : 12,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 1,
                                      ),
                                    ),
                                  ],
                                ),
                                Row(
                                  children: [
                                    Text(
                                      '- R\$ ${_descontoTotal.toStringAsFixed(2)}',
                                      style: TextStyle(
                                        color: Colors.greenAccent[400],
                                        fontSize: isVerySmallHeight ? 11 : 13,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    GestureDetector(
                                      onTap: () {
                                         setState(() {
                                           _descontoTotal = 0.0;
                                         });
                                         _storage.salvar(_keyDescontoTotalPDV, 0.0);
                                      },
                                      child: Icon(
                                        Icons.close_rounded,
                                        color: Colors.greenAccent[400]?.withOpacity(0.7),
                                        size: 16,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          Padding(
                            padding: EdgeInsets.symmetric(
                              vertical: isVerySmallHeight ? 6 : 12,
                            ),
                            child: const Divider(color: Colors.white10),
                          ),
                        ],
                        // O VALOR PRINCIPAL
                        Text(
                          'TOTAL A PAGAR',
                          style: TextStyle(
                            color: Colors.greenAccent.withOpacity(0.8),
                            fontSize: isVerySmallHeight
                                ? 9
                                : (isSmallHeight ? 10 : 12),
                            fontWeight: FontWeight.bold,
                            letterSpacing: 2,
                          ),
                        ),
                        SizedBox(height: isVerySmallHeight ? 2 : 4),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            'R\$ ${_totalCarrinho.toStringAsFixed(2)}',
                              style: TextStyle(
                                color: Colors.greenAccent,
                                fontSize: isVerySmallHeight
                                    ? 28
                                    : (isSmallHeight ? 32 : 42),
                                fontWeight: FontWeight.w900,
                                letterSpacing: -1.5,
                                shadows: [
                                  Shadow(
                                    color: Colors.greenAccent.withOpacity(0.7),
                                    offset: const Offset(0, 0),
                                    blurRadius: 10,
                                  ),
                                  Shadow(
                                    color: Colors.greenAccent.withOpacity(0.4),
                                    offset: const Offset(0, 0),
                                    blurRadius: 20,
                                  ),
                                ],
                              ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (_descontoTotal == 0) ...[
                              GestureDetector(
                                onTap: () => _aplicarDescontoTotal(),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: Colors.orange.withOpacity(0.2),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: const [
                                      Icon(
                                        Icons.discount_rounded,
                                        color: Colors.orangeAccent,
                                        size: 12,
                                      ),
                                      SizedBox(width: 4),
                                      Text(
                                        'ADD DESCONTO',
                                        style: TextStyle(
                                          color: Colors.orangeAccent,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                            ],
                            GestureDetector(
                              onTap: _carrinho.isEmpty ? null : () => _abrirDialogDividirConta(),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: _carrinho.isEmpty 
                                      ? Colors.white.withOpacity(0.05) 
                                      : Colors.blue.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: _carrinho.isEmpty 
                                        ? Colors.white.withOpacity(0.1) 
                                        : Colors.blueAccent.withOpacity(0.2),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.call_split_rounded,
                                      color: _carrinho.isEmpty ? Colors.white24 : Colors.blueAccent,
                                      size: 12,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      'DIVIDIR CONTA',
                                      style: TextStyle(
                                        color: _carrinho.isEmpty ? Colors.white24 : Colors.blueAccent,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: isVerySmallHeight ? 6 : 12),
                  // Botões de ação compactos com glow
                  Row(
                    children: [
                      // Botão Receber
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const PdvPage(
                                  abaInicial: 0, // 0 = Aba Receber
                                  esconderAbaVenda: true, // Esconde a aba Venda
                                ),
                              ),
                            );
                          },
                          child: Container(
                            padding: EdgeInsets.symmetric(
                              vertical: isVerySmallHeight ? 8 : 12,
                            ),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFFFF6B35), Color(0xFFFF8E53)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(10),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.orange.withOpacity(0.4),
                                  blurRadius: 12,
                                  spreadRadius: 0,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.receipt_long,
                                  color: Colors.white,
                                  size: isSmallHeight ? 16 : 18,
                                ),
                                SizedBox(width: isSmallHeight ? 4 : 6),
                                Text(
                                  'PEDIDOS',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: isSmallHeight ? 9 : 11,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.8,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Botão Salvar compacto
                      Expanded(
                        child: GestureDetector(
                          onTap: _carrinho.isEmpty
                              ? null
                              : () => _salvarVendaPendente(dataService, [], mostrarPromptImpressao: true),
                          child: Container(
                            padding: EdgeInsets.symmetric(
                              vertical: isVerySmallHeight ? 8 : 12,
                            ),
                            decoration: BoxDecoration(
                              color: _carrinho.isEmpty
                                  ? (isDark ? Colors.white.withOpacity(0.05) : Colors.grey.shade200)
                                  : (isDark ? Colors.orange.withOpacity(0.15) : const Color(0xFFFEF3C7)),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: _carrinho.isEmpty
                                    ? Colors.transparent
                                    : (isDark ? Colors.orange.withOpacity(0.3) : const Color(0xFFFCD34D)),
                              ),
                              boxShadow: _carrinho.isEmpty
                                  ? null
                                  : [
                                      BoxShadow(
                                        color: Colors.orange.withOpacity(0.2),
                                        blurRadius: 8,
                                      ),
                                    ],
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.bookmark_add_rounded,
                                  color: _carrinho.isEmpty
                                      ? (isDark ? Colors.white.withOpacity(0.2) : Colors.black26)
                                      : (isDark ? Colors.orange : const Color(0xFFD97706)),
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'SALVAR',
                                  style: TextStyle(
                                    color: _carrinho.isEmpty
                                        ? (isDark ? Colors.white.withOpacity(0.2) : Colors.black26)
                                        : (isDark ? Colors.orange : const Color(0xFFD97706)),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Botão Finalizar com glow verde
                      Expanded(
                        flex: 2,
                        child: GestureDetector(
                          onTap: _carrinho.isEmpty
                              ? null
                              : () => _finalizarVenda(dataService),
                          child: Container(
                            padding: EdgeInsets.symmetric(
                              vertical: isVerySmallHeight ? 8 : 12,
                            ),
                            decoration: BoxDecoration(
                              gradient: _carrinho.isEmpty
                                  ? null
                                  : LinearGradient(
                                      colors: [
                                        isDark ? Colors.greenAccent.withOpacity(0.3) : const Color(0xFF10B981),
                                        isDark ? Colors.green.withOpacity(0.3) : const Color(0xFF059669),
                                      ],
                                    ),
                              color: _carrinho.isEmpty
                                  ? (isDark ? Colors.white.withOpacity(0.05) : Colors.grey.shade200)
                                  : null,
                              borderRadius: BorderRadius.circular(10),
                              boxShadow: _carrinho.isEmpty
                                  ? null
                                  : [
                                      BoxShadow(
                                        color: Colors.green.withOpacity(
                                          isDark ? 0.4 : 0.25,
                                        ),
                                        blurRadius: 12,
                                        spreadRadius: 1,
                                      ),
                                    ],
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.shopping_cart_checkout_rounded,
                                  color: _carrinho.isEmpty
                                      ? (isDark ? Colors.white.withOpacity(0.2) : Colors.black26)
                                      : (isDark ? Colors.greenAccent : Colors.white),
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'FINALIZAR (F9)',
                                  style: TextStyle(
                                    color: _carrinho.isEmpty
                                        ? (isDark ? Colors.white.withOpacity(0.2) : Colors.black26)
                                        : (isDark ? Colors.greenAccent : Colors.white),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    letterSpacing: 1,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
  bool _globalKeyHandler(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    if (_dialogAberto || _estaFinalizando) return false;

    final dataService = Provider.of<DataService>(context, listen: false);
    final key = event.logicalKey;
    final bool searchFocused = _buscaFocusNode.hasFocus;

    // --- TECLAS DE FUNÇÃO (Sempre funcionam) ---
    if (key == LogicalKeyboardKey.f2) {
      if (!searchFocused) _buscaFocusNode.requestFocus();
      setState(() {
        _focoNoCarrinho = false;
        _focoNasCategorias = false;
        _gridSelectedIndex = -1;
        _cartSelectedIndex = -1;
        _categoriaSelectedIndex = -1;
      });
      return true;
    }
    if (key == LogicalKeyboardKey.f4) {
      setState(() {
        _focoNasCategorias = true;
        _categoriaSelectedIndex = 0;
        _focoNoCarrinho = false;
        _gridSelectedIndex = -1;
        _cartSelectedIndex = -1;
        if (!searchFocused) _atalhosFocusNode.requestFocus();
      });
      return true;
    }
    if (key == LogicalKeyboardKey.f6) {
      _selecionarCliente(dataService);
      return true;
    }
    if (key == LogicalKeyboardKey.f7) {
      _abrirLancamentoDespesa();
      return true;
    }
    if (key == LogicalKeyboardKey.f8) {
      if (_carrinho.isNotEmpty) _salvarVendaPendente(dataService, [], mostrarPromptImpressao: true);
      return true;
    }
    if (key == LogicalKeyboardKey.f9) {
      _finalizarVenda(dataService);
      return true;
    }
    if (key == LogicalKeyboardKey.f10) {
      _finalizarDinheiroDireto(dataService);
      return true;
    }

    // --- ATALHOS QUE CONFLITAM COM A BUSCA (Ignorados se buscando) ---
    if (searchFocused) return false;

    // CTRL para Conferência
    if (key == LogicalKeyboardKey.controlLeft || key == LogicalKeyboardKey.controlRight) {
       _abrirConferenciaItens();
       return true;
    }

    // SHIFT para Carrinho
    if (key == LogicalKeyboardKey.shiftLeft || key == LogicalKeyboardKey.shiftRight) {
      if (_carrinho.isNotEmpty) {
        setState(() {
          _focoNoCarrinho = true;
          _cartSelectedIndex = 0;
          _focoNasCategorias = false;
          _gridSelectedIndex = -1;
          _categoriaSelectedIndex = -1;
          _atalhosFocusNode.requestFocus();
        });
      }
      return true;
    }

    // ESC para Limpar
    if (key == LogicalKeyboardKey.escape) {
      _limparCarrinho();
      return true;
    }

    // SHIFT + DEL para Limpar Tudo
    if (key == LogicalKeyboardKey.delete && HardwareKeyboard.instance.isShiftPressed) {
      _limparCarrinho();
      return true;
    }

    // Operações no carrinho
    if (_carrinho.isNotEmpty) {
      if (key == LogicalKeyboardKey.add || key == LogicalKeyboardKey.numpadAdd) {
        _alterarQuantidade(_carrinho.length - 1, 1);
        return true;
      }
      if (key == LogicalKeyboardKey.minus || key == LogicalKeyboardKey.numpadSubtract) {
        if (_carrinho.last.quantidade > 1) {
          _alterarQuantidade(_carrinho.length - 1, -1);
        }
        return true;
      }
      if (HardwareKeyboard.instance.isControlPressed && key == LogicalKeyboardKey.keyD) {
        _aplicarDescontoItem(_carrinho.length - 1);
        return true;
      }
      if (HardwareKeyboard.instance.isControlPressed && key == LogicalKeyboardKey.delete) {
        _removerItem(_carrinho.length - 1);
        return true;
      }
    }

    return false;
  }
}

/// Widget de notificação de sucesso elegante no canto superior direito
class _NotificacaoSucesso extends StatefulWidget {
  final IconData icone;
  final String titulo;
  final String subtitulo;
  final Color cor;
  final String? info;
  final String? valorFormatado;
  final Duration duracao;
  final VoidCallback onDismiss;

  const _NotificacaoSucesso({
    required this.icone,
    required this.titulo,
    required this.subtitulo,
    required this.cor,
    this.info,
    this.valorFormatado,
    required this.duracao,
    required this.onDismiss,
  });

  @override
  State<_NotificacaoSucesso> createState() => _NotificacaoSucessoState();
}

class _NotificacaoSucessoState extends State<_NotificacaoSucesso>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(1.0, 0.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    _controller.forward();

    // Auto-dismiss após a duração
    Future.delayed(widget.duracao, () {
      if (mounted) {
        _dismiss();
      }
    });
  }

  void _dismiss() {
    _controller.reverse().then((_) {
      widget.onDismiss();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 20,
      right: 20,
      child: SlideTransition(
        position: _slideAnimation,
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Material(
            color: Colors.transparent,
            child: GestureDetector(
              onTap: _dismiss,
              onHorizontalDragEnd: (details) {
                if (details.primaryVelocity != null &&
                    details.primaryVelocity! > 0) {
                  _dismiss();
                }
              },
              child: Container(
                constraints: const BoxConstraints(maxWidth: 320),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A2E),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: widget.cor.withOpacity(0.5),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: widget.cor.withOpacity(0.2),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 15,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Ícone com animação de check
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0.0, end: 1.0),
                      duration: const Duration(milliseconds: 500),
                      curve: Curves.elasticOut,
                      builder: (context, value, child) {
                        return Transform.scale(
                          scale: value,
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  widget.cor.withOpacity(0.3),
                                  widget.cor.withOpacity(0.1),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              widget.icone,
                              color: widget.cor,
                              size: 28,
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(width: 14),
                    // Conteúdo
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.titulo,
                            style: TextStyle(
                              color: widget.cor,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.subtitulo,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.9),
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (widget.valorFormatado != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              widget.valorFormatado!,
                              style: TextStyle(
                                color: widget.cor,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                          if (widget.info != null) ...[
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                widget.info!,
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.6),
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Botão fechar
                    GestureDetector(
                      onTap: _dismiss,
                      child: Icon(
                        Icons.close_rounded,
                        color: Colors.white.withOpacity(0.4),
                        size: 18,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Notificação discreta e inteligente para itens adicionados ao carrinho
class _NotificacaoItemAdicionado extends StatefulWidget {
  final IconData icone;
  final String titulo;
  final String nomeItem;
  final double quantidade;
  final double quantidadeTotal;
  final double valorItem;
  final double totalCarrinho;
  final Color cor;
  final bool jaExistia;
  final VoidCallback onDismiss;

  const _NotificacaoItemAdicionado({
    required this.icone,
    required this.titulo,
    required this.nomeItem,
    required this.quantidade,
    required this.quantidadeTotal,
    required this.valorItem,
    required this.totalCarrinho,
    required this.cor,
    required this.jaExistia,
    required this.onDismiss,
  });

  @override
  State<_NotificacaoItemAdicionado> createState() =>
      _NotificacaoItemAdicionadoState();
}

class _NotificacaoItemAdicionadoState extends State<_NotificacaoItemAdicionado>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;
  final NumberFormat _formatoMoeda = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: 'R\$',
  );

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(
      begin: 0.8,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    _controller.forward();

    // Auto-dismiss em 0.3 segundos (muito mais rápido para o operador)
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        _dismiss();
      }
    });
  }

  void _dismiss() {
    _controller.reverse().then((_) {
      widget.onDismiss();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: const Alignment(0.0, -0.3), // Quase centro, um pouco acima para não cobrir tudo
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Material(
            color: Colors.transparent,
            child: GestureDetector(
              onTap: _dismiss,
              child: Container(
                constraints: const BoxConstraints(maxWidth: 350),
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 20,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFF1A1A2E).withOpacity(0.98),
                      const Color(0xFF16213E).withOpacity(0.98),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: widget.cor.withOpacity(0.5),
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: widget.cor.withOpacity(0.3),
                      blurRadius: 30,
                      spreadRadius: 2,
                    ),
                    BoxShadow(
                      color: Colors.black.withOpacity(0.5),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Ícone grande e visual
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: widget.cor.withOpacity(0.15),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: widget.cor.withOpacity(0.3),
                          width: 2,
                        ),
                      ),
                      child: Icon(widget.icone, color: widget.cor, size: 40),
                    ),
                    const SizedBox(height: 16),
                    // Título centralizado
                    Text(
                      widget.titulo.toUpperCase(),
                      style: TextStyle(
                        color: widget.cor,
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Nome do item principal
                    Text(
                      widget.nomeItem,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 12),
                    // Detalhes da quantidade e preço
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            widget.jaExistia
                                ? 'Qtd Total: ${widget.quantidadeTotal.toStringAsFixed(widget.quantidadeTotal.truncateToDouble() == widget.quantidadeTotal ? 0 : 2)}'
                                : 'Quantidade: ${widget.quantidade.toStringAsFixed(widget.quantidade.truncateToDouble() == widget.quantidade ? 0 : 2)}',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            '•',
                            style: TextStyle(color: Colors.white.withOpacity(0.3)),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            _formatoMoeda.format(widget.valorItem),
                            style: TextStyle(
                              color: widget.cor,
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Total do carrinho (o que mais importa)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.shopping_cart_checkout,
                          size: 16,
                          color: Colors.white.withOpacity(0.5),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'TOTAL CARRINHO: ',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.5),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          _formatoMoeda.format(widget.totalCarrinho),
                          style: const TextStyle(
                            color: Colors.cyanAccent,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Widget de item do carrinho com hover para mostrar descrição
class _ItemCarrinhoComHover extends StatefulWidget {
  final ItemCarrinho item;
  final int index;
  final Function(int) onAlterarQuantidade;
  final VoidCallback onAplicarDesconto;
  final VoidCallback onAlterarPreco;
  final VoidCallback onRemover;
  final VoidCallback onRemoverDescontoDirect;
  final VoidCallback onDarBaixa;
  final VoidCallback onAdicionarObservacao;
  final VoidCallback onToggleBrinde;
  final VoidCallback? onToggleBaixaProporcional;
  // Troca a forma de venda do item no carrinho (unidade/caixa/pacote/saco)
  final VoidCallback? onTrocarFormaVenda;

  const _ItemCarrinhoComHover({
    required this.item,
    required this.index,
    required this.onAlterarQuantidade,
    required this.onAplicarDesconto,
    required this.onAlterarPreco,
    required this.onRemover,
    required this.onRemoverDescontoDirect,
    required this.onDarBaixa,
    required this.onAdicionarObservacao,
    required this.onToggleBrinde,
    this.onToggleBaixaProporcional,
    this.onTrocarFormaVenda,
  });

  @override
  State<_ItemCarrinhoComHover> createState() => _ItemCarrinhoComHoverState();
}

class _ItemCarrinhoComHoverState extends State<_ItemCarrinhoComHover> {
  OverlayEntry? _overlayEntry;
  final GlobalKey _itemKey = GlobalKey();

  /// Rótulo amigável da unidade de venda do item no carrinho.
  String _rotuloUnidadeVenda(String unidadeVenda) {
    switch (unidadeVenda) {
      case 'caixa':
        return 'CAIXA';
      case 'pacote':
        return 'PACOTE';
      case 'saco':
        return 'SACO';
      default:
        return 'UNIDADE';
    }
  }

  String? _obterCodigoProduto(ItemCarrinho item) {
    if (item.isServico) return null;

    final dataService = Provider.of<DataService>(context, listen: false);
    Produto? produto;
    for (final p in dataService.produtos) {
      if (p.id == item.id) {
        produto = p;
        break;
      }
    }

    final codigo = produto?.codigo?.trim();
    if (codigo != null && codigo.isNotEmpty) return codigo;

    final codigoBarras = produto?.codigoBarras?.trim();
    if (codigoBarras != null && codigoBarras.isNotEmpty) return codigoBarras;

    return null;
  }

  /// Texto da conversão de baixa do produto composto (ex.: "1 litro a cada 1000 ml") ou null se não houver
  String? _textoConversaoBaixa(ItemCarrinho item) {
    if (item.isServico) return null;
    final dataService = Provider.of<DataService>(context, listen: false);
    for (final p in dataService.produtos) {
      if (p.id == item.id && p.ehComposto) {
        for (final c in p.composicao) {
          if (c.pesoTotalSaco != null && c.fracaoBase != null) {
            return textoConversao(
              c.fracaoBase!,
              c.pesoTotalSaco!,
              unidadeBaixa: c.unidadeBaixa,
              unidadeVenda: c.unidadeVenda,
            );
          }
        }
      }
    }
    return null;
  }

  void _showDescricao() {
    if (widget.item.descricao == null || widget.item.descricao!.isEmpty) {
      return;
    }

    final RenderBox? renderBox =
        _itemKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final position = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;

    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        left: position.dx,
        top: position.dy + size.height + 4,
        width: size.width,
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A2E),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Colors.white.withOpacity(0.2),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.5),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Text(
              widget.item.descricao!,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ),
        ),
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  void _hideDescricao() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  @override
  void dispose() {
    _hideDescricao();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final item = widget.item;
    final codigoProduto = _obterCodigoProduto(item);
    final textoConversaoBaixa = _textoConversaoBaixa(item);
    final corPrincipal = item.isServico
        ? Colors.purpleAccent
        : Colors.greenAccent;
    final corBackground = item.isServico ? Colors.purple : Colors.green;
    final screenHeight = MediaQuery.of(context).size.height;
    final isSmallHeight = screenHeight < 750;

    return MouseRegion(
      key: _itemKey,
      onEnter: (_) {
        if (item.descricao != null && item.descricao!.isNotEmpty) {
          _showDescricao();
        }
      },
      onExit: (_) {
        _hideDescricao();
      },
      child: Container(
        margin: EdgeInsets.only(bottom: isSmallHeight ? 4 : 8),
        padding: EdgeInsets.all(isSmallHeight ? 8 : 12),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withOpacity(0.05) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(isSmallHeight ? 12 : 16),
          border: Border.all(color: isDark ? Colors.white.withOpacity(0.03) : Colors.black12),
          boxShadow: [
            if (!isDark)
              BoxShadow(
                color: Colors.black.withOpacity(0.03),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
          ],
        ),
        child: Column(
          children: [
            // Linha Superior: Ícone, Nome e Botão Remover
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Ícone compacto
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: isDark ? corBackground.withOpacity(0.15) : (item.isServico ? Colors.purple.shade50 : Colors.green.shade50),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    item.isServico
                        ? Icons.build_rounded
                        : Icons.inventory_2_rounded,
                    color: isDark ? corPrincipal.withOpacity(0.8) : (item.isServico ? Colors.purple.shade700 : Colors.green.shade700),
                    size: isSmallHeight ? 16 : 20,
                  ),
                ),
                SizedBox(width: isSmallHeight ? 8 : 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Text(
                              item.nome,
                              style: TextStyle(
                                color: isDark ? Colors.white : Colors.black87,
                                fontWeight: FontWeight.bold,
                                fontSize: isSmallHeight ? 14 : 16,
                                height: 1.2,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (item.isBrinde) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.redAccent.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: Colors.redAccent.withOpacity(0.5)),
                              ),
                              child: const Text(
                                'BRINDE',
                                style: TextStyle(
                                  color: Colors.redAccent,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (codigoProduto != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: isDark ? Colors.white.withOpacity(0.07) : Colors.grey.shade200,
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: isDark ? Colors.white.withOpacity(0.12) : Colors.black12,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.qr_code_2_rounded,
                                  size: isSmallHeight ? 10 : 12,
                                  color: isDark ? Colors.white.withOpacity(0.65) : Colors.black54,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Cod: $codigoProduto',
                                  style: TextStyle(
                                    color: isDark ? Colors.white.withOpacity(0.75) : Colors.black87,
                                    fontSize: isSmallHeight ? 9 : 10,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ),
                      if (item.unidadeVenda != null && item.unidadeVenda!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.blueAccent.withOpacity(0.15)
                                  : Colors.blue.shade50,
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: isDark
                                    ? Colors.blueAccent.withOpacity(0.35)
                                    : Colors.blue.shade200,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  item.unidadeVenda == 'caixa'
                                      ? Icons.inventory_outlined
                                      : (item.unidadeVenda == 'pacote'
                                          ? Icons.widgets_outlined
                                          : (item.unidadeVenda == 'saco'
                                              ? Icons.shopping_bag_outlined
                                              : Icons.inventory_2_outlined)),
                                  size: isSmallHeight ? 10 : 12,
                                  color: isDark
                                      ? Colors.blueAccent
                                      : Colors.blue.shade700,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _rotuloUnidadeVenda(item.unidadeVenda!),
                                  style: TextStyle(
                                    color: isDark
                                        ? Colors.blueAccent
                                        : Colors.blue.shade700,
                                    fontSize: isSmallHeight ? 9 : 10,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      if (item.descontoPromocionalPercent != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.orangeAccent.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(color: Colors.orangeAccent.withOpacity(0.45)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.local_offer_outlined, size: 12, color: Colors.orangeAccent),
                                const SizedBox(width: 4),
                                Text(
                                  '${item.descontoPromocionalPercent!.toStringAsFixed(0)}% OFF',
                                  style: TextStyle(
                                    color: Colors.orangeAccent,
                                    fontSize: isSmallHeight ? 9 : 10,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      if (textoConversaoBaixa != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: InkWell(
                            onTap: () => widget.onToggleBaixaProporcional?.call(),
                            borderRadius: BorderRadius.circular(999),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: item.baixaProporcional
                                    ? Colors.amber.withOpacity(0.15)
                                    : Colors.blueAccent.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: item.baixaProporcional
                                      ? Colors.amber.withOpacity(0.45)
                                      : Colors.blueAccent.withOpacity(0.45),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    item.baixaProporcional ? Icons.scale_outlined : Icons.inventory_2_outlined,
                                    size: 12,
                                    color: item.baixaProporcional ? Colors.amber : Colors.blueAccent,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    item.baixaProporcional
                                        ? 'Baixa proporcional: $textoConversaoBaixa'
                                        : 'Baixa direta (unidade)',
                                    style: TextStyle(
                                      color: item.baixaProporcional ? Colors.amber : Colors.blueAccent,
                                      fontSize: isSmallHeight ? 9 : 10,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      if (item.adicionais != null && item.adicionais!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: item.adicionais!.map((a) => Padding(
                              padding: const EdgeInsets.only(bottom: 2),
                              child: Row(
                                children: [
                                  Icon(Icons.add_circle_outline, color: isDark ? Colors.greenAccent.withOpacity(0.5) : Colors.green.shade700, size: 10),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      '${a.nome} (+ R\$ ${a.preco.toStringAsFixed(2)})',
                                      style: TextStyle(
                                        color: isDark ? Colors.white.withOpacity(0.5) : Colors.black54,
                                        fontSize: 10,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            )).toList(),
                          ),
                        ),
                      if (item.opcoesCombo != null && item.opcoesCombo.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: item.opcoesCombo.map((o) => Padding(
                              padding: const EdgeInsets.only(bottom: 2),
                              child: Row(
                                children: [
                                  Icon(Icons.subdirectory_arrow_right_rounded, color: isDark ? Colors.blueAccent.withOpacity(0.6) : Colors.blue.shade700, size: 10),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      '${o.nome}${o.precoAdicional > 0 ? " (+ R\$ ${o.precoAdicional.toStringAsFixed(2)})" : ""}',
                                      style: TextStyle(
                                        color: isDark ? Colors.white.withOpacity(0.55) : Colors.black54,
                                        fontSize: 10.5,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            )).toList(),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                // Botão Remover discreto
                GestureDetector(
                  onTap: widget.onRemover,
                  child: Icon(
                    Icons.close_rounded,
                    color: isDark ? Colors.white.withOpacity(0.25) : Colors.black38,
                    size: isSmallHeight ? 16 : 18,
                  ),
                ),
              ],
            ),
            if (item.observacao != null && item.observacao!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline_rounded, color: Colors.orangeAccent, size: 14),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          item.observacao!,
                          style: TextStyle(
                            color: isDark ? Colors.white.withOpacity(0.7) : Colors.black87,
                            fontSize: 11,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            SizedBox(height: isSmallHeight ? 6 : 12),
            // Linha Inferior: Controles, Desconto e Subtotal
            Row(
              children: [
                // Controles de Quantidade
                Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.black.withOpacity(0.2) : Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GestureDetector(
                        onTap: () => widget.onAlterarQuantidade(-1),
                        child: Container(
                          padding: EdgeInsets.all(isSmallHeight ? 4 : 6),
                          decoration: BoxDecoration(
                            color: isDark ? Colors.white.withOpacity(0.05) : Colors.white,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            Icons.remove_rounded,
                            color: item.quantidade > 1
                                ? (isDark ? Colors.white70 : Colors.black87)
                                : Colors.redAccent.withOpacity(0.5),
                            size: isSmallHeight ? 12 : 14,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: isSmallHeight ? 24 : 28,
                        child: Text(
                          '${item.quantidade}',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: isDark ? Colors.white : Colors.black87,
                            fontWeight: FontWeight.bold,
                            fontSize: isSmallHeight ? 12 : 14,
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: () => widget.onAlterarQuantidade(1),
                        child: Container(
                          padding: EdgeInsets.all(isSmallHeight ? 4 : 6),
                          decoration: BoxDecoration(
                            color: isDark ? corPrincipal.withOpacity(0.1) : (item.isServico ? Colors.purple.shade100 : Colors.green.shade100),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            Icons.add_rounded,
                            color: isDark ? corPrincipal : (item.isServico ? Colors.purple.shade800 : Colors.green.shade800),
                            size: isSmallHeight ? 12 : 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: isSmallHeight ? 4 : 8),
                // Botão de Desconto
                GestureDetector(
                  onTap: widget.onAplicarDesconto,
                  child: Container(
                    padding: EdgeInsets.all(isSmallHeight ? 6 : 8),
                    decoration: BoxDecoration(
                      color: item.desconto > 0
                          ? Colors.orange.withOpacity(0.2)
                          : (isDark ? Colors.white.withOpacity(0.05) : Colors.grey.shade200),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.discount_rounded,
                      color: item.desconto > 0
                          ? Colors.orangeAccent
                          : (isDark ? Colors.white30 : Colors.black38),
                      size: isSmallHeight ? 12 : 14,
                    ),
                  ),
                ),
                SizedBox(width: isSmallHeight ? 4 : 8),
                // Botão de Trocar Forma de Venda (apenas quando o produto tem múltiplas formas)
                if (widget.onTrocarFormaVenda != null) ...[
                  GestureDetector(
                    onTap: widget.onTrocarFormaVenda,
                    child: Container(
                      padding: EdgeInsets.all(isSmallHeight ? 6 : 8),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.blueAccent.withOpacity(0.12)
                            : Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.swap_horiz_rounded,
                        color: isDark ? Colors.blueAccent : Colors.blue.shade700,
                        size: isSmallHeight ? 12 : 14,
                      ),
                    ),
                  ),
                  SizedBox(width: isSmallHeight ? 4 : 8),
                ],
                // Botão de Observações
                GestureDetector(
                  onTap: widget.onAdicionarObservacao,
                  child: Container(
                    padding: EdgeInsets.all(isSmallHeight ? 6 : 8),
                    decoration: BoxDecoration(
                      color: (item.observacao != null && item.observacao!.isNotEmpty)
                          ? Colors.blue.withOpacity(0.15)
                          : (isDark ? Colors.white.withOpacity(0.05) : Colors.grey.shade200),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.notes_rounded,
                      color: (item.observacao != null && item.observacao!.isNotEmpty)
                          ? Colors.blueAccent
                          : (isDark ? Colors.white30 : Colors.black38),
                      size: isSmallHeight ? 12 : 14,
                    ),
                  ),
                ),
                SizedBox(width: isSmallHeight ? 4 : 8),
                // Botão de Brinde
                GestureDetector(
                  onTap: widget.onToggleBrinde,
                  child: Container(
                    padding: EdgeInsets.all(isSmallHeight ? 6 : 8),
                    decoration: BoxDecoration(
                      color: item.isBrinde
                          ? Colors.redAccent.withOpacity(0.2)
                          : (isDark ? Colors.white.withOpacity(0.05) : Colors.grey.shade200),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: item.isBrinde
                            ? Colors.redAccent.withOpacity(0.4)
                            : Colors.transparent,
                        width: 1,
                      ),
                    ),
                    child: Icon(
                      item.isBrinde ? Icons.card_giftcard : Icons.card_giftcard_outlined,
                      color: item.isBrinde
                          ? Colors.redAccent
                          : (isDark ? Colors.white30 : Colors.black38),
                      size: isSmallHeight ? 12 : 14,
                    ),
                  ),
                ),

                const Spacer(),
                // Preço e Subtotal
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (item.desconto > 0)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          GestureDetector(
                            onTap: () {
                               widget.onRemoverDescontoDirect();
                            },
                            child: Icon(
                              Icons.close_rounded,
                              color: Colors.orangeAccent.withOpacity(0.5),
                              size: 10,
                            ),
                          ),
                          const SizedBox(width: 2),
                          Text(
                            '- R\$ ${item.desconto.toStringAsFixed(2)}',
                            style: TextStyle(
                              color: Colors.orangeAccent,
                              fontSize: isSmallHeight ? 9 : 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    GestureDetector(
                      onTap: widget.onAlterarPreco,
                      child: Tooltip(
                        message: 'Clique para alterar o preço unitário do produto',
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: item.tevePrecoAlterado
                                ? (item.foiVendidoMenor
                                    ? Colors.redAccent.withOpacity(0.18)
                                    : Colors.greenAccent.withOpacity(0.18))
                                : (isDark ? Colors.white.withOpacity(0.04) : Colors.grey.shade100),
                            borderRadius: BorderRadius.circular(6),
                            border: item.tevePrecoAlterado
                                ? Border.all(
                                    color: item.foiVendidoMenor
                                        ? Colors.redAccent.withOpacity(0.5)
                                        : Colors.greenAccent.withOpacity(0.5),
                                    width: 1,
                                  )
                                : Border.all(color: isDark ? Colors.white.withOpacity(0.08) : Colors.black12, width: 1),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              if (item.tevePrecoAlterado)
                                Text(
                                  item.foiVendidoMenor
                                      ? '🔻 Orig: R\$ ${item.precoOriginal.toStringAsFixed(2)}'
                                      : '🔺 Orig: R\$ ${item.precoOriginal.toStringAsFixed(2)}',
                                  style: TextStyle(
                                    color: item.foiVendidoMenor ? Colors.redAccent : Colors.greenAccent,
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.edit_outlined,
                                    size: 11,
                                    color: isDark ? corPrincipal.withOpacity(0.7) : (item.isServico ? Colors.purple.shade700 : Colors.green.shade700),
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    'R\$ ${item.subtotal.toStringAsFixed(2)}',
                                    style: TextStyle(
                                      color: isDark ? corPrincipal : (item.isServico ? Colors.purple.shade800 : Colors.green.shade800),
                                      fontWeight: FontWeight.w900,
                                      fontSize: isSmallHeight ? 14 : 16,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// Widget separado para o seletor de cliente - evita problemas de renderização
class _SeletorClienteWidget extends StatefulWidget {
  final DataService dataService;
  final String? clienteSelecionadoId;
  final Function(Cliente) onClienteSelecionado;
  final VoidCallback onRemoverCliente;

  const _SeletorClienteWidget({
    required this.dataService,
    required this.clienteSelecionadoId,
    required this.onClienteSelecionado,
    required this.onRemoverCliente,
  });

  @override
  State<_SeletorClienteWidget> createState() => _SeletorClienteWidgetState();
}

class _SeletorClienteWidgetState extends State<_SeletorClienteWidget> {
  String _busca = '';
  final TextEditingController _buscaController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final clientes = _clientesFiltrados;

    return Container(
      height: MediaQuery.of(context).size.height * 0.95,
      decoration: const BoxDecoration(
        color: Color(0xFF1E1E2E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Título
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                const Icon(Icons.person_search, color: Colors.blue, size: 28),
                const SizedBox(width: 12),
                const Text(
                  'Selecionar Cliente',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                if (widget.clienteSelecionadoId != null)
                  GestureDetector(
                    onTap: _removerCliente,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.person_off,
                            color: Colors.orange,
                            size: 18,
                          ),
                          SizedBox(width: 4),
                          Text(
                            'Remover',
                            style: TextStyle(
                              color: Colors.orange,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // Campo de busca
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: TextField(
                      controller: _buscaController,
                      autofocus: true,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Buscar por nome, telefone ou CPF/CNPJ...',
                        hintStyle: TextStyle(
                          color: Colors.white.withOpacity(0.4),
                        ),
                        prefixIcon: const Icon(
                          Icons.search,
                          color: Colors.white54,
                        ),
                        suffixIcon: _busca.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, color: Colors.white54),
                                onPressed: () {
                                  _buscaController.clear();
                                  setState(() => _busca = '');
                                },
                              )
                            : null,
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                      ),
                      onChanged: (value) => setState(() => _busca = value),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Botão novo cliente
                GestureDetector(
                  onTap: _cadastrarNovoCliente,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.green,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.person_add, color: Colors.white, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'Novo',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Lista de clientes
          Expanded(
            child: clientes.isEmpty
                ? _buildEstadoVazio()
                : _buildListaClientes(clientes),
          ),
        ],
      ),
    );
  }


  @override
  void dispose() {
    _buscaController.dispose();
    super.dispose();
  }

  List<Cliente> get _clientesFiltrados {
    if (_busca.isEmpty) {
      return widget.dataService.clientes;
    }
    final termo = _busca.toLowerCase();
    return widget.dataService.clientes.where((c) {
      return c.nome.toLowerCase().contains(termo) ||
          c.telefone.contains(termo) ||
          (c.cpfCnpj?.contains(termo) ?? false);
    }).toList();
  }

  void _selecionarCliente(Cliente cliente) {
    Navigator.of(context).pop();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onClienteSelecionado(cliente);
    });
  }

  void _removerCliente() {
    Navigator.of(context).pop();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onRemoverCliente();
    });
  }

  Future<void> _cadastrarNovoCliente() async {
    Navigator.of(context).pop();
    await Future.delayed(const Duration(milliseconds: 100));
    if (!mounted) return;

    final novoCliente = await Navigator.push<Cliente>(
      context,
      MaterialPageRoute(builder: (context) => const ClienteDetalhesPage()),
    );

    if (novoCliente != null && mounted) {
      widget.onClienteSelecionado(novoCliente);
    }
  }

  Widget _buildEstadoVazio() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.person_off,
            size: 48,
            color: Colors.white.withOpacity(0.3),
          ),
          const SizedBox(height: 12),
          Text(
            _busca.isEmpty
                ? 'Nenhum cliente cadastrado'
                : 'Nenhum cliente encontrado',
            style: TextStyle(color: Colors.white.withOpacity(0.5)),
          ),
          const SizedBox(height: 20),
          GestureDetector(
            onTap: _cadastrarNovoCliente,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.green,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.person_add, color: Colors.white),
                  const SizedBox(width: 8),
                  Text(
                    _busca.isNotEmpty
                        ? 'Cadastrar "$_busca"'
                        : 'Cadastrar Cliente',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildListaClientes(List<Cliente> clientes) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: clientes.length,
      itemBuilder: (context, index) {
        final cliente = clientes[index];
        final isSelected = widget.clienteSelecionadoId == cliente.id;

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _selecionarCliente(cliente),
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isSelected
                  ? Colors.green.withOpacity(0.2)
                  : const Color(0xFF2A2A3E),
              borderRadius: BorderRadius.circular(12),
              border: isSelected
                  ? Border.all(color: Colors.green, width: 2)
                  : null,
            ),
            child: Row(
              children: [
                // Avatar simples
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? Colors.green
                        : Colors.blue.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    cliente.nome.isNotEmpty
                        ? cliente.nome[0].toUpperCase()
                        : '?',
                    style: TextStyle(
                      color: isSelected ? Colors.white : Colors.blue,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                // Informações
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        cliente.nome,
                        style: TextStyle(
                          color: isSelected ? Colors.greenAccent : Colors.white,
                          fontSize: 16,
                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        cliente.telefone,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.5),
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                // Botão Editar
                IconButton(
                  icon: const Icon(Icons.edit, color: Colors.white54, size: 20),
                  onPressed: () async {
                    final resultado = await Navigator.push<Cliente>(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ClienteDetalhesPage(cliente: cliente),
                      ),
                    );
                    if (resultado != null && mounted) {
                      // Se o cliente foi editado, atualizar na lista (via dataService)
                      // O dataService já é atualizado dentro da ClienteDetalhesPage
                      // Mas talvez precisemos forçar um refresh aqui se não for via Provider
                      setState(() {});
                    }
                  },
                  tooltip: 'Editar cliente',
                ),
                // Indicador de seleção
                if (isSelected)
                  const Icon(
                    Icons.check_circle,
                    color: Colors.greenAccent,
                    size: 28,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// Dialog de pagamento do PDV - usa a mesma lógica do PagamentoWidget
class _DialogPagamentoPDV extends StatefulWidget {
  final double subtotal;
  final double descontoTotal;
  final double totalCarrinho;
  final List<PagamentoPedido> pagamentosIniciais;
  final Function(List<PagamentoPedido>, double, double) onConfirmar;
  final Function(List<PagamentoPedido>) onSalvarPendente;
  final Cliente? cliente; // Cliente para validar limite de crédito
  final String? cpfCnpjInicial; 
  final String? nomeInicial;
  final Function(String?, String?) onDadosConsumidorChanged;

  const _DialogPagamentoPDV({
    required this.subtotal,
    required this.descontoTotal,
    required this.totalCarrinho,
    required this.pagamentosIniciais,
    required this.onConfirmar,
    required this.onSalvarPendente,
    this.cliente,
    this.cpfCnpjInicial,
    this.nomeInicial,
    required this.onDadosConsumidorChanged,
  });

  @override
  State<_DialogPagamentoPDV> createState() => _DialogPagamentoPDVState();
}

class _DialogPagamentoPDVState extends State<_DialogPagamentoPDV> {
  late List<PagamentoPedido> _pagamentos;
  bool _estaConfirmando = false; // Flag local para o botão
  final _formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  final _formatoData = DateFormat('dd/MM/yyyy');
  final FocusNode _focusNode = FocusNode();
  int _selectedPaymentIndex = -1;
  double _descontoAutomatico = 0.0;
  double _acrescimoAutomatico = 0.0; // índice do pagamento selecionado na lista
  late TextEditingController _cpfController;
  late TextEditingController _nomeController;

  @override
  void initState() {
    super.initState();
    _pagamentos = List.from(widget.pagamentosIniciais);
    _cpfController = TextEditingController(text: widget.cpfCnpjInicial);
    _nomeController = TextEditingController(text: widget.nomeInicial);
    _focusNode.requestFocus();
    
    // Handler global para o diálogo de pagamento
    HardwareKeyboard.instance.addHandler(_dialogKeyHandler);
  }

  bool _dialogKeyHandler(KeyEvent event) {
    if (event is! KeyDownEvent) return false;

    // F9 no diálogo: Confirmar ou Salvar
    if (event.logicalKey == LogicalKeyboardKey.f9) {
      if (_estaConfirmando) return true;
      if (_pagamentoCompleto) {
        setState(() => _estaConfirmando = true);
        widget.onConfirmar(_pagamentos, _descontoAutomatico, _acrescimoAutomatico);
      } else {
        widget.onSalvarPendente(_pagamentos);
      }
      return true;
    }

    // ESC no diálogo: Fechar
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      Navigator.pop(context);
      return true;
    }

    return false;
  }

  @override
  void dispose() {
    _cpfController.dispose();
    _nomeController.dispose();
    HardwareKeyboard.instance.removeHandler(_dialogKeyHandler);
    super.dispose();
  }

  double get _totalLancado => _pagamentos.fold(0.0, (sum, p) => sum + p.valor);
  double get _valorRestante => widget.totalCarrinho - _totalLancado;
  bool get _pagamentoCompleto => _valorRestante <= 0.01;
  double get _totalTroco => _pagamentos
      .where((p) => p.troco != null && p.troco! > 0)
      .fold(0.0, (sum, p) => sum + (p.troco ?? 0));

  void _adicionarPagamento(TipoPagamento tipo) {
    // Se for uma venda salva (tem pagamentos iniciais do tipo "outro") e o usuário
    // escolher um novo tipo de pagamento, limpar os pagamentos antigos do tipo "outro"
    // ANTES de verificar o valor restante, para que não bloqueie a adição do novo pagamento.
    if (widget.pagamentosIniciais.isNotEmpty && tipo != TipoPagamento.outro) {
      final temPagamentosOutro = _pagamentos.any(
        (p) => p.tipo == TipoPagamento.outro && !p.recebido,
      );

      if (temPagamentosOutro) {
        // Remover todos os pagamentos do tipo "outro" que não foram recebidos
        setState(() {
          _pagamentos.removeWhere(
            (p) => p.tipo == TipoPagamento.outro && !p.recebido,
          );
        });
      }
    }

    
    final dataService = Provider.of<DataService>(context, listen: false);
    final pagamentosConfig = dataService.empresaAtual?.configuracoes?['pagamentos'] as Map?;
    final config = pagamentosConfig?[tipo.name] as Map?;
    final descontoPerc = (config?['descontoPerc'] as num?)?.toDouble() ?? 0.0;
    final acrescimoPerc = (config?['acrescimoPerc'] as num?)?.toDouble() ?? 0.0;

    double valorASugerir = _valorRestante > 0 ? _valorRestante : 0.0;
    
    // Calcula desconto ou acréscimo automático sobre o valor restante
    double descontoAplicadoLocal = 0.0;
    double acrescimoAplicadoLocal = 0.0;
    if (descontoPerc > 0 && valorASugerir > 0) {
      descontoAplicadoLocal = valorASugerir * (descontoPerc / 100);
      valorASugerir -= descontoAplicadoLocal;
    } else if (acrescimoPerc > 0 && valorASugerir > 0) {
      acrescimoAplicadoLocal = valorASugerir * (acrescimoPerc / 100);
      valorASugerir += acrescimoAplicadoLocal;
    }

    final valorSugerido = valorASugerir;

    if (_valorRestante <= 0 && tipo != TipoPagamento.outro) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('A venda já está totalmente paga. Remova um pagamento se desejar alterar.'),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // Validação especial para Fiado
    if (tipo == TipoPagamento.fiado) {
      // Verificar se tem cliente selecionado
      if (widget.cliente == null) {
        _mostrarErroSemClienteFiado();
        return;
      }

      // Verificar se o cliente tem limite de crédito
      if (widget.cliente!.limiteCredito == null ||
          widget.cliente!.limiteCredito! <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error, color: Colors.white),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${widget.cliente!.nome} não possui limite de crédito cadastrado',
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            margin: EdgeInsets.only(
              bottom: MediaQuery.of(context).size.height - 150,
              left: 16,
              right: 16,
            ),
          ),
        );
        return;
      }

      if (widget.cliente!.bloqueado) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.block, color: Colors.white),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${widget.cliente!.nome} está bloqueado para compras fiado',
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            margin: EdgeInsets.only(
              bottom: MediaQuery.of(context).size.height - 150,
              left: 16,
              right: 16,
            ),
          ),
        );
        return;
      }

      // Verificar se o cliente tem crédito disponível
      if (!widget.cliente!.podeFiar(valorSugerido)) {
        final disponivelFormatado = NumberFormat.currency(
          locale: 'pt_BR',
          symbol: 'R\$',
        ).format(widget.cliente!.creditoDisponivel);
        final limiteFormatado = NumberFormat.currency(
          locale: 'pt_BR',
          symbol: 'R\$',
        ).format(widget.cliente!.limiteCredito);
        final devedorFormatado = NumberFormat.currency(
          locale: 'pt_BR',
          symbol: 'R\$',
        ).format(widget.cliente!.saldoDevedor);

        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF1E1E2E),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Row(
              children: [
                Icon(Icons.warning, color: Colors.orange),
                SizedBox(width: 12),
                Text('Limite Excedido', style: TextStyle(color: Colors.white)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${widget.cliente!.nome} não possui crédito suficiente.',
                  style: const TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 16),
                _buildInfoCredito('Limite Total', limiteFormatado, Colors.blue),
                _buildInfoCredito(
                  'Saldo Devedor',
                  devedorFormatado,
                  Colors.red,
                ),
                _buildInfoCredito(
                  'Disponível',
                  disponivelFormatado,
                  Colors.green,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Entendi'),
              ),
            ],
          ),
        );
        return;
      }
    }

    // Validação especial para Crediário
    if (tipo == TipoPagamento.crediario) {
      // Verificar se tem cliente selecionado
      if (widget.cliente == null) {
        _mostrarErroSemClienteCrediario();
        return;
      }
    }

    _mostrarDialogPagamento(tipo, valorSugerido, descontoCalc: descontoAplicadoLocal, acrescimoCalc: acrescimoAplicadoLocal);
  }

  // Mostra mensagem de erro centralizada quando tenta usar crediário sem cliente
  void _mostrarErroSemClienteCrediario() {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: Colors.pink.withOpacity(0.5), width: 2),
        ),
        content: Container(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Ícone de erro grande
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.pink.withOpacity(0.15),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.pink.withOpacity(0.4),
                    width: 3,
                  ),
                ),
                child: const Icon(
                  Icons.person_off,
                  color: Colors.pink,
                  size: 60,
                ),
              ),
              const SizedBox(height: 24),

              // Título do erro
              const Text(
                'CLIENTE OBRIGATÓRIO',
                style: TextStyle(
                  color: Colors.pink,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),

              // Mensagem explicativa
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    const Row(
                      children: [
                        Icon(
                          Icons.calendar_month,
                          color: Colors.pink,
                          size: 28,
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Para lançar venda em Crediário, é necessário selecionar um cliente.',
                            style: TextStyle(color: Colors.white, fontSize: 15),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: Colors.orange.withOpacity(0.3),
                        ),
                      ),
                      child: const Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            color: Colors.orange,
                            size: 20,
                          ),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Selecione um cliente antes de escolher esta forma de pagamento.',
                              style: TextStyle(
                                color: Colors.orange,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.check),
              label: const Text(
                'ENTENDI',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.pink,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Mostra mensagem de erro centralizada quando tenta usar fiado sem cliente
  void _mostrarErroSemClienteFiado() {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: Colors.red.withOpacity(0.5), width: 2),
        ),
        content: Container(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Ícone de erro grande
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.15),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.red.withOpacity(0.4),
                    width: 3,
                  ),
                ),
                child: const Icon(
                  Icons.person_off,
                  color: Colors.red,
                  size: 60,
                ),
              ),
              const SizedBox(height: 24),

              // Título do erro
              const Text(
                'CLIENTE OBRIGATÓRIO',
                style: TextStyle(
                  color: Colors.red,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),

              // Mensagem explicativa
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.handshake, color: Colors.red, size: 28),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Para lançar venda Fiado, é necessário selecionar um cliente.',
                            style: TextStyle(color: Colors.white, fontSize: 15),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: Colors.orange.withOpacity(0.3),
                        ),
                      ),
                      child: const Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            color: Colors.orange,
                            size: 20,
                          ),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Selecione um cliente antes de escolher esta forma de pagamento.',
                              style: TextStyle(
                                color: Colors.orange,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.check),
              label: const Text(
                'ENTENDI',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCredito(String label, String valor, Color cor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.white.withOpacity(0.6))),
          Text(
            valor,
            style: TextStyle(color: cor, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  void _mostrarDialogPagamento(
    TipoPagamento tipo,
    double valorSugerido, {
    PagamentoPedido? pagamentoExistente,
    double descontoCalc = 0.0,
    double acrescimoCalc = 0.0,
  }) {
    final valorFocusNode = FocusNode();
    final valorController = TextEditingController(
      text: valorSugerido.toStringAsFixed(2),
    );
    final valorRecebidoController = TextEditingController();
    final observacaoController = TextEditingController(
      text: pagamentoExistente?.observacao ?? '',
    );

    int parcelas = 1;
    bool parcelar = false;
    DateTime primeiroVencimento = DateTime.now().add(const Duration(days: 30));
    int intervaloVencimento = 30;
    bool isDinheiro = tipo == TipoPagamento.dinheiro;
    bool isFiado = tipo == TipoPagamento.fiado;
    DateTime dataVencimentoFiado = DateTime.now().add(const Duration(days: 7));
    double troco = 0.0;

    final suportaParcelamento = [
      TipoPagamento.boleto,
      TipoPagamento.crediario,
    ].contains(tipo);

    final List<int> valoresRapidos = [10, 20, 50, 100, 200];
    int quickValueIndex = -1; // -1: outros campos, 0-4: valores rápidos

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          void calcularTroco() {
            final valorPagar =
                double.tryParse(valorController.text.replaceAll(',', '.')) ?? 0;
            final valorRecebido =
                double.tryParse(
                  valorRecebidoController.text.replaceAll(',', '.'),
                ) ??
                0;
            setDialogState(() {
              troco = valorRecebido - valorPagar;
              if (troco < 0) troco = 0;
            });
          }

          void concluir() {
            final valorOriginal =
                double.tryParse(
                  valorController.text.replaceAll(',', '.'),
                ) ??
                0;
            if (valorOriginal <= 0) return;

            final String? obs = observacaoController.text.isNotEmpty
                ? observacaoController.text
                : null;
            
            double valorALancar = valorOriginal;
            double? valorRecebidoFinal;
            double? trocoFinal;

            // Lógica Inteligente de Pagamento e Troco
            if (isDinheiro) {
              // Se o valor lançado for maior que o sugerido, calcula o troco automaticamente
              if (valorOriginal > valorSugerido) {
                valorALancar = valorSugerido < 0 ? 0 : valorSugerido;
                valorRecebidoFinal = valorOriginal;
                trocoFinal = valorOriginal - valorALancar;
              } else {
                // Caso contrário, usa os campos específicos de troco se preenchidos
                final vr = double.tryParse(valorRecebidoController.text.replaceAll(',', '.'));
                if (vr != null && vr > valorOriginal) {
                   valorRecebidoFinal = vr;
                   trocoFinal = vr - valorOriginal;
                }
              }
            } else {
              // Para outras formas, o valor lançado não pode exceder o restante da venda
              if (valorOriginal > valorSugerido) {
                valorALancar = valorSugerido < 0 ? 0 : valorSugerido;
              }
            }

            // Impede lançamentos sem valor real, a menos que seja um ajuste (valor ALancar == 0)
            if (valorALancar <= 0) {
                Navigator.pop(context);
                return;
            };

            // Update auto discount/acrescimo
            _descontoAutomatico += descontoCalc;
            _acrescimoAutomatico += acrescimoCalc;

            var novaLista = List<PagamentoPedido>.from(_pagamentos);
            if (widget.pagamentosIniciais.isNotEmpty &&
                tipo != TipoPagamento.outro) {
              novaLista.removeWhere(
                (p) => p.tipo == TipoPagamento.outro && !p.recebido,
              );
            }

            if (parcelar && parcelas > 1) {
              final parcelamentoId = DateTime.now().millisecondsSinceEpoch
                  .toString();
              final valorCadaParcela = valorALancar / parcelas;

              for (int i = 0; i < parcelas; i++) {
                final dataVenc = primeiroVencimento.add(
                  Duration(days: intervaloVencimento * i),
                );
                novaLista.add(
                  PagamentoPedido(
                    id: '${parcelamentoId}_$i',
                    tipo: tipo,
                    valor: valorCadaParcela,
                    parcelas: parcelas,
                    numeroParcela: i + 1,
                    parcelamentoId: parcelamentoId,
                    dataVencimento: dataVenc,
                    recebido: false,
                    observacao: i == 0 ? obs : null,
                  ),
                );
              }
            } else {
              final isRecebido =
                  tipo == TipoPagamento.dinheiro ||
                  tipo == TipoPagamento.pix ||
                  tipo == TipoPagamento.cartaoCredito ||
                  tipo == TipoPagamento.cartaoDebito;

              DateTime? dataVenc;
              if (isFiado) {
                dataVenc = dataVencimentoFiado;
              } else if (!isRecebido) {
                dataVenc = primeiroVencimento;
              }

              novaLista.add(
                PagamentoPedido(
                  id: DateTime.now().millisecondsSinceEpoch.toString(),
                  tipo: tipo,
                  valor: valorALancar,
                  recebido: isRecebido,
                  dataRecebimento: isRecebido ? DateTime.now() : null,
                  dataVencimento: dataVenc,
                  observacao: obs,
                  valorRecebido: valorRecebidoFinal,
                  troco: trocoFinal,
                ),
              );
            }

            setState(() => _pagamentos = novaLista);
            Navigator.pop(context);
            
            // SE O PAGAMENTO JÁ COMPLETOU O TOTAL, FINALIZAR AUTOMATICAMENTE (VAPT-VUPT)
            if (_pagamentoCompleto && !isFiado && !suportaParcelamento) {
               widget.onConfirmar(novaLista, 0.0, 0.0);
            }
          }

          double valorTotal =
              double.tryParse(valorController.text.replaceAll(',', '.')) ?? 0;
          double valorParcela = parcelas > 0
              ? valorTotal / parcelas
              : valorTotal;

          return Focus(
            autofocus: true,
            onKeyEvent: (node, event) {
              if (event is! KeyDownEvent) return KeyEventResult.ignored;
              final key = event.logicalKey;

              if (key == LogicalKeyboardKey.enter) {
                if (quickValueIndex >= 0) {
                   setDialogState(() {
                      valorRecebidoController.text = valoresRapidos[quickValueIndex].toStringAsFixed(2);
                      calcularTroco();
                      quickValueIndex = -1; // Retorna para o fluxo normal ou confirma
                   });
                   // Opcional: confirmar direto se quiser
                   concluir();
                   return KeyEventResult.handled;
                }
                concluir();
                return KeyEventResult.handled;
              }

              if (isDinheiro) {
                if (key == LogicalKeyboardKey.arrowDown) {
                   if (quickValueIndex == -1) {
                      setDialogState(() => quickValueIndex = 0);
                   }
                   return KeyEventResult.handled;
                }
                if (key == LogicalKeyboardKey.arrowUp) {
                   if (quickValueIndex >= 0) {
                      setDialogState(() => quickValueIndex = -1);
                   }
                   return KeyEventResult.handled;
                }
                if (key == LogicalKeyboardKey.arrowRight && quickValueIndex >= 0) {
                   if (quickValueIndex < valoresRapidos.length - 1) {
                      setDialogState(() => quickValueIndex++);
                   }
                   return KeyEventResult.handled;
                }
                if (key == LogicalKeyboardKey.arrowLeft && quickValueIndex >= 0) {
                   if (quickValueIndex > 0) {
                      setDialogState(() => quickValueIndex--);
                   }
                   return KeyEventResult.handled;
                }
              }

              // Seta direita: preenche o campo valor com o valor sugerido e foca nele
              if (key == LogicalKeyboardKey.arrowRight) {
                setDialogState(() {
                  valorController.text = valorSugerido.toStringAsFixed(2);
                  valorController.selection = TextSelection.fromPosition(
                    TextPosition(offset: valorController.text.length),
                  );
                  if (isDinheiro) calcularTroco();
                });
                valorFocusNode.requestFocus();
                return KeyEventResult.handled;
              }


              return KeyEventResult.ignored;
            },
            child: AlertDialog(
              backgroundColor: const Color(0xFF1E1E2E),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _getCorTipo(tipo).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      _getIconeTipo(tipo),
                      color: _getCorTipo(tipo),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      tipo.nome,
                      style: const TextStyle(color: Colors.white, fontSize: 18),
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Valor',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: valorController,
                      focusNode: valorFocusNode,
                      autofocus: false,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      onChanged: (_) {
                        if (isDinheiro) calcularTroco();
                        setDialogState(() {});
                      },
                      decoration: InputDecoration(
                        prefixText: 'R\$ ',
                        prefixStyle: const TextStyle(
                          color: Colors.greenAccent,
                          fontSize: 20,
                        ),
                        filled: true,
                        fillColor: Colors.black26,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),

                    if (isDinheiro) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Cliente entregou:',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 6),
                            TextField(
                              controller: valorRecebidoController,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                              keyboardType: const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                              onChanged: (_) => calcularTroco(),
                              decoration: InputDecoration(
                                prefixText: 'R\$ ',
                                prefixStyle: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 18,
                                ),
                                hintText: '0,00',
                                hintStyle: TextStyle(
                                  color: Colors.white.withOpacity(0.3),
                                ),
                                filled: true,
                                fillColor: Colors.black.withOpacity(0.3),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide.none,
                                ),
                                focusedBorder: quickValueIndex == -1 ? null : OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: List.generate(valoresRapidos.length, (index) {
                                final valor = valoresRapidos[index];
                                final isSelected = index == quickValueIndex;
                                return GestureDetector(
                                  onTap: () {
                                    setDialogState(() {
                                      quickValueIndex = index;
                                      valorRecebidoController.text = valor.toStringAsFixed(2);
                                      calcularTroco();
                                    });
                                  },
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 150),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isSelected 
                                          ? Colors.greenAccent
                                          : Colors.white.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(8),
                                      boxShadow: isSelected ? [
                                        BoxShadow(
                                          color: Colors.greenAccent.withOpacity(0.3),
                                          blurRadius: 8,
                                        )
                                      ] : null,
                                    ),
                                    child: Text(
                                      'R\$ $valor',
                                      style: TextStyle(
                                        color: isSelected ? Colors.black : Colors.white70,
                                        fontSize: 12,
                                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                      ),
                                    ),
                                  ),
                                );
                              }),
                            ),
                            if (troco > 0) ...[
                              const SizedBox(height: 10),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.amber.shade700,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Column(
                                  children: [
                                    const Text(
                                      'TROCO',
                                      style: TextStyle(
                                        color: Colors.black54,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Text(
                                      'R\$ ${troco.toStringAsFixed(2)}',
                                      style: const TextStyle(
                                        color: Colors.black,
                                        fontSize: 22,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],

                    if (suportaParcelamento) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.purple.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(
                                  Icons.calendar_month,
                                  color: Colors.purpleAccent,
                                  size: 18,
                                ),
                                const SizedBox(width: 6),
                                const Text(
                                  'Parcelamento',
                                  style: TextStyle(
                                    color: Colors.purpleAccent,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const Spacer(),
                                Switch(
                                  value: parcelar,
                                  onChanged: (value) => setDialogState(() {
                                    parcelar = value;
                                    if (!parcelar) parcelas = 1;
                                  }),
                                  activeThumbColor: Colors.purpleAccent,
                                ),
                              ],
                            ),
                            if (parcelar) ...[
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  GestureDetector(
                                    onTap: () => setDialogState(() {
                                      if (parcelas > 2) parcelas--;
                                    }),
                                    child: Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: Colors.red.withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Icon(
                                        Icons.remove,
                                        color: Colors.redAccent,
                                        size: 18,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      '${parcelas}x de ${_formatoMoeda.format(valorParcela)}',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  GestureDetector(
                                    onTap: () => setDialogState(() {
                                      if (parcelas < 24) parcelas++;
                                    }),
                                    child: Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: Colors.green.withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Icon(
                                        Icons.add,
                                        color: Colors.greenAccent,
                                        size: 18,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              GestureDetector(
                                onTap: () async {
                                  final data = await showDatePicker(
                                    context: context,
                                    initialDate: primeiroVencimento,
                                    firstDate: DateTime.now(),
                                    lastDate: DateTime.now().add(
                                      const Duration(days: 365),
                                    ),
                                    builder: (context, child) => Theme(
                                      data: ThemeData.dark().copyWith(
                                        colorScheme: const ColorScheme.dark(
                                          primary: Colors.purple,
                                          surface: Color(0xFF1E1E2E),
                                        ),
                                      ),
                                      child: child!,
                                    ),
                                  );
                                  if (data != null) {
                                    setDialogState(
                                      () => primeiroVencimento = data,
                                    );
                                  }
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.calendar_today,
                                        color: Colors.white54,
                                        size: 16,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        '1º venc: ${_formatoData.format(primeiroVencimento)}',
                                        style: const TextStyle(
                                          color: Colors.white70,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],

                    if (isFiado) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.red.withOpacity(0.3)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(
                                  Icons.event,
                                  color: Colors.red,
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                const Text(
                                  'Data de Pagamento',
                                  style: TextStyle(
                                    color: Colors.red,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const Spacer(),
                                if (widget.cliente != null) ...[
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.green.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      'Disp: ${_formatoMoeda.format(widget.cliente!.creditoDisponivel)}',
                                      style: const TextStyle(
                                        color: Colors.greenAccent,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 12),
                            GestureDetector(
                              onTap: () async {
                                final data = await showDatePicker(
                                  context: context,
                                  initialDate: dataVencimentoFiado,
                                  firstDate: DateTime.now(),
                                  lastDate: DateTime.now().add(
                                    const Duration(days: 365),
                                  ),
                                  builder: (context, child) => Theme(
                                    data: ThemeData.dark().copyWith(
                                      colorScheme: const ColorScheme.dark(
                                        primary: Colors.red,
                                        surface: Color(0xFF1E1E2E),
                                      ),
                                    ),
                                    child: child!,
                                  ),
                                );
                                if (data != null) {
                                  setDialogState(
                                    () => dataVencimentoFiado = data,
                                  );
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black26,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.calendar_today,
                                      color: Colors.white54,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        _formatoData.format(dataVencimentoFiado),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ),
                                    const Icon(
                                      Icons.edit,
                                      color: Colors.white38,
                                      size: 18,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'O cliente deverá pagar até esta data',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.5),
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 16),
                    TextField(
                      controller: observacaoController,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      maxLines: 2,
                      decoration: InputDecoration(
                        hintText: 'Observação (opcional)',
                        hintStyle: const TextStyle(color: Colors.white30),
                        filled: true,
                        fillColor: Colors.black26,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    'Cancelar',
                    style: TextStyle(color: Colors.white54),
                  ),
                ),
                ElevatedButton(
                  onPressed: concluir,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _getCorTipo(tipo),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Text(
                    parcelar && parcelas > 1
                        ? 'Criar $parcelas Parcelas'
                        : 'Adicionar',
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildPainelTotalCompacto() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0D15),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.greenAccent.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'TOTAL A PAGAR',
                style: TextStyle(
                  color: Colors.greenAccent.withOpacity(0.8),
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
              Text(
                _formatoMoeda.format(widget.totalCarrinho),
                style: const TextStyle(
                  color: Colors.greenAccent,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          if (widget.descontoTotal > 0)
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Text(
                  'DESCONTOS',
                  style: TextStyle(
                    color: Colors.redAccent,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  '- ${_formatoMoeda.format(widget.descontoTotal)}',
                  style: const TextStyle(
                    color: Colors.redAccent,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildPainelTotalFull() {
    final totalPago = _pagamentos.fold<double>(0, (sum, p) => sum + p.valor);
    final falta = widget.totalCarrinho - totalPago;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [const Color(0xFF0D0D15), const Color(0xFF161625)],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.greenAccent.withOpacity(0.2)),
          boxShadow: [
            BoxShadow(
              color: Colors.greenAccent.withOpacity(0.05),
              blurRadius: 20,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'SUBTOTAL',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.5),
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                      ),
                    ),
                    Text(
                      _formatoMoeda.format(widget.subtotal),
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                if (widget.descontoTotal > 0)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text(
                        'DESCONTOS',
                        style: TextStyle(
                          color: Colors.redAccent,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                      ),
                      Text(
                        '- ${_formatoMoeda.format(widget.descontoTotal)}',
                        style: const TextStyle(
                          color: Colors.redAccent,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            const Divider(color: Colors.white10, height: 16),
            Text(
              'TOTAL A PAGAR',
              style: TextStyle(
                color: Colors.greenAccent.withOpacity(0.8),
                fontSize: 14,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _formatoMoeda.format(widget.totalCarrinho),
              style: TextStyle(
                color: Colors.greenAccent.shade400,
                fontSize: 54,
                fontWeight: FontWeight.w900,
                letterSpacing: -1,
              ),
            ),
            if (falta > 0 && totalPago > 0) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: Colors.orangeAccent.withOpacity(0.3)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.info_outline, color: Colors.orangeAccent, size: 16),
                        const SizedBox(width: 8),
                        const Text(
                          'FALTA RECEBER:',
                          style: TextStyle(
                            color: Colors.orangeAccent,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      _formatoMoeda.format(falta),
                      style: const TextStyle(
                        color: Colors.orangeAccent,
                        fontWeight: FontWeight.w900,
                        fontSize: 22,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _removerPagamento(int index) {
    setState(() => _pagamentos.removeAt(index));
  }

  Color _getCorTipo(TipoPagamento tipo) {
    switch (tipo) {
      case TipoPagamento.dinheiro:
        return Colors.green;
      case TipoPagamento.pix:
        return Colors.teal;
      case TipoPagamento.cartaoCredito:
        return Colors.blue;
      case TipoPagamento.cartaoDebito:
        return Colors.indigo;
      case TipoPagamento.boleto:
        return Colors.orange;
      case TipoPagamento.crediario:
        return Colors.purple;
      case TipoPagamento.fiado:
        return Colors.red;
      case TipoPagamento.outro:
        return Colors.grey;
      case TipoPagamento.alimentacao:
        return Colors.teal;
      case TipoPagamento.transferencia:
        return Colors.blueAccent;
    }
  }

  IconData _getIconeTipo(TipoPagamento tipo) {
    switch (tipo) {
      case TipoPagamento.dinheiro:
        return Icons.money;
      case TipoPagamento.pix:
        return Icons.qr_code;
      case TipoPagamento.cartaoCredito:
        return Icons.credit_card;
      case TipoPagamento.cartaoDebito:
        return Icons.credit_card;
      case TipoPagamento.boleto:
        return Icons.receipt;
      case TipoPagamento.crediario:
        return Icons.calendar_today;
      case TipoPagamento.fiado:
        return Icons.handshake;
      case TipoPagamento.outro:
        return Icons.more_horiz;
      case TipoPagamento.alimentacao:
        return Icons.restaurant;
      case TipoPagamento.transferencia:
        return Icons.swap_horiz;
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final isSmallHeight = screenHeight < 750;

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyRepeatEvent) return KeyEventResult.ignored;
        if (event is! KeyDownEvent) return KeyEventResult.ignored;

        final key = event.logicalKey;
        
        // ESC e F9 tratados no handler do HardwareKeyboard para maior confiabilidade
        

        // Teclas 1 a 8 para formas de pagamento
        final types = TipoPagamento.values;
        if (key == LogicalKeyboardKey.digit1 || key == LogicalKeyboardKey.numpad1) {
          _adicionarPagamento(types[0]);
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.digit2 || key == LogicalKeyboardKey.numpad2) {
          _adicionarPagamento(types[1]);
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.digit3 || key == LogicalKeyboardKey.numpad3) {
          _adicionarPagamento(types[2]);
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.digit4 || key == LogicalKeyboardKey.numpad4) {
          _adicionarPagamento(types[3]);
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.digit5 || key == LogicalKeyboardKey.numpad5) {
          _adicionarPagamento(types[4]);
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.digit6 || key == LogicalKeyboardKey.numpad6) {
          _adicionarPagamento(types[5]);
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.digit7 || key == LogicalKeyboardKey.numpad7) {
          _adicionarPagamento(types[6]);
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.digit8 || key == LogicalKeyboardKey.numpad8) {
          _adicionarPagamento(types[7]);
          return KeyEventResult.handled;
        }

        // Navegar lista de pagamentos com ↑/↓
        if (key == LogicalKeyboardKey.arrowDown) {
          if (_pagamentos.isNotEmpty) {
            setState(() {
              _selectedPaymentIndex =
                  (_selectedPaymentIndex + 1).clamp(0, _pagamentos.length - 1);
            });
          }
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowUp) {
          if (_pagamentos.isNotEmpty) {
            setState(() {
              if (_selectedPaymentIndex <= 0) {
                _selectedPaymentIndex = -1; // volta ao estado sem seleção
              } else {
                _selectedPaymentIndex--;
              }
            });
          }
          return KeyEventResult.handled;
        }

        // DEL: remove o pagamento selecionado
        if (key == LogicalKeyboardKey.delete) {
          if (_selectedPaymentIndex >= 0 && _selectedPaymentIndex < _pagamentos.length) {
            _removerPagamento(_selectedPaymentIndex);
            setState(() {
              if (_pagamentos.isEmpty) {
                _selectedPaymentIndex = -1;
              } else {
                _selectedPaymentIndex =
                    _selectedPaymentIndex.clamp(0, _pagamentos.length - 1);
              }
            });
          }
          return KeyEventResult.handled;
        }

        // ENTER para finalizar se houver pagamentos E valor completo
        if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) {
          if (_pagamentos.isNotEmpty && _pagamentoCompleto) {
            widget.onConfirmar(_pagamentos, _descontoAutomatico, _acrescimoAutomatico);
          } else if (_pagamentos.isNotEmpty && !_pagamentoCompleto) {
            // Avisar que falta valor
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    const Icon(Icons.warning_amber, color: Colors.white),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Faltam ${_formatoMoeda.format(_valorRestante)} para cobrir o total da venda',
                      ),
                    ),
                  ],
                ),
                backgroundColor: Colors.orange.shade800,
                behavior: SnackBarBehavior.floating,
                duration: const Duration(seconds: 3),
              ),
            );
          }
          return KeyEventResult.handled;
        }

        // ESC para fechar o resumo
        if (key == LogicalKeyboardKey.escape) {
          Navigator.pop(context);
          return KeyEventResult.handled;
        }

        return KeyEventResult.ignored;
      },
      child: Container(
        height: screenHeight * 0.9,
        decoration: const BoxDecoration(
          color: Color(0xFF1E1E2E),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Título Fixo no topo
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.greenAccent.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.payment,
                    color: Colors.greenAccent,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Resumo da Venda',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),

          if (!isSmallHeight) _buildPainelTotalFull(),

          // LISTA FRÁGIL: Parte que pode rolar se o conteúdo crescer demais
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  // Painel de Total Vibrante - Movido para dentro do scroll se a tela for pequena
                  if (isSmallHeight) ...[
                    _buildPainelTotalCompacto(),
                    const SizedBox(height: 16),
                  ],

                  // Formas de pagamento
                  const Text(
                    'Adicionar Pagamento',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    
                    children: TipoPagamento.values.where((t) {
                      final dataService = Provider.of<DataService>(context, listen: false);
                      final pagamentosConfig = dataService.empresaAtual?.configuracoes?['pagamentos'] as Map?;
                      return (pagamentosConfig?[t.name]?['ativo'] as bool?) ?? true;
                    }).toList().asMap().entries.map((entry) {

                      final index = entry.key;
                      final tipo = entry.value;
                      final shortcut = index + 1;

                      return GestureDetector(
                        onTap: () => _adicionarPagamento(tipo),
                        child: Tooltip(
                          message: 'Pressione $shortcut para selecionar',
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: _getCorTipo(tipo).withOpacity(0.15),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: _getCorTipo(tipo).withOpacity(0.3),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Atalho numérico
                                if (shortcut <= 8)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                      vertical: 1,
                                    ),
                                    margin: const EdgeInsets.only(right: 6),
                                    decoration: BoxDecoration(
                                      color: _getCorTipo(tipo).withOpacity(0.3),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      '$shortcut',
                                      style: TextStyle(
                                        color: _getCorTipo(tipo),
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                Icon(
                                  _getIconeTipo(tipo),
                                  color: _getCorTipo(tipo),
                                  size: 14,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  tipo.nome,
                                  style: TextStyle(
                                    color: _getCorTipo(tipo),
                                    fontWeight: FontWeight.w500,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),

                  const SizedBox(height: 10),

                  // Identificação do Consumidor para NFC-e
                  if (widget.cliente == null) ...[
                    const Divider(color: Colors.white10, height: 32),
                    Row(
                      children: [
                        Icon(
                          Icons.badge_outlined,
                          color: Colors.blueAccent.withOpacity(0.8),
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'IDENTIFICAÇÃO PARA NFC-E (OPCIONAL)',
                          style: TextStyle(
                            color: Colors.white54,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: _cpfController,
                            style: const TextStyle(color: Colors.white, fontSize: 13),
                            decoration: InputDecoration(
                              hintText: 'CPF/CNPJ na Nota',
                              hintStyle: TextStyle(
                                color: Colors.white.withOpacity(0.2),
                              ),
                              prefixIcon: Icon(
                                Icons.badge,
                                size: 16,
                                color: Colors.white.withOpacity(0.3),
                              ),
                              filled: true,
                              fillColor: Colors.black26,
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 12,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide.none,
                              ),
                            ),
                            keyboardType: TextInputType.number,
                            onChanged: (val) => widget.onDadosConsumidorChanged(
                              val,
                              _nomeController.text,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 3,
                          child: TextField(
                            controller: _nomeController,
                            style: const TextStyle(color: Colors.white, fontSize: 13),
                            decoration: InputDecoration(
                              hintText: 'Nome do Consumidor',
                              hintStyle: TextStyle(
                                color: Colors.white.withOpacity(0.2),
                              ),
                              prefixIcon: Icon(
                                Icons.person_outline,
                                size: 16,
                                color: Colors.white.withOpacity(0.3),
                              ),
                              filled: true,
                              fillColor: Colors.black26,
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 12,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide.none,
                              ),
                            ),
                            onChanged: (val) => widget.onDadosConsumidorChanged(
                              _cpfController.text,
                              val,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Pressione F9 ou clique em Finalizar para concluir com estes dados.',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.3),
                        fontSize: 9,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],

                  const SizedBox(height: 20),

                  if (_pagamentos.isEmpty)
                    Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.payment_outlined,
                            size: 48,
                            color: Colors.white.withOpacity(0.2),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Nenhum pagamento adicionado',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.4),
                            ),
                          ),
                        ],
                      ),
                    )
                  else ...[
                    // Resumo de Troco se houver
                    if (_totalTroco > 0)
                      Container(
                        margin: const EdgeInsets.only(bottom: 20),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.amber.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.amber.withOpacity(0.3)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'TROCO TOTAL:',
                              style: TextStyle(
                                color: Colors.amber,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            Text(
                              _formatoMoeda.format(_totalTroco),
                              style: const TextStyle(
                                color: Colors.amber,
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                            ),
                          ],
                        ),
                      ),
                    // Lista de pagamentos já adicionados
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _pagamentos.length,
                      itemBuilder: (context, index) {
                        final pagamento = _pagamentos[index];
                        final isSelected = index == _selectedPaymentIndex;
                        return GestureDetector(
                          onTap: () => setState(() => _selectedPaymentIndex = index),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? Colors.orange.withOpacity(0.12)
                                  : Colors.white.withOpacity(0.05),
                              borderRadius: BorderRadius.circular(12),
                              border: isSelected
                                  ? Border.all(color: Colors.orange, width: 1.5)
                                  : null,
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: _getCorTipo(
                                      pagamento.tipo,
                                    ).withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(
                                    _getIconeTipo(pagamento.tipo),
                                    color: _getCorTipo(pagamento.tipo),
                                    size: 18,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        pagamento.tipo.nome,
                                        style: TextStyle(
                                          color: isSelected ? Colors.orange : Colors.white,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      if (pagamento.isParcela)
                                        Text(
                                          'Parcela ${pagamento.numeroParcela}/${pagamento.parcelas}',
                                          style: TextStyle(
                                            color: Colors.white.withOpacity(0.5),
                                            fontSize: 11,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                Text(
                                  _formatoMoeda.format(pagamento.valor),
                                  style: TextStyle(
                                    color: isSelected ? Colors.orange : _getCorTipo(pagamento.tipo),
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                GestureDetector(
                                  onTap: () => _removerPagamento(index),
                                  child: Icon(
                                    Icons.close,
                                    color: isSelected
                                        ? Colors.orange.withOpacity(0.8)
                                        : Colors.white.withOpacity(0.3),
                                    size: 18,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                ],
              ],
            ),
          ),
        ),

          // Botões de ação
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                // Botão Salvar
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => widget.onSalvarPendente(_pagamentos),
                    icon: const Icon(Icons.save_outlined, size: 20),
                    label: const Text(
                      'Salvar (Receber Depois)',
                      style: TextStyle(fontSize: 14),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.orange,
                      side: BorderSide(color: Colors.orange.withOpacity(0.5)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                // Botão Finalizar
                 SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: (_pagamentos.isEmpty || !_pagamentoCompleto || _estaConfirmando)
                        ? null
                        : () {
                            setState(() => _estaConfirmando = true);
                            widget.onConfirmar(_pagamentos, _descontoAutomatico, _acrescimoAutomatico);
                          },
                    icon: _estaConfirmando 
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Icon(Icons.check_circle, size: 24),
                    label: Text(
                      _estaConfirmando 
                          ? 'PROCESSANDO...' 
                          : (_pagamentoCompleto
                              ? 'FINALIZAR VENDA'
                              : 'FALTA ${_formatoMoeda.format(_valorRestante)}'),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _estaConfirmando
                          ? Colors.grey
                          : (_pagamentoCompleto ? Colors.green : Colors.red.shade800),
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.grey.withOpacity(0.3),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
}

/// Popup animado de sucesso com dinheiro caindo - centralizado na tela
class PopupSucessoVenda extends StatefulWidget {
  final double valor;
  final String titulo;
  final String subtitulo;
  final double? troco;
  final IconData? icone;
  final Color? corBase;
  final String? infoExtra;
  final VoidCallback? onDismiss;
  final VoidCallback? onEmitirNFCe;
  final VoidCallback? onWhatsApp;
  final VoidCallback? onImprimir; // Novo callback para impressão

  const PopupSucessoVenda({
    super.key,
    required this.valor,
    required this.titulo,
    required this.subtitulo,
    this.troco,
    this.icone,
    this.corBase,
    this.infoExtra,
    this.onDismiss,
    this.onEmitirNFCe,
    this.onWhatsApp,
    this.onImprimir,
  });

  /// Mostra o popup de sucesso
  static void mostrar(
    BuildContext context, {
    required double valor,
    required String titulo,
    required String subtitulo,
    double? troco,
    IconData? icone,
    Color? corBase,
    String? infoExtra,
    VoidCallback? onDismiss,
    VoidCallback? onEmitirNFCe,
    VoidCallback? onWhatsApp,
    VoidCallback? onImprimir,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black54,
      builder: (context) => PopupSucessoVenda(
        valor: valor,
        titulo: titulo,
        subtitulo: subtitulo,
        troco: troco,
        icone: icone,
        corBase: corBase,
        infoExtra: infoExtra,
        onDismiss: onDismiss,
        onEmitirNFCe: onEmitirNFCe,
        onWhatsApp: onWhatsApp,
        onImprimir: onImprimir,
      ),
    );
  }

  @override
  State<PopupSucessoVenda> createState() => _PopupSucessoVendaState();
}

class _PopupSucessoVendaState extends State<PopupSucessoVenda>
    with TickerProviderStateMixin {
  late AnimationController _scaleController;
  late Animation<double> _scaleAnimation;
  final math.Random _random = math.Random();
  
  // Foco para botões
  final FocusNode _fecharNode = FocusNode();
  final FocusNode _nfceNode = FocusNode();
  final FocusNode _whatsappNode = FocusNode();
  final FocusNode _imprimirNode = FocusNode();

  @override
  void initState() {
    super.initState();

    // Animação de escala do popup
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 300),
      reverseDuration: const Duration(milliseconds: 100),
      vsync: this,
    );
    _scaleAnimation = CurvedAnimation(
      parent: _scaleController,
      curve: Curves.elasticOut,
    );

    _scaleController.forward();

    // Auto fechar após 2.5 segundos (apenas se não houver botão de emitir NFC-e)
    if (widget.onEmitirNFCe == null) {
      Future.delayed(const Duration(milliseconds: 2500), () {
        if (mounted) {
          _fechar();
        }
      });
    }

    // Focar no botão fechar após o popup abrir
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _fecharNode.requestFocus();
      }
    });
    
    // Adicionar listeners para reconstruir quando o foco mudar (para atualizar estilos)
    _fecharNode.addListener(_onFocusChange);
    _nfceNode.addListener(_onFocusChange);
    _whatsappNode.addListener(_onFocusChange);
    _imprimirNode.addListener(_onFocusChange);
  }
  
  void _onFocusChange() {
    if (mounted) setState(() {});
  }

  void _fechar() {
    _scaleController.reverse().then((_) {
      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
        widget.onDismiss?.call();
      }
    });
  }

  void _emitir() {
    if (widget.onEmitirNFCe != null) {
      if (mounted) {
        Navigator.pop(context);
        widget.onEmitirNFCe?.call();
      }
    }
  }

  void _whatsApp() {
    if (widget.onWhatsApp != null) {
      if (mounted) {
        Navigator.pop(context);
        widget.onWhatsApp?.call();
      }
    }
  }

  void _imprimir() {
    if (widget.onImprimir != null) {
      if (mounted) {
        widget.onImprimir?.call();
      }
    }
  }

  @override
  void dispose() {
    _scaleController.dispose();
    _fecharNode.dispose();
    _nfceNode.dispose();
    _whatsappNode.dispose();
    _imprimirNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

    return KeyboardListener(
      focusNode: FocusNode(), // Capturar teclas globalmente no popup
      onKeyEvent: (event) {
        if (event is KeyDownEvent) {
          // Lista de botões disponíveis para navegação
          final listNodes = <FocusNode>[];
          if (widget.onEmitirNFCe != null) listNodes.add(_nfceNode);
          if (widget.onWhatsApp != null) listNodes.add(_whatsappNode);
          if (widget.onImprimir != null) listNodes.add(_imprimirNode);
          listNodes.add(_fecharNode);

          if (event.logicalKey == LogicalKeyboardKey.enter || 
              event.logicalKey == LogicalKeyboardKey.numpadEnter) {
            // Enter aciona o botão focado
            if (_nfceNode.hasFocus) {
              _emitir();
            } else if (_whatsappNode.hasFocus) {
              _whatsApp();
            } else if (_imprimirNode.hasFocus) {
              _imprimir();
            } else {
              _fechar();
            }
          } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            // Mover foco para a esquerda
            int index = listNodes.indexWhere((n) => n.hasFocus);
            if (index > 0) {
              listNodes[index - 1].requestFocus();
            } else if (index == 0) {
              listNodes.last.requestFocus();
            }
          } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
            // Mover foco para a direita
            int index = listNodes.indexWhere((n) => n.hasFocus);
            if (index != -1 && index < listNodes.length - 1) {
              listNodes[index + 1].requestFocus();
            } else {
              listNodes.first.requestFocus();
            }
          } else if (event.logicalKey == LogicalKeyboardKey.escape) {
            _fechar();
          }
        }
      },
      child: Material(
        color: Colors.transparent,
        child: Stack(
          children: [
          // O fundo animado foi removido para evitar travamentos em dispositivos lentos

          // Popup central
          Center(
            child: ScaleTransition(
              scale: _scaleAnimation,
              child: Container(
                margin: const EdgeInsets.all(32),
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      (widget.corBase ?? Colors.green).withBlue(50).withRed(20),
                      widget.corBase ?? Colors.green,
                      (widget.corBase ?? Colors.green).withOpacity(0.8),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: (widget.corBase ?? Colors.green).withOpacity(0.5),
                      blurRadius: 40,
                      spreadRadius: 10,
                    ),
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Ícone animado
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0.0, end: 1.0),
                      duration: const Duration(milliseconds: 600),
                      curve: Curves.elasticOut,
                      builder: (context, value, child) {
                        return Transform.scale(
                          scale: value,
                          child: Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.white.withOpacity(0.3),
                                  blurRadius: 20,
                                  spreadRadius: 5,
                                ),
                              ],
                            ),
                            child: Icon(
                              widget.icone ?? Icons.check_circle,
                              size: 70,
                              color: Colors.white,
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 24),

                    // Título
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0.0, end: 1.0),
                      duration: const Duration(milliseconds: 400),
                      curve: Curves.easeOut,
                      builder: (context, value, child) {
                        return Opacity(
                          opacity: value,
                          child: Transform.translate(
                            offset: Offset(0, 20 * (1 - value)),
                            child: child,
                          ),
                        );
                      },
                      child: Text(
                        widget.titulo,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Subtítulo (número da venda)
                    Text(
                      widget.subtitulo,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.8),
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Valor com animação
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0.0, end: 1.0),
                      duration: const Duration(milliseconds: 600),
                      curve: Curves.elasticOut,
                      builder: (context, value, child) {
                        return Transform.scale(
                          scale: 0.5 + (value * 0.5),
                          child: Opacity(opacity: value.clamp(0.0, 1.0), child: child),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 28,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.3),
                            width: 2,
                          ),
                        ),
                        child: Column(
                          children: [
                            if (widget.infoExtra != null) ...[
                              Text(
                                widget.infoExtra!,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                            ],
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.attach_money,
                                  color: Colors.white,
                                  size: 32,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  formatoMoeda.format(widget.valor),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 32,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            if (widget.troco != null && widget.troco! > 0) ...[
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black26,
                                      blurRadius: 10,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  children: [
                                    const Text(
                                      'TROCO DO CLIENTE',
                                      style: TextStyle(
                                        color: Colors.black54,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 10,
                                        letterSpacing: 1,
                                      ),
                                    ),
                                    Text(
                                      formatoMoeda.format(widget.troco),
                                      style: TextStyle(
                                        color: widget.corBase ?? Colors.green.shade700,
                                        fontWeight: FontWeight.w900,
                                        fontSize: 24,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Botões de ação
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (widget.onEmitirNFCe != null)
                          ElevatedButton.icon(
                            focusNode: _nfceNode,
                            onPressed: _emitir,
                            icon: const Icon(Icons.receipt, size: 20),
                            label: const Text(
                              'Emitir NFC-e',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: Colors.green.shade800,
                              elevation: _nfceNode.hasFocus ? 8 : 2,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 16,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                                side: _nfceNode.hasFocus 
                                  ? BorderSide(color: Colors.green.shade900, width: 2)
                                  : BorderSide.none,
                              ),
                            ),
                          ),
                        if (widget.onEmitirNFCe != null)
                          const SizedBox(width: 16),
                        
                        if (widget.onWhatsApp != null)
                          ElevatedButton.icon(
                            focusNode: _whatsappNode,
                            onPressed: _whatsApp,
                            icon: const Icon(Icons.chat_bubble_outline, size: 20),
                            label: const Text('WhatsApp'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF25D366),
                              foregroundColor: Colors.white,
                              elevation: _whatsappNode.hasFocus ? 8 : 2,
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                                side: _whatsappNode.hasFocus 
                                  ? const BorderSide(color: Colors.white, width: 2)
                                  : BorderSide.none,
                              ),
                            ),
                          ),

                        if (widget.onWhatsApp != null)
                          const SizedBox(width: 16),
                        
                        // Botão Imprimir Cupom Simples
                        if (widget.onImprimir != null)
                          ElevatedButton.icon(
                            focusNode: _imprimirNode,
                            onPressed: _imprimir,
                            icon: const Icon(Icons.print_rounded, size: 20),
                            label: const Text(
                              'Imprimir',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white.withOpacity(0.9),
                              foregroundColor: Colors.blue.shade800,
                              elevation: _imprimirNode.hasFocus ? 8 : 2,
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                                side: _imprimirNode.hasFocus 
                                  ? BorderSide(color: Colors.blue.shade900, width: 2)
                                  : BorderSide.none,
                              ),
                            ),
                          ),

                        if (widget.onImprimir != null)
                          const SizedBox(width: 16),
                        
                        // Botão Fechar - Com foco
                        ElevatedButton(
                          focusNode: _fecharNode,
                          onPressed: _fechar,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white.withOpacity(0.25),
                            foregroundColor: Colors.white,
                            elevation: _fecharNode.hasFocus ? 8 : 0,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 16,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: _fecharNode.hasFocus 
                                ? const BorderSide(color: Colors.white, width: 2)
                                : BorderSide(color: Colors.white.withOpacity(0.3), width: 1),
                            ),
                          ),
                          child: const Text(
                            'Fechar',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    ),
   );
  }
}

/// Dados para animação de cada nota de dinheiro
class _DinheiroAnimado {
  final double x;
  final double delay;
  final double speed;
  final double rotation;
  final double rotationSpeed;
  final double size;

  _DinheiroAnimado({
    required this.x,
    required this.delay,
    required this.speed,
    required this.rotation,
    required this.rotationSpeed,
    required this.size,
  });
}

/// Widget do logo "ê" dourado/amarelo brilhante para o topo do PDV
class _LogoDouradoBrilhante extends StatefulWidget {
  const _LogoDouradoBrilhante();

  @override
  State<_LogoDouradoBrilhante> createState() => _LogoDouradoBrilhanteState();
}

class _LogoDouradoBrilhanteState extends State<_LogoDouradoBrilhante>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _glowAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);

    _glowAnimation = Tween<double>(
      begin: 0.3,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _glowAnimation,
      builder: (context, child) {
        return Stack(
          alignment: Alignment.center,
          children: [
            // Brilho pulsante ao redor
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    Colors.amber.withOpacity(0.4 * _glowAnimation.value),
                    Colors.orange.withOpacity(0.2 * _glowAnimation.value),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
            // Sombra brilhante
            Text(
              'ê',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w900,
                color: Colors.amber.shade300,
                fontFamily: 'Roboto',
                shadows: [
                  Shadow(
                    color: Colors.amber.withOpacity(0.8 * _glowAnimation.value),
                    blurRadius: 20 * _glowAnimation.value,
                    offset: const Offset(0, 0),
                  ),
                  Shadow(
                    color: Colors.orange.withOpacity(
                      0.6 * _glowAnimation.value,
                    ),
                    blurRadius: 15 * _glowAnimation.value,
                    offset: const Offset(0, 0),
                  ),
                  Shadow(
                    color: Colors.yellow.withOpacity(
                      0.4 * _glowAnimation.value,
                    ),
                    blurRadius: 25 * _glowAnimation.value,
                    offset: const Offset(0, 0),
                  ),
                  const Shadow(
                    color: Colors.black87,
                    blurRadius: 4,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
            ),
            // Logo principal com gradiente dourado
            ShaderMask(
              shaderCallback: (bounds) => LinearGradient(
                colors: [
                  Colors.amber.shade400,
                  Colors.orange.shade400,
                  Colors.amber.shade600,
                ],
                stops: const [0.0, 0.5, 1.0],
              ).createShader(bounds),
              child: Text(
                'ê',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  fontFamily: 'Roboto',
                  letterSpacing: -1,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _DialogConferenciaItens extends StatefulWidget {
  final List<ItemCarrinho> carrinho;
  final Function(int) onRemoverItem;

  const _DialogConferenciaItens({
    required this.carrinho,
    required this.onRemoverItem,
  });

  @override
  State<_DialogConferenciaItens> createState() => _DialogConferenciaItensState();
}

class _DialogConferenciaItensState extends State<_DialogConferenciaItens> {
  /// Verifica se o produto do carrinho é vendido por embalagem (caixa, pacote, saco).
  /// Usa a forma armazenada no item (escolhida no PDV) e, como fallback,
  /// consulta o produto para compatibilidade com carrinhos antigos.
  bool _itemVendidoPorEmbalagem(ItemCarrinho item) {
    if (item.isServico) return false;
    if (item.unidadeVenda != null) {
      return item.unidadeVenda == 'caixa' ||
          item.unidadeVenda == 'pacote' ||
          item.unidadeVenda == 'saco';
    }
    final dataService = Provider.of<DataService>(context, listen: false);
    for (final p in dataService.produtos) {
      if (p.id == item.id) {
        return p.vendePorEmbalagem;
      }
    }
    return false;
  }

  /// Rótulo da unidade de venda do item (CAIXA/PACOTE/SACO/UNIDADE).
  /// Usa a forma armazenada no item quando disponível.
  String _unidadeVendaLabelItem(ItemCarrinho item) {
    if (item.isServico) return '';
    if (item.unidadeVenda != null && item.unidadeVenda!.isNotEmpty) {
      switch (item.unidadeVenda) {
        case 'caixa':
          return 'CAIXA';
        case 'pacote':
          return 'PACOTE';
        case 'saco':
          return 'SACO';
        default:
          return 'UNIDADE';
      }
    }
    final dataService = Provider.of<DataService>(context, listen: false);
    for (final p in dataService.produtos) {
      if (p.id == item.id) {
        return p.unidadeVendaLabel;
      }
    }
    return '';
  }

  int _selectedIndex = 0;
  final ScrollController _scrollController = ScrollController();
  final NumberFormat _formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

  double get _totalCarrinho => widget.carrinho.fold(0.0, (sum, item) => sum + item.subtotalSemDesconto);
  double get _totalItens => widget.carrinho.fold(0.0, (sum, item) => sum + item.quantidade);

  void _scrollToSelected() {
    if (!_scrollController.hasClients) return;
    
    const double itemHeight = 80.0;
    final double viewportHeight = 400.0; 
    final targetOffset = _selectedIndex * itemHeight;
    
    if (targetOffset < _scrollController.offset || 
        targetOffset > _scrollController.offset + viewportHeight - itemHeight) {
      _scrollController.animateTo(
        targetOffset.clamp(0, _scrollController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  void _removerItemAt(int index) {
    widget.onRemoverItem(index);
    setState(() {
      if (widget.carrinho.isEmpty) {
        Navigator.pop(context);
      } else if (_selectedIndex >= widget.carrinho.length) {
        _selectedIndex = widget.carrinho.length - 1;
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;

        if (key == LogicalKeyboardKey.arrowDown) {
          if (_selectedIndex < widget.carrinho.length - 1) {
            setState(() => _selectedIndex++);
            _scrollToSelected();
          }
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowUp) {
          if (_selectedIndex > 0) {
            setState(() => _selectedIndex--);
            _scrollToSelected();
          }
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.delete || key == LogicalKeyboardKey.backspace) {
          _removerItemAt(_selectedIndex);
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.escape) {
          Navigator.pop(context);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
        child: Container(
          width: 600,
          constraints: const BoxConstraints(maxHeight: 800),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF161625), Color(0xFF0D0D14)],
            ),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Colors.cyanAccent.withOpacity(0.3), width: 2),
            boxShadow: [
              BoxShadow(
                color: Colors.cyanAccent.withOpacity(0.1),
                blurRadius: 40,
                spreadRadius: 5,
              ),
              BoxShadow(
                color: Colors.black.withOpacity(0.5),
                blurRadius: 20,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.cyanAccent.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.fact_check_rounded, color: Colors.cyanAccent, size: 28),
                  ),
                  const SizedBox(width: 16),
                  const Text(
                    'CONFERÊNCIA DE VENDA',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Colors.white38),
                    hoverColor: Colors.white10,
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Flexible(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withOpacity(0.05)),
                  ),
                  child: ListView.separated(
                    controller: _scrollController,
                    shrinkWrap: true,
                    padding: const EdgeInsets.all(16),
                    itemCount: widget.carrinho.length,
                    separatorBuilder: (_, __) => Divider(color: Colors.white.withOpacity(0.05), height: 16),
                    itemBuilder: (context, index) {
                      final item = widget.carrinho[index];
                      final isSelected = index == _selectedIndex;
                      
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isSelected ? Colors.cyanAccent.withOpacity(0.08) : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected ? Colors.cyanAccent.withOpacity(0.3) : Colors.transparent,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: isSelected ? Colors.cyanAccent : Colors.cyanAccent.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                _itemVendidoPorEmbalagem(item)
                                    ? '${item.quantidade.toStringAsFixed(item.quantidade == item.quantidade.roundToDouble() ? 0 : 2)} ${_unidadeVendaLabelItem(item).toLowerCase()}${item.quantidade > 1 ? 's' : ''}'
                                    : '${item.quantidade.toStringAsFixed(item.quantidade == item.quantidade.roundToDouble() ? 0 : 2)}x',
                                style: TextStyle(
                                  color: isSelected ? Colors.black : Colors.cyanAccent,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.nome.toUpperCase(),
                                    style: TextStyle(
                                      color: isSelected ? Colors.cyanAccent : Colors.white,
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  if (item.descricao != null && item.descricao!.isNotEmpty)
                                    Text(
                                      item.descricao!,
                                      style: TextStyle(
                                        color: isSelected ? Colors.white70 : Colors.white38,
                                        fontSize: 12,
                                      ),
                                    ),
                                  if (item.descontoPromocionalPercent != null) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      '${item.descontoPromocionalPercent!.toStringAsFixed(0)}% promocional · -${_formatoMoeda.format(item.descontoPromocionalValor!)}',
                                      style: TextStyle(
                                        color: Colors.orangeAccent,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  _formatoMoeda.format(item.subtotalSemDesconto),
                                  style: TextStyle(
                                    color: isSelected ? Colors.cyanAccent : Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                Text(
                                  'un: ${_formatoMoeda.format(item.preco)}',
                                  style: TextStyle(
                                    color: isSelected ? Colors.white38 : Colors.white24,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.cyanAccent.withOpacity(0.15), Colors.transparent],
                  ),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.cyanAccent.withOpacity(0.2)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'TOTAL DA VENDA',
                          style: TextStyle(
                            color: Colors.cyanAccent.withOpacity(0.7),
                            fontWeight: FontWeight.w900,
                            fontSize: 12,
                            letterSpacing: 1,
                          ),
                        ),
                        Text(
                          '${_totalItens} produtos lançados',
                          style: const TextStyle(color: Colors.white38, fontSize: 13),
                        ),
                      ],
                    ),
                    Text(
                      _formatoMoeda.format(_totalCarrinho),
                      style: const TextStyle(
                        color: Colors.cyanAccent,
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                        shadows: [
                          Shadow(color: Colors.cyanAccent, blurRadius: 15),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                   Icon(Icons.swap_vert, color: Colors.cyanAccent, size: 16),
                  const SizedBox(width: 4),
                  const Text(
                    'SETAS PARA NAVEGAR',
                    style: TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 16),
                   Icon(Icons.backspace_outlined, color: Colors.redAccent, size: 16),
                  const SizedBox(width: 4),
                  const Text(
                    'DEL/BACKSPACE PARA REMOVER',
                    style: TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 16),
                   Icon(Icons.close, color: Colors.white24, size: 16),
                  const SizedBox(width: 4),
                  const Text(
                    'ESC PARA FECHAR',
                    style: TextStyle(color: Colors.white24, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}


