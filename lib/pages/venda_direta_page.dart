import 'dart:math' as math;
import 'dart:async';
import 'dart:html' as html if (dart.library.html) 'dart:html';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:sistema_exodo_novo/models/conta_pagar.dart';
import 'package:sistema_exodo_novo/services/data_service.dart';
import 'package:sistema_exodo_novo/services/local_storage_service.dart';
import 'package:sistema_exodo_novo/models/produto.dart';
import 'package:sistema_exodo_novo/models/servico.dart';
import 'package:sistema_exodo_novo/models/cliente.dart';
import 'package:sistema_exodo_novo/models/pedido.dart';
import 'package:sistema_exodo_novo/models/item_pedido.dart';
import 'package:sistema_exodo_novo/models/item_servico.dart';
import 'package:sistema_exodo_novo/models/forma_pagamento.dart';
import 'package:sistema_exodo_novo/models/venda_balcao.dart';
import 'package:sistema_exodo_novo/models/empresa.dart';
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
import 'package:sistema_exodo_novo/services/nfce_service_factory.dart';
import 'package:sistema_exodo_novo/services/nfce_service.dart';
import 'package:sistema_exodo_novo/models/nfce.dart';
import 'package:sistema_exodo_novo/models/carrinho_item.dart';
import 'package:sistema_exodo_novo/models/mesa_comanda.dart';
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
import 'package:pdf/pdf.dart';
import 'package:sistema_exodo_novo/services/pedido_pdf_service.dart';

/// Item no carrinho da venda direta
class ItemCarrinho {
  final String id;
  final String nome;
  final String? descricao; // Descrição do produto/serviço
  final double preco;
  int quantidade;
  final bool isServico;
  double desconto; // Desconto em valor (R$)
  final String? fornecedorNome; // Fornecedor do produto
  final String? fornecedorId; // ID do fornecedor do produto
  String? observacao;
  final List<AdicionalProduto> adicionais;

  ItemCarrinho({
    required this.id,
    required this.nome,
    this.descricao,
    required this.preco,
    this.quantidade = 1,
    this.isServico = false,
    this.desconto = 0.0,
    this.fornecedorNome,
    this.fornecedorId,
    this.observacao,
    List<AdicionalProduto>? adicionais,
  }) : adicionais = adicionais ?? [];

  double get subtotal {
    final totalAdicionais = adicionais.fold(0.0, (sum, a) => sum + a.preco);
    return ((preco + totalAdicionais) * quantidade) - desconto;
  }
  double get subtotalSemDesconto {
    final totalAdicionais = adicionais.fold(0.0, (sum, a) => sum + a.preco);
    return (preco + totalAdicionais) * quantidade;
  }

  // Serialização para persistência
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'nome': nome,
      'descricao': descricao,
      'preco': preco,
      'quantidade': quantidade,
      'isServico': isServico,
      'desconto': desconto,
      'fornecedorNome': fornecedorNome,
      'fornecedorId': fornecedorId,
      'observacao': observacao,
      'adicionais': adicionais.map((a) => a.toMap()).toList(),
    };
  }

  factory ItemCarrinho.fromMap(Map<String, dynamic> map) {
    return ItemCarrinho(
      id: map['id'] ?? '',
      nome: map['nome'] ?? '',
      descricao: map['descricao'],
      preco: (map['preco'] ?? 0.0).toDouble(),
      quantidade: map['quantidade'] ?? 1,
      isServico: map['isServico'] ?? false,
      desconto: (map['desconto'] ?? 0.0).toDouble(),
      fornecedorNome: map['fornecedorNome'],
      fornecedorId: map['fornecedorId'],
      observacao: map['observacao'],
      adicionais: (map['adicionais'] as List<dynamic>?)
          ?.map((a) => AdicionalProduto.fromMap(a as Map<String, dynamic>))
          .toList() ?? [],
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

class _VendaDiretaPageState extends State<VendaDiretaPage> {
  final _buscaController = TextEditingController();
  final _buscaFocusNode = FocusNode();
  String _termoBusca = '';
  SortOption _sortOption = SortOption.codigo;
  final List<ItemCarrinho> _carrinho = [];
  Cliente? _clienteSelecionado;
  String? _categoriaAtiva;
  int _quantidadeDigitada = 1;
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
  String? _ultimoItemAdicionadoId; // ID do último item adicionado (para destaque)

  // ESTADO DE DELIVERY
  bool _isDelivery = false;
  EnderecoCliente? _enderecoEntrega;
  double _taxaEntrega = 0.0;
  String? _motoristaId;
  String? _motoristaNome;

  bool _estaFinalizando = false; // Flag para evitar duplos cliques e concorrência
  final LocalStorageService _storage = LocalStorageService();
  static const String _keyCarrinhoPDV = 'exodo_carrinho_pdv';
  static const String _keyClientePDV = 'exodo_cliente_pdv';
  static const String _keyCpfNfcePDV = 'exodo_cpf_nfce_pdv';
  static const String _keyNomeNfcePDV = 'exodo_nome_nfce_pdv';
  static const String _keyDescontoTotalPDV = 'exodo_desconto_total_pdv';

  // Getters para facilitar identificação de Mesa/Comanda
  String get tipoNome {
    if (_mesaComandaVinculada == null) return 'Venda';
    return _mesaComandaVinculada?.tipo == TipoControle.comanda ? 'Comanda' : 'Mesa';
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
        if (html.document.fullscreenElement == null) {
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
          preco: widget.mesaComanda!.valorCouvertCalculado / (widget.mesaComanda!.quantidadePessoasCouvert ?? 1),
          quantidade: widget.mesaComanda!.quantidadePessoasCouvert ?? 1,
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
          _carregarClienteSelecionado();
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
        final doc = html.window.document;
        if (doc.fullscreenElement == null) {
          doc.documentElement?.requestFullscreen();
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
        final doc = html.window.document;
        if (doc.fullscreenElement == null) {
          doc.documentElement?.requestFullscreen();
        } else {
          doc.exitFullscreen();
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
    _timerFullscreen?.cancel();
    _buscaController.dispose();
    _buscaFocusNode.dispose();
    _atalhosFocusNode.dispose();
    _carrinhoScrollController.dispose();
    super.dispose();
  }

  // ============ Métodos de Persistência do Carrinho ============

  /// Carrega o carrinho salvo do localStorage
  Future<void> _carregarCarrinhoSalvo() async {
    try {
      if (widget.pedidoParaEditar != null) {
        // Não carregar carrinho salvo se estiver editando um pedido
        return;
      }

      final carrinhoMap = await _storage.carregarLista(_keyCarrinhoPDV);
      if (carrinhoMap.isNotEmpty) {
        setState(() {
          _carrinho.clear();
          _carrinho.addAll(carrinhoMap.map((map) => ItemCarrinho.fromMap(map)));
        });
        debugPrint('>>> ✓ Carrinho carregado: ${_carrinho.length} itens');
      }

      // Carregar desconto total
      final descontoTotalMap = await _storage.carregar(_keyDescontoTotalPDV);
      if (descontoTotalMap != null && descontoTotalMap is double) {
        setState(() {
          _descontoTotal = descontoTotalMap;
        });
      }
    } catch (e) {
      debugPrint('>>> ✗ Erro ao carregar carrinho: $e');
    }
  }

  /// Salva o carrinho atual no localStorage
  Future<void> _salvarCarrinho() async {
    try {
      if (widget.pedidoParaEditar != null) {
        // Não salvar se estiver editando um pedido
        return;
      }

      await _storage.salvarLista(_keyCarrinhoPDV, _carrinho);
      await _storage.salvar(_keyDescontoTotalPDV, _descontoTotal);
      debugPrint('>>> ✓ Carrinho salvo: ${_carrinho.length} itens');
    } catch (e) {
      debugPrint('>>> ✗ Erro ao salvar carrinho: $e');
    }
  }

  /// Carrega o cliente selecionado salvo
  Future<void> _carregarClienteSelecionado() async {
    try {
      if (widget.pedidoParaEditar != null || widget.clienteInicial != null) {
        // Não carregar se já tiver cliente definido
        return;
      }

      final clienteMap = await _storage.carregarLista(_keyClientePDV);
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
        await _storage.salvarLista(_keyClientePDV, [
          {'id': _clienteSelecionado!.id},
        ]);
        debugPrint('>>> ✓ Cliente salvo: ${_clienteSelecionado!.nome}');
      } else {
        // Se não há cliente, limpar do storage (salvar lista vazia)
        await _storage.salvarLista(_keyClientePDV, []);
      }
    } catch (e) {
      debugPrint('>>> ✗ Erro ao salvar cliente: $e');
    }
  }

  /// Limpa o carrinho e cliente salvos (quando finalizar venda)
  Future<void> _limparCarrinhoSalvo() async {
    try {
      // Limpar carrinho (salvar lista vazia)
      await _storage.salvarLista(_keyCarrinhoPDV, []);
      // Limpar cliente (salvar lista vazia)
      await _storage.salvarLista(_keyClientePDV, []);
      // Limpar desconto total
      await _storage.salvar(_keyDescontoTotalPDV, 0.0);
      debugPrint('>>> ✓ Carrinho, cliente e desconto limpos do storage');
    } catch (e) {
      debugPrint('>>> ✗ Erro ao limpar carrinho: $e');
    }
  }

  /// Reseta completamente o estado da venda na interface (limpa carrinho, cliente, seleções e focos)
  void _resetarTodaVenda() {
    setState(() {
      _carrinho.clear();
      _clienteSelecionado = null;
      _descontoTotal = 0.0;
      _observacoesVenda = null;
      _pagamentosSalvos = [];
      _gridSelectedIndex = -1;
      _cartSelectedIndex = -1;
      _categoriaSelectedIndex = -1;
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

  int get _totalItens =>
      _carrinho.fold(0, (sum, item) => sum + item.quantidade);

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
                  setState(() {
                    _carrinho.add(
                      ItemCarrinho(
                        id: produto.id,
                        nome: produto.nome,
                        descricao: produto.descricao,
                        preco: produto.precoAtual,
                        isServico: false,
                        quantidade: _quantidadeDigitada,
                        fornecedorNome: fornecedorPreSelecionado ?? produto.fornecedorNome,
                        observacao: produto.observacaoPadrao,
                        adicionais: List<AdicionalProduto>.from(selecionados),
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
                      preco: produto.precoAtual,
                      isServico: false,
                      paraCozinha: produto.paraCozinha,
                      paraBar: produto.paraBar,
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

  void _efetivarAdicaoAoCarrinho(dynamic item, {String? fornecedorNome, bool manterFoco = false}) {
    final isServico = item is Servico;
    final id = item.id;
    final nome = item.nome;
    final preco = isServico ? item.preco : (item as Produto).precoAtual;
    final descricao = isServico ? null : (item as Produto).descricao;
    final observacao = isServico ? null : (item as Produto).observacaoPadrao;
    final fornecedorId = isServico ? null : (item as Produto).fornecedorId;

    // Se fornecedorNome não foi passado, tenta usar o do produto
    final fNome = fornecedorNome ?? (isServico ? null : (item as Produto).fornecedorNome);

    // Verificar se já existe no carrinho com MESMO fornecedor
    final index = _carrinho.indexWhere((c) => c.id == id && c.adicionais.isEmpty && c.fornecedorNome == fNome);
    final bool jaExistia = index >= 0;

    if (jaExistia) {
      setState(() {
        // Mover item existente para o fim da lista (topo no visual invertido)
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
            descricao: descricao,
            preco: preco,
            isServico: isServico,
            quantidade: _quantidadeDigitada,
            fornecedorNome: fNome,
            fornecedorId: fornecedorId,
            observacao: observacao,
          ),
        );
      });
    }

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
    final int quantidadeAtual = jaExistia
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
      _quantidadeDigitada = 1;
    });

    if (!manterFoco) {
      setState(() {
        _termoBusca = '';
      });
      _buscaController.clear();
      _buscaFocusNode.requestFocus();
    }

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

  void _adicionarAoCarrinho(dynamic item, {bool manterFoco = false}) {
    if (item is! Produto) {
      _efetivarAdicaoAoCarrinho(item, manterFoco: manterFoco);
      return;
    }

    final produto = item as Produto;
    final isServico = item is Servico;
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

    _efetivarAdicaoAoCarrinho(item, manterFoco: manterFoco);
  }

  bool _deveMostrarAdicionais(Produto produto, Empresa? empresa) {
    if (!produto.temAdicionais) return false;
    
    // Verificar se realmente tem algum adicional para mostrar (produto ou global)
    final especificos = produto.adicionais.where((a) => a.ativo).isNotEmpty;
    final globais = (empresa?.modelosAdicionais ?? []).isNotEmpty;
    
    return especificos || globais;
  }

  void _alterarQuantidade(int index, int delta) {
    setState(() {
      _carrinho[index].quantidade += delta;
      if (_carrinho[index].quantidade <= 0) {
        _carrinho.removeAt(index);
      }
    });

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
            quantidade: delta,
            preco: itemCarrinho.preco,
            isServico: itemCarrinho.isServico,
            paraCozinha: itemCarrinho.isServico ? false : dataService.getProdutoById(itemCarrinho.id)?.paraCozinha,
            paraBar: itemCarrinho.isServico ? false : dataService.getProdutoById(itemCarrinho.id)?.paraBar,
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

  List<Produto> _getProdutosPorCategoria(DataService dataService) {
    List<Produto> lista;
    if (_categoriaAtiva == null) {
      lista = List<Produto>.from(dataService.produtos);
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
          return dateB.compareTo(dateA); // Do mais novo para o mais antigo
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
    
    return lista;
  }

  List<dynamic> _buscarItens(DataService dataService) {
    if (_termoBusca.isEmpty) return [];

    final buscaLower = _termoBusca.toLowerCase().trim();
    final ehNumero = RegExp(r'^[0-9]+$').hasMatch(buscaLower);

    // Se for número, mínimo 1 caractere; se for texto, mínimo 2 caracteres
    if (!ehNumero && buscaLower.length < 2) return [];

    final resultados = <dynamic>[];

    // Se digitar 9999, garantir que o produto Diversos existe e adicionar aos resultados
    if (ehNumero && buscaLower == '9999') {
      dataService.garantirProdutoDiversos().then((diversos) {
        if (mounted) {
          setState(() {
            // Força atualização para mostrar o produto Diversos
          });
        }
      });
    }

    // Extrair números do query (removendo zeros à esquerda para comparação)
    final queryNumeros = _termoBusca.replaceAll(RegExp(r'[^0-9]'), '');
    final queryNumerosSemZeros = queryNumeros.isEmpty
        ? ''
        : int.tryParse(queryNumeros)?.toString() ?? queryNumeros;

    // Buscar produtos com busca avançada
    for (final produto in dataService.produtos) {
      // Filtro por categoria (se houver categoria ativa)
      if (_categoriaAtiva != null && produto.grupo != _categoriaAtiva) {
        continue;
      }

      final nome = produto.nome.toLowerCase().trim();
      final codigo = (produto.codigo ?? '').trim();
      final codigoLower = codigo.toLowerCase();
      final codigoBarras = (produto.codigoBarras ?? '').trim();
      final codigoBarrasLower = codigoBarras.toLowerCase();
      final grupo = produto.grupo.toLowerCase();

      // Extrair números dos códigos
      final codigoNumeros = codigo.replaceAll(RegExp(r'[^0-9]'), '');
      final codigoNumerosSemZeros = codigoNumeros.isEmpty
          ? ''
          : int.tryParse(codigoNumeros)?.toString() ?? codigoNumeros;
      final codigoBarrasNumeros = codigoBarras.replaceAll(
        RegExp(r'[^0-9]'),
        '',
      );
      final codigoBarrasNumerosSemZeros = codigoBarrasNumeros.isEmpty
          ? ''
          : int.tryParse(codigoBarrasNumeros)?.toString() ??
                codigoBarrasNumeros;

      // 1. Match exato de código
      if (codigoLower == buscaLower || codigo == _termoBusca) {
        resultados.add(produto);
        continue;
      }

      // 2. Match exato de código de barras
      if (codigoBarrasLower == buscaLower || codigoBarras == _termoBusca) {
        resultados.add(produto);
        continue;
      }

      // 3. Match numérico exato (ignorando zeros à esquerda)
      if (queryNumerosSemZeros.isNotEmpty) {
        if (codigoNumerosSemZeros == queryNumerosSemZeros ||
            codigoBarrasNumerosSemZeros == queryNumerosSemZeros) {
          resultados.add(produto);
          continue;
        }
        if (codigoNumeros == queryNumeros ||
            codigoBarrasNumeros == queryNumeros) {
          resultados.add(produto);
          continue;
        }
      }

      // 4. Código começa com o termo
      if (codigoLower.startsWith(buscaLower) && codigoLower.isNotEmpty) {
        resultados.add(produto);
        continue;
      }

      // 5. Código de barras começa com o termo
      if (codigoBarrasLower.startsWith(buscaLower) &&
          codigoBarrasLower.isNotEmpty) {
        resultados.add(produto);
        continue;
      }

      // 6. Código numérico começa com o termo
      if (queryNumerosSemZeros.isNotEmpty) {
        if (queryNumerosSemZeros.length == 2) {
          if ((codigoNumerosSemZeros.startsWith(queryNumerosSemZeros) &&
                  codigoNumerosSemZeros.length <= 3) ||
              (codigoBarrasNumerosSemZeros.startsWith(queryNumerosSemZeros) &&
                  codigoBarrasNumerosSemZeros.length <= 3)) {
            resultados.add(produto);
            continue;
          }
        } else if (queryNumerosSemZeros.length >= 3) {
          if (codigoNumerosSemZeros.startsWith(queryNumerosSemZeros) ||
              codigoBarrasNumerosSemZeros.startsWith(queryNumerosSemZeros)) {
            resultados.add(produto);
            continue;
          }
        }
      }

      // 7. Match exato do nome (SOMENTE se não for busca apenas numérica)
      if (!ehNumero && nome == buscaLower) {
        resultados.add(produto);
        continue;
      }

      // 8. Nome começa com o termo (SOMENTE se não for busca apenas numérica)
      if (!ehNumero && nome.startsWith(buscaLower)) {
        resultados.add(produto);
        continue;
      }

      // 9. Busca por múltiplas palavras (SOMENTE se não for busca apenas numérica)
      if (!ehNumero) {
        final palavrasQuery = buscaLower
            .split(RegExp(r'[\s\-_]+'))
            .where((p) => p.isNotEmpty)
            .toList();
        if (palavrasQuery.length > 1) {
          final palavrasNome = nome.split(RegExp(r'[\s\-_]+'));
          final todasPalavrasEncontradas = palavrasQuery.every(
            (palavra) => palavrasNome.any(
              (pn) => pn.startsWith(palavra) || pn.contains(palavra),
            ),
          );
          if (todasPalavrasEncontradas) {
            resultados.add(produto);
            continue;
          }
        }
      }

      // 10. Nome contém o termo (3+ caracteres) (SOMENTE se não for busca apenas numérica)
      if (!ehNumero && _termoBusca.length >= 3 && nome.contains(buscaLower)) {
        resultados.add(produto);
        continue;
      }

      // 11. Código contém o termo (3+ caracteres)
      if (_termoBusca.length >= 3 && codigoLower.contains(buscaLower)) {
        resultados.add(produto);
        continue;
      }

      // 12. Código de barras contém o termo (3+ caracteres)
      if (_termoBusca.length >= 3 && codigoBarrasLower.contains(buscaLower)) {
        resultados.add(produto);
        continue;
      }

      // 13. Código numérico contém (3+ dígitos)
      if (queryNumerosSemZeros.length >= 3 &&
          (codigoNumerosSemZeros.contains(queryNumerosSemZeros) ||
              codigoBarrasNumerosSemZeros.contains(queryNumerosSemZeros))) {
        resultados.add(produto);
        continue;
      }

      // 14. Grupo contém o termo (SOMENTE se não for busca apenas numérica)
      if (!ehNumero && grupo.contains(buscaLower)) {
        resultados.add(produto);
        continue;
      }
    }

    // Buscar serviços (sempre, independente da categoria de produto ativa)
    for (final servico in dataService.servicos) {

      final nome = servico.nome.toLowerCase().trim();

      // Match exato
      if (nome == buscaLower) {
        resultados.add(servico);
        continue;
      }

      // Nome começa com o termo
      if (nome.startsWith(buscaLower)) {
        resultados.add(servico);
        continue;
      }

      // Busca por múltiplas palavras
      final palavrasQuery = buscaLower
          .split(RegExp(r'[\s\-_]+'))
          .where((p) => p.isNotEmpty)
          .toList();
      if (palavrasQuery.length > 1) {
        final palavrasNome = nome.split(RegExp(r'[\s\-_]+'));
        final todasPalavrasEncontradas = palavrasQuery.every(
          (palavra) => palavrasNome.any(
            (pn) => pn.startsWith(palavra) || pn.contains(palavra),
          ),
        );
        if (todasPalavrasEncontradas) {
          resultados.add(servico);
          continue;
        }
      }

      // Nome contém (3+ caracteres)
      if (_termoBusca.length >= 3 && nome.contains(buscaLower)) {
        resultados.add(servico);
        continue;
      }
    }

    // Ordenar por relevância
    resultados.sort((a, b) {
      final isProdutoA = a is Produto;
      final isProdutoB = b is Produto;

      // Produtos primeiro
      if (isProdutoA != isProdutoB) return isProdutoA ? -1 : 1;

      if (isProdutoA) {
        final produtoA = a as Produto;
        final produtoB = b as Produto;
        final aNome = produtoA.nome.toLowerCase();
        final bNome = produtoB.nome.toLowerCase();
        final aCodigo = (produtoA.codigo ?? '').trim().toLowerCase();
        final bCodigo = (produtoB.codigo ?? '').trim().toLowerCase();

        // Priorizar matches exatos
        final aCodigoExato = aCodigo == buscaLower || aCodigo == _termoBusca;
        final bCodigoExato = bCodigo == buscaLower || bCodigo == _termoBusca;
        if (aCodigoExato != bCodigoExato) return aCodigoExato ? -1 : 1;

        final aNomeExato = aNome.trim() == buscaLower;
        final bNomeExato = bNome.trim() == buscaLower;
        if (aNomeExato != bNomeExato) return aNomeExato ? -1 : 1;

        // Depois nomes que começam
        final aNomeComeca = aNome.startsWith(buscaLower);
        final bNomeComeca = bNome.startsWith(buscaLower);
        if (aNomeComeca != bNomeComeca) return aNomeComeca ? -1 : 1;

        // Por último, alfabeticamente
        return aNome.compareTo(bNome);
      } else {
        final servicoA = a as Servico;
        final servicoB = b as Servico;
        final aNome = servicoA.nome.toLowerCase();
        final bNome = servicoB.nome.toLowerCase();

        final aNomeExato = aNome.trim() == buscaLower;
        final bNomeExato = bNome.trim() == buscaLower;
        if (aNomeExato != bNomeExato) return aNomeExato ? -1 : 1;

        final aNomeComeca = aNome.startsWith(buscaLower);
        final bNomeComeca = bNome.startsWith(buscaLower);
        if (aNomeComeca != bNomeComeca) return aNomeComeca ? -1 : 1;

        return aNome.compareTo(bNome);
      }
    });

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
        quantidade: qtd,
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

    _mostrarDialogPagamento(dataService);
  }

  void _selecionarCliente(DataService dataService) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _buildSeletorCliente(dataService),
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
      });
      _salvarClienteSelecionado();
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
                                                                ? Colors.redAccent
                                                                : produto.estoque < 10
                                                                    ? Colors.orangeAccent
                                                                    : Colors.greenAccent.shade200,
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
                                                color: Colors.green.withOpacity(0.15),
                                                borderRadius: BorderRadius.circular(10),
                                                border: Border.all(
                                                  color: Colors.greenAccent.withOpacity(0.2),
                                                ),
                                              ),
                                              child: Text(
                                                'R\$ ${produto.preco.toStringAsFixed(2)}',
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
      final codigoBarras = (produto.codigoBarras ?? '').trim();
      final codigoBarrasLower = codigoBarras.toLowerCase();
      final grupo = produto.grupo.toLowerCase();

      final codigoNumeros = codigo.replaceAll(RegExp(r'[^0-9]'), '');
      final codigoNumerosSemZeros = codigoNumeros.isEmpty
          ? ''
          : int.tryParse(codigoNumeros)?.toString() ?? codigoNumeros;
      final codigoBarrasNumeros = codigoBarras.replaceAll(
        RegExp(r'[^0-9]'),
        '',
      );
      final codigoBarrasNumerosSemZeros = codigoBarrasNumeros.isEmpty
          ? ''
          : int.tryParse(codigoBarrasNumeros)?.toString() ??
                codigoBarrasNumeros;

      bool encontrou = false;

      // Se a busca for APENAS numérica, buscar SOMENTE pelo código (busca exata)
      if (ehApenasNumerico) {
        // Buscar APENAS por código ou código de barras (busca exata)
        if (codigoNumerosSemZeros == queryNumerosSemZeros ||
            codigoBarrasNumerosSemZeros == queryNumerosSemZeros ||
            codigoLower == queryLower ||
            codigo == query ||
            codigoBarrasLower == queryLower ||
            codigoBarras == query) {
          encontrou = true;
        }
      } else {
        // Busca com letras ou texto - busca normal (código e nome)
        if (codigoLower == queryLower ||
            codigo == query ||
            codigoBarrasLower == queryLower ||
            codigoBarras == query ||
            (queryNumerosSemZeros.isNotEmpty &&
                (codigoNumerosSemZeros == queryNumerosSemZeros ||
                    codigoBarrasNumerosSemZeros == queryNumerosSemZeros)) ||
            codigoLower.startsWith(queryLower) ||
            codigoBarrasLower.startsWith(queryLower) ||
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

  void _mostrarDialogPagamento(DataService dataService) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _DialogPagamentoPDV(
        subtotal: _totalCarrinhoSemDesconto,
        descontoTotal: _totalCarrinhoSemDesconto - _totalCarrinho,
        totalCarrinho: _totalCarrinho,
        pagamentosIniciais: _pagamentosSalvos,
        cliente: _clienteSelecionado,
        cpfCnpjInicial: _cpfNfce,
        nomeInicial: _nomeNfce,
        onDadosConsumidorChanged: (cpf, nome) {
          _cpfNfce = cpf;
          _nomeNfce = nome;
          // Não precisa dar setState aqui porque o modal já se gerencia
        },
        onConfirmar: (listaPagamentos) {
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

    setState(() => _estaFinalizando = true);
    
    final uuid = const Uuid();
    debugPrint('>>> [VendaDireta] 🚀 INICIANDO FINALIZAÇÃO DA VENDA (Segura)');
    debugPrint('>>> [VendaDireta] 🔍 Total Capturado: R\$ ${totalVendaCapturado.toStringAsFixed(2)}');
    debugPrint('>>> [VendaDireta] 🔍 Itens: ${itensVendaCapturados.length}');
    
    try {
      String numero = isDeliveryCapturado 
          ? dataService.getProximoNumeroPedido() 
          : dataService.getProximoNumeroVenda();
      if (mesaNumero != null) {
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
              precoUnitario: item.preco,
              quantidade: item.quantidade,
              isServico: item.isServico,
              fornecedorNome: item.fornecedorNome,
              observacao: item.observacao,
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

      final vendaId = uuid.v4();
      final vendaBalcao = VendaBalcao(
        id: vendaId,
        numero: numero,
        dataVenda: DateTime.now(),
        clienteId: clienteSelecionadoCapturado?.id,
        clienteNome: clienteNomeFinal,
        clienteTelefone: clienteSelecionadoCapturado?.telefone,
        clienteCpfCnpj: clienteSelecionadoCapturado?.cpfCnpj ?? cpfNfceCapturado,
        itens: itensVenda,
        tipoPagamento: tipoPagamentoVenda,
        valorTotal: totalVendaCapturado,
        valorRecebido: totalRecebido > 0 ? totalRecebido : null,
        troco: pagamentosAtualizados
            .where((p) => p.troco != null && p.troco! > 0)
            .fold<double?>(null, (sum, p) => (sum ?? 0) + (p.troco ?? 0)),
        observacoes: observacaoIdentificadora,
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
                dataPedido: DateTime.now(),
              )
            : null,
      );

      // SALVAR DADOS (Snapshot garantido)
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
    final authService = Provider.of<AuthService>(context, listen: false);
    final usuarioAtual = authService.usuarioAtual;
    String? nomeIdentificacao;

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
            quantidade: item.quantidade,
            isServico: item.isServico,
            fornecedorNome: item.fornecedorNome,
            observacao: item.observacao,
            adicionais: item.adicionais,
          ),
        )
        .toList();

    // Determinar tipo de pagamento principal (se houver)
    TipoPagamento tipoPrincipal = TipoPagamento.outro;
    if (pagamentosDoDialog.isNotEmpty) {
      tipoPrincipal = pagamentosDoDialog.first.tipo;
    }

    // Criar venda balcão
    final vendaBalcao = VendaBalcao(
      id: _pedidoOriginal?.id ?? uuid.v4(),
      numero: _pedidoOriginal?.numero ?? dataService.getProximoNumeroPedido(),
      dataVenda: _pedidoOriginal?.dataPedido ?? DateTime.now(),
      clienteId: _clienteSelecionado?.id,
      clienteNome: _clienteSelecionado?.nome ?? (nomeIdentificacao?.isNotEmpty == true ? nomeIdentificacao : (mesaNumero != null ? 'Mesa $mesaNumero' : null)),
      clienteTelefone: _clienteSelecionado?.telefone,

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
          ),
        );
      }
    }

    // Criar pedido a partir da venda salva
    final pedidoVendaSalva = Pedido(
      id: _pedidoOriginal?.id ?? uuid.v4(),
      numero: _pedidoOriginal?.numero ?? vendaBalcao.numero,
      clienteId: _clienteSelecionado?.id,
      clienteNome: vendaBalcao.clienteNome,
      clienteTelefone: _clienteSelecionado?.telefone ?? vendaBalcao.clienteTelefone,
      dataPedido: vendaBalcao.dataVenda,
      status: 'Pendente',
      produtos: produtosPedido,
      servicos: servicosPedido,
      pagamentos: pagamentosDoDialog.isNotEmpty 
          ? pagamentosDoDialog 
          : [PagamentoPedido(
              id: uuid.v4(),
              tipo: TipoPagamento.outro,
              valor: _totalCarrinho,
              recebido: false,
              observacao: 'Venda Salva: ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}',
            )],
      createdAt: vendaBalcao.dataVenda,
      updatedAt: vendaBalcao.dataVenda,
      observacoes: vendaBalcao.observacoes,
      vendedorId: usuarioAtual?.funcionarioId ?? usuarioAtual?.id,
      vendedorNome: usuarioAtual?.nome,
      deliveryInfo: vendaBalcao.deliveryInfo,
    );

    // Se estava editando um pedido/venda salva, remover o antigo ANTES de adicionar o novo
    // Isso evita duplicados e garante que o novo registro (com mesmo ID se carregado) persista
    if (_pedidoOriginal != null) {
      dataService.deletePedido(_pedidoOriginal!.id);
      final vendaOriginal = dataService.vendasBalcao
          .where((v) => v.numero == _pedidoOriginal!.numero)
          .firstOrNull;
      if (vendaOriginal != null) {
        dataService.deleteVendaBalcao(vendaOriginal.id);
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
      dataService.addPedido(pedidoVendaSalva);

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
    _limparCarrinhoSalvo();
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
    _resetarTodaVenda();
    // Limpar carrinho salvo após finalizar venda
    _limparCarrinhoSalvo();
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
      Uint8List pdfBytes;
      if (termico) {
        pdfBytes = await PedidoPDFService.gerarPDFTermico(
          pedido: pedido,
          empresa: empresa,
        );
      } else {
        pdfBytes = await PedidoPDFService.gerarPDF(
          pedido: pedido,
          empresa: empresa,
        );
      }

      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdfBytes,
        name: 'Pedido_${pedido.numero}',
      );
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
    _resetarTodaVenda();
    // Limpar carrinho salvo após finalizar venda
    _limparCarrinhoSalvo();
  }

  /// Notificação inteligente e discreta para itens adicionados
  void _mostrarNotificacaoItemAdicionado({
    required String nome,
    required int quantidade,
    required int quantidadeTotal,
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
    _resetarTodaVenda();
    // Limpar carrinho salvo após finalizar venda
    _limparCarrinhoSalvo();
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
    _resetarTodaVenda();
    // Limpar carrinho salvo após finalizar venda
    _limparCarrinhoSalvo();
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

    _resetarTodaVenda();
    // Limpar carrinho e cliente salvos após finalizar
    _limparCarrinhoSalvo();
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
      // Limpar carrinho e cliente após fechar
      if (mounted) {
        _resetarTodaVenda();
        _limparCarrinhoSalvo();
        // Se veio do controle de mesas, voltar para aquela tela
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
      final empresa = authService.empresaAtual;

      debugPrint('>>> [VendaDireta] ========================================');
      debugPrint(
        '>>> [VendaDireta] Verificando empresa antes de emitir NFC-e...',
      );
      debugPrint(
        '>>> [VendaDireta] empresa: ${empresa != null ? empresa.razaoSocial : "null"}',
      );

      if (empresa == null) {
        debugPrint('>>> [VendaDireta] ❌ Nenhuma empresa selecionada!');
        _mostrarErro(
          'Nenhuma empresa selecionada.\n\n'
          'SOLUÇÃO: Verifique se você está logado e se uma empresa foi selecionada no início do aplicativo.',
        );
        return;
      }

      debugPrint(
        '>>> [VendaDireta] configuracoes: ${empresa.configuracoes != null ? "presente" : "null"}',
      );
      if (empresa.configuracoes != null) {
        debugPrint(
          '>>> [VendaDireta] configuracoes.keys: ${empresa.configuracoes!.keys.toList()}',
        );
        final bytes = empresa.configuracoes!['certificadoDigitalBytes'];
        debugPrint(
          '>>> [VendaDireta] certificadoDigitalBytes: ${bytes != null ? "presente (${(bytes as String).length} chars)" : "null"}',
        );
        debugPrint(
          '>>> [VendaDireta] certificadoWindowsThumbprint: ${empresa.configuracoes!['certificadoWindowsThumbprint'] ?? "null"}',
        );
      }
      debugPrint(
        '>>> [VendaDireta] certificadoDigitalUrl: ${empresa.certificadoDigitalUrl ?? "null"}',
      );
      debugPrint(
        '>>> [VendaDireta] senhaCertificado: ${empresa.senhaCertificado != null && empresa.senhaCertificado!.isNotEmpty ? "presente (${empresa.senhaCertificado!.length} chars)" : "AUSENTE"}',
      );
      debugPrint('>>> [VendaDireta] ========================================');

      // Validar configurações NFC-e
      final temCertificado =
          (empresa.configuracoes?['certificadoDigitalBytes'] != null &&
              (empresa.configuracoes!['certificadoDigitalBytes'] as String)
                  .isNotEmpty) ||
          (empresa.certificadoDigitalUrl != null &&
              empresa.certificadoDigitalUrl!.isNotEmpty) ||
          (empresa.configuracoes?['certificadoWindowsThumbprint'] != null);

      if (!temCertificado ||
          empresa.senhaCertificado == null ||
          empresa.senhaCertificado!.isEmpty) {
        debugPrint('>>> [VendaDireta] ❌ Certificado digital não configurado!');
        _mostrarErro(
          'Certificado digital não configurado. Configure na empresa.\n\n'
          'DIAGNÓSTICO:\n'
          '• Base64: ${empresa.configuracoes?['certificadoDigitalBytes'] != null ? "presente" : "ausente"}\n'
          '• URL: ${empresa.certificadoDigitalUrl != null ? "presente" : "ausente"}\n'
          '• Windows: ${empresa.configuracoes?['certificadoWindowsThumbprint'] != null ? "presente" : "ausente"}\n'
          '• Senha: ${empresa.senhaCertificado != null ? "presente" : "ausente"}',
        );
        return;
      }

      if (empresa.csc == null || empresa.cscIdToken == null) {
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

      // Converter pagamentos
      final pagamentos = <NFCePagamento>[];
      String tipoPagamento = '01'; // Dinheiro por padrão
      switch (vendaBalcao.tipoPagamento) {
        case TipoPagamento.dinheiro:
          tipoPagamento = '01';
          break;
        case TipoPagamento.pix:
          tipoPagamento = '99';
          break;
        case TipoPagamento.cartaoCredito:
          tipoPagamento = '03';
          break;
        case TipoPagamento.cartaoDebito:
          tipoPagamento = '04';
          break;
        default:
          tipoPagamento = '99';
      }

      pagamentos.add(
        NFCePagamento(tipo: tipoPagamento, valor: vendaBalcao.valorTotal),
      );

      // Usar URL configurada na empresa (importante para Túneis como Zrok/Ngrok)
      final configUrl = empresa.configuracoes?['bridgeNfceUrl'] as String?;
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
      final ambienteHomologacao = empresa.ambienteHomologacao ?? true;

      debugPrint(
        '>>> [VendaDireta] Ambiente: ${ambienteHomologacao ? "Homologação" : "Produção"}',
      );

      // Obter usuário atual
      final usuario = authService.usuarioAtual;
      final serieUsuario = usuario?.serieNfce;

      final nfce = await nfceService.emitir(
        empresa: empresa,
        produtos: produtos,
        quantidades: quantidades,
        pagamentos: pagamentos,
        valorTotal: vendaBalcao.valorTotal,
        cpfCnpjConsumidor: cpfCnpjOverride ?? vendaBalcao.clienteCpfCnpj,
        nomeConsumidor: nomeOverride ?? vendaBalcao.clienteNome,
        observacoes: vendaBalcao.observacoes,
        vendaId: vendaBalcao.id,
        vendaNumero: numeroOverride ?? dataService.getProximoNumeroNfce().toString(),
        ambienteHomologacao: ambienteHomologacao,
        serie: serieUsuario,
      );

      // Salvar NFC-e no DataService
      await dataService.adicionarNFCe(nfce);

      // Fechar diálogo de processamento
      if (mounted) Navigator.pop(context);

      // Mostrar resultado
      if (nfce.status == 'autorizada') {
        // Mostrar mensagem de sucesso em verde bem visível
        _mostrarMensagemSucessoNFCe(nfce);
        _mostrarSucessoNFCe(nfce);
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
    final proximoDisponivel = dataService.getProximoNumeroNfce().toString();
    
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
    
    if (empresa == null || 
        empresa.whatsappApiUrl == null || 
        empresa.whatsappApiKey == null) {
      _mostrarErro('Configuração de WhatsApp não encontrada. Configure em Configurações > WhatsApp.');
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
      final service = WhatsAppService.fromEmpresa(empresa);
      final isConnected = await service.isConectado();
      
      if (!isConnected) {
        if (mounted) Navigator.pop(context);
        _mostrarErro('WhatsApp não está conectado.\n\nAcesse o Gerenciamento WhatsApp na Home para conectar seu aparelho.');
        return;
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
      buffer.writeln('━━━━━━━━━━━━━━━━━━━━');
      buffer.writeln('Obrigado pela preferência! 😊');
      if (empresa.telefone != null) {
        buffer.writeln('📞 Contato: ${empresa.telefone}');
      }

      final ok = await service.enviarMensagem(telefone, buffer.toString());
      
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
    final authService = Provider.of<AuthService>(context, listen: false);
    final usuarioAtual = authService.usuarioAtual;
    final uuid = const Uuid();
    
    try {
      final numero = dataService.getProximoNumeroPedido();
      final vendaId = uuid.v4();
      
      final itensVenda = _carrinho.map((item) => ItemVendaBalcao(
        id: item.id,
        nome: item.nome,
        precoUnitario: item.preco,
        quantidade: item.quantidade,
        isServico: item.isServico,
        fornecedorNome: item.fornecedorNome,
        observacao: item.observacao,
        adicionais: item.adicionais,
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
        itens: itensVenda,
        tipoPagamento: TipoPagamento.outro, // Lançado como pendente
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
          ));
        }
      }

      final pedido = Pedido(
        id: vendaId,
        numero: numero,
        clienteId: _clienteSelecionado?.id,
        clienteNome: vendaBalcao.clienteNome,
        clienteTelefone: vendaBalcao.clienteTelefone,
        dataPedido: vendaBalcao.dataVenda,
        status: 'Pendente',
        total: vendaBalcao.valorTotal,
        produtos: produtosPedido,
        servicos: servicosPedido,
        pagamentos: [
          PagamentoPedido(
            id: uuid.v4(),
            tipo: TipoPagamento.outro,
            valor: vendaBalcao.valorTotal,
            recebido: false,
          )
        ],
        deliveryInfo: deliveryInfo,
        observacoes: vendaBalcao.observacoes,
        vendedorId: usuarioAtual?.funcionarioId ?? usuarioAtual?.id,
        vendedorNome: usuarioAtual?.nome,
      );

      // SALVAR TUDO
      await dataService.addPedido(pedido);
      
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

  void _abrirConfiguracoesPDV() {
    final dataService = Provider.of<DataService>(context, listen: false);
    final authService = Provider.of<AuthService>(context, listen: false);
    final empresa = dataService.empresaAtual;
    if (empresa == null) return;

    // Estado local para resposta instantânea
    bool selecionarFornecedorLocal = empresa.configuracoes?['selecionarFornecedorPDV'] == true;

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
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
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
                    title: const Text('Selecionar Fornecedor', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
                const SizedBox(height: 20),
                const Text(
                  'As alterações são aplicadas a todas as vendas desta empresa.',
                  style: TextStyle(color: Colors.white38, fontSize: 11, fontStyle: FontStyle.italic),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('CANCELAR', style: TextStyle(color: Colors.white54)),
              ),
              ElevatedButton(
                onPressed: () async {
                  final config = Map<String, dynamic>.from(empresa.configuracoes ?? {});
                  config['selecionarFornecedorPDV'] = selecionarFornecedorLocal;
                  
                  final novaEmpresa = empresa.copyWith(configuracoes: config);
                  // Usar AuthService para garantir que o estado global seja atualizado e não sobrescrito pelo AuthWrapper
                  await authService.atualizarEmpresa(novaEmpresa);
                  
                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Row(
                          children: [
                            const Icon(Icons.check_circle, color: Colors.white),
                            const SizedBox(width: 10),
                            Text('Configurações salvas: Seleção de fornecedor ${selecionarFornecedorLocal ? "ativada" : "desativada"}.'),
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

  void _abrirDialogDelivery() {
    if (_clienteSelecionado == null) {
      _mostrarErro('Selecione um cliente antes de configurar a Entrega.');
      return;
    }

    final dataService = Provider.of<DataService>(context, listen: false);
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final cliente = dataService.getClienteById(_clienteSelecionado!.id) ?? _clienteSelecionado!;
          
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
                                setState(() => _taxaEntrega = double.tryParse(value) ?? 0.0);
                              },
                              controller: TextEditingController(text: _taxaEntrega > 0 ? _taxaEntrega.toStringAsFixed(2) : ''),
                              keyboardType: TextInputType.number,
                              style: const TextStyle(color: Colors.white),
                              decoration: InputDecoration(
                                labelText: 'Taxa de Entrega',
                                labelStyle: const TextStyle(color: Colors.white54),
                                prefixText: 'R\$ ',
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white10)),
                                focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.orangeAccent)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextField(
                              onChanged: (value) {
                                setState(() => _motoristaNome = value);
                              },
                              controller: TextEditingController(text: _motoristaNome ?? ''),
                              style: const TextStyle(color: Colors.white),
                              decoration: InputDecoration(
                                labelText: 'Motorista / Motoboy',
                                labelStyle: const TextStyle(color: Colors.white54),
                                prefixIcon: const Icon(Icons.person_pin, color: Colors.white24),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white10)),
                                focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.orangeAccent)),
                              ),
                            ),
                          ),
                        ],
                      ),
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
              if (_isDelivery)
                ElevatedButton(
                  onPressed: () {
                    if (_isDelivery && _enderecoEntrega == null) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Selecione um endereço para a Entrega')));
                      return;
                    }
                    if (_estaFinalizando) return;
                    
                    // Em vez de finalizar direto, fechamos este diálogo e abrimos o de PAGAMENTO
                    // para que o usuário possa lançar como pago, parcial ou pendente.
                    Navigator.pop(context);
                    _mostrarDialogPagamento(dataService);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orangeAccent,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('CONFIRMAR E IR PARA PAGAMENTO', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
                ),
            ],
          );
        },
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
    }
  }

  Widget _buildSeletorCliente(DataService dataService) {
    return _SeletorClienteWidget(
      dataService: dataService,
      clienteSelecionadoId: _clienteSelecionado?.id,
      onClienteSelecionado: (cliente) {
        setState(() => _clienteSelecionado = cliente);
        _salvarClienteSelecionado();
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
    Map<String, int> produtosContagem = {};
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
                        ...produtosOrdenados.take(10).map((entry) {
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
                          ...servicosOrdenados.take(5).map((entry) {
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
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final isVerySmallHeight = screenHeight < 650;
    final isSmallHeight = screenHeight < 750;

    // Se digitar 9999, garantir que o produto Diversos existe
    if (_termoBusca == '9999') {
      dataService.garantirProdutoDiversos();
    }

    final itensEncontrados = _buscarItens(dataService);
    final categorias = _getCategorias(dataService);
    final produtosCategoria = _getProdutosPorCategoria(dataService);

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

        // Tecla SHIFT - Focar Carrinho rapidamente
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
          return KeyEventResult.handled;
        }

        // Tecla CONTROL - Conferência de Itens
        if (key == LogicalKeyboardKey.controlLeft || key == LogicalKeyboardKey.controlRight) {
           _abrirConferenciaItens();
           return KeyEventResult.handled;
        }

        // Tecla F8 - Salvar / Pedido
        if (key == LogicalKeyboardKey.f8) {
          if (_carrinho.isNotEmpty) {
            _salvarVendaPendente(dataService, [], mostrarPromptImpressao: true);
          }
          return KeyEventResult.handled;
        }

        // Tecla F9 - Finalizar/Receber
        if (key == LogicalKeyboardKey.f9) {
          if (_carrinho.isNotEmpty) {
            _finalizarVenda(dataService);
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
            final maxItems = _termoBusca.isNotEmpty
                ? _buscarItens(dataService).length
                : (_categoriaAtiva != null
                    ? _getProdutosPorCategoria(dataService).length
                    : 0);

            if (_gridSelectedIndex < maxItems - 1) {
              setState(() => _gridSelectedIndex++);
              return KeyEventResult.handled;
            }
            // Fim do grid sem mais items: ir para o carrinho
            if (_carrinho.isNotEmpty) {
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
            setState(() => _gridSelectedIndex--);
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
              if (_cartSelectedIndex < _carrinho.length - 1) {
                _cartSelectedIndex++;
              }
            } else if (_focoNasCategorias) {
              _focoNasCategorias = false;
              _categoriaSelectedIndex = -1;
              _gridSelectedIndex = 0;
            } else if (_buscaFocusNode.hasFocus) {
              _focoNasCategorias = true;
              _categoriaSelectedIndex = 0;
              _gridSelectedIndex = -1;
              _cartSelectedIndex = -1;
              _atalhosFocusNode.requestFocus();
            } else {
              final maxItems = _termoBusca.isNotEmpty
                  ? _buscarItens(dataService).length
                  : (_categoriaAtiva != null
                        ? _getProdutosPorCategoria(dataService).length
                        : 0);

              if (_gridSelectedIndex < 0 && maxItems > 0) {
                _gridSelectedIndex = 0;
              } else if (_gridSelectedIndex + crossAxisCount < maxItems) {
                _gridSelectedIndex += crossAxisCount;
              } else if (_gridSelectedIndex >= 0 && _gridSelectedIndex + crossAxisCount >= maxItems) {
                // Se não tem próxima linha, talvez pular para o carrinho? Por enquanto vamos só manter no último
                if (_gridSelectedIndex < maxItems - 1) {
                   _gridSelectedIndex = maxItems - 1;
                }
              }
            }
          });
          return KeyEventResult.handled;
        }

        if (key == LogicalKeyboardKey.arrowUp) {
          setState(() {
            if (_focoNoCarrinho) {
              if (_cartSelectedIndex > 0) {
                _cartSelectedIndex--;
              }
            } else if (_focoNasCategorias) {
              _focoNasCategorias = false;
              _buscaFocusNode.requestFocus();
            } else {
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
          return KeyEventResult.handled;
        }

        // Enter - Adicionar ao carrinho ou Ações
        if (key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.numpadEnter) {
          if (_focoNasCategorias) {
            final index = _categoriaSelectedIndex;
            if (index == 0) {
              setState(() {
                _categoriaAtiva = null;
                _termoBusca = '';
                _buscaController.clear();
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
          if (!_focoNoCarrinho && _gridSelectedIndex >= 0) {
            final itens = _termoBusca.isNotEmpty
                ? _buscarItens(dataService)
                : (_categoriaAtiva != null
                      ? _getProdutosPorCategoria(dataService)
                      : []);
            if (_gridSelectedIndex < itens.length) {
              _adicionarAoCarrinho(itens[_gridSelectedIndex], manterFoco: true);
              return KeyEventResult.handled;
            }
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
                            colors: [
                              const Color(0xFF0D0D15),
                              const Color(0xFF12121C),
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
                        html.document.fullscreenElement == null
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
                                    color: const Color(0xFF0D0D15),
                                    borderRadius: BorderRadius.circular(20),
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
                          html.document.fullscreenElement == null
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

  Widget _buildBarraSuperior(DataService dataService) {
    final isSmallHeight = MediaQuery.of(context).size.height < 750;
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 800;

    // Elementos da barra
    final searchField = Expanded(
      flex: 3,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E2E),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.blue.withOpacity(0.3)),
        ),
        child: TextField(
          controller: _buscaController,
          focusNode: _buscaFocusNode,
          style: TextStyle(color: Colors.white, fontSize: isSmallHeight ? 14 : 15),
          decoration: InputDecoration(
            hintText: _categoriaAtiva != null ? '🔍 $_categoriaAtiva...' : '🔍 Buscar...',
            hintStyle: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: isSmallHeight ? 12 : 13),
            prefixIcon: GestureDetector(onTap: () => _abrirBuscaFacilitada(context), child: Icon(Icons.search, color: Colors.blue, size: isSmallHeight ? 18 : 22)),
            filled: true, fillColor: Colors.transparent, border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          ),
          onChanged: (value) => setState(() => _termoBusca = value),
        ),
      ),
    );

    final actionButtons = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildCompactHeaderButton(icon: Icons.person, label: _clienteSelecionado?.nome ?? 'Cliente', color: _clienteSelecionado != null ? Colors.greenAccent : Colors.white54, onTap: () => _selecionarCliente(dataService)),
          const SizedBox(width: 8),
          _buildCompactHeaderButton(
            icon: Icons.delivery_dining, 
            label: _isDelivery ? 'Entrega Ativa' : 'Entregas', 
            color: _isDelivery ? Colors.orangeAccent : Colors.white54, 
            onTap: () => _abrirDialogDelivery()
          ),
          const SizedBox(width: 8),
          _buildCompactHeaderButton(icon: Icons.history, label: 'Histórico', color: Colors.amber, onTap: () => _abrirHistoricoVendas()),
          const SizedBox(width: 8),
          _buildCompactHeaderButton(icon: Icons.assignment, label: 'Central', color: Colors.blueAccent, onTap: () => _abrirPedidos()),
          const SizedBox(width: 8),
          _buildCompactHeaderButton(icon: Icons.money_off, label: 'Despesa', color: Colors.redAccent, onTap: () => _abrirLancamentoDespesa()),
        ],
      ),
    );

    return Container(
      padding: EdgeInsets.fromLTRB(16, isSmallHeight ? 4 : 8, 16, isSmallHeight ? 4 : 8),
      child: isMobile 
        ? Column(
            children: [
              Row(
                children: [
                  _buildBotaoMapaMesas(dataService, compact: true),
                  const SizedBox(width: 4),
                  _buildBotaoComandas(dataService, compact: true),
                  const SizedBox(width: 4),
                  _buildBotaoCozinha(dataService, compact: true),
                  const SizedBox(width: 8),
                  searchField,
                ],
              ),
              const SizedBox(height: 8),
              actionButtons,
            ],
          )
        : Row(
            children: [
              _buildBotaoMapaMesas(dataService, compact: true),
              const SizedBox(width: 4),
              _buildBotaoComandas(dataService, compact: true),
              const SizedBox(width: 4),
              _buildBotaoCozinha(dataService, compact: true),
              const SizedBox(width: 8),
              if (_mesaComandaVinculada != null) ...[
                _buildBadgeVinculoHeader(),
                const SizedBox(width: 8),
              ],
              searchField,
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
                    // Botão "Todos"
                    final isActive =
                        _categoriaAtiva == null && _termoBusca.isEmpty;
                    final isSelected =
                        _focoNasCategorias && _categoriaSelectedIndex == 0;
                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          _categoriaAtiva = null;
                          _termoBusca = '';
                          _buscaController.clear();
                          _focoNasCategorias = true;
                          _categoriaSelectedIndex = 0;
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

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0D15),
        border: Border(top: BorderSide(color: Colors.white.withOpacity(0.05))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
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
                  // Se pressionar Enter na descrição, verificar se pode adicionar
                  final descricao = value.trim();
                  if (descricao.isEmpty) {
                    return; // Não fazer nada se descrição estiver vazia
                  }

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
                  // Ao pressionar Enter no preço, adicionar o item
                  final descricao = descricaoController.text.trim();
                  final preco =
                      double.tryParse(value.replaceAll(',', '.')) ?? 0.0;

                  if (descricao.isEmpty) {
                    // Se não tem descrição, focar nela
                    focusNodeDescricao.requestFocus();
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      const SnackBar(
                        content: Text('Informe a descrição'),
                        backgroundColor: Colors.red,
                      ),
                    );
                    return;
                  }

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
              final descricao = descricaoController.text.trim();
              final preco =
                  double.tryParse(precoController.text.replaceAll(',', '.')) ??
                  0.0;

              if (descricao.isEmpty) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(
                    content: Text('Informe a descrição'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }

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
  ) {
    // Adicionar ao carrinho
    final id = '${produtoDiversos.id}-${DateTime.now().millisecondsSinceEpoch}';
    final nome = 'Diversos: $descricao';

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
            descricao: descricao,
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
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final isVerySmallHeight = screenHeight < 650;
    final isSmallHeight = screenHeight < 750;

    // Mais colunas para caber mais produtos
    int crossAxisCount = 3;
    if (screenWidth >= 1600) {
      crossAxisCount = 6;
    } else if (screenWidth >= 1200) {
      crossAxisCount = 5;
    } else if (screenWidth >= 900) {
      crossAxisCount = 4;
    }

    // Aspect ratio mais compacto para economizar espaço
    final aspectRatio = isVerySmallHeight ? 2.0 : (isSmallHeight ? 1.8 : 1.6);

    return GridView.builder(
      padding: const EdgeInsets.all(4),
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
    );
  }

  Widget _buildGridProdutos(List<Produto> produtos) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final isVerySmallHeight = screenHeight < 650;
    final isSmallHeight = screenHeight < 750;

    // Mais colunas para caber mais produtos
    int crossAxisCount = 3;
    if (screenWidth >= 1600) {
      crossAxisCount = 6;
    } else if (screenWidth >= 1200) {
      crossAxisCount = 5;
    } else if (screenWidth >= 900) {
      crossAxisCount = 4;
    }
    
    final aspectRatio = isVerySmallHeight ? 2.0 : (isSmallHeight ? 1.8 : 1.6);

    return GridView.builder(
      padding: const EdgeInsets.all(4),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        childAspectRatio: aspectRatio,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
      ),
      itemCount: produtos.length,
      itemBuilder: (context, index) {
        return _buildCardProduto(produtos[index], true, index: index);
      },
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

    // Se for o produto Diversos (código 9999), abrir diálogo para descrição
    final isDiversos = isProduto && codigo == '9999';

    final screenHeight = MediaQuery.of(context).size.height;
    final isSmallHeight = screenHeight < 750;
    final isSelected =
        !_focoNoCarrinho && _gridSelectedIndex == index && index != -1;

    return GestureDetector(
      onTap: () {
        setState(() {
          _focoNoCarrinho = false;
          _gridSelectedIndex = index;
        });
        if (isDiversos) {
          // Verificar se o termo de busca é um número (preço)
          final valorDigitado = double.tryParse(
            _termoBusca.replaceAll(',', '.').trim(),
          );
          _lancarDiversosRapido(precoInicial: valorDigitado);
        } else {
          _adicionarAoCarrinho(item, manterFoco: true);
        }
      },
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isProduto
                ? [const Color(0xFF1E3A5F), const Color(0xFF2C3E50)]
                : [const Color(0xFF4A1E5F), const Color(0xFF3E2C50)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(isSmallHeight ? 10 : 12),
          border: Border.all(
            color: isSelected
                ? Colors.cyanAccent
                : (promocao
                      ? Colors.orange.withOpacity(0.5)
                      : Colors.transparent),
            width: isSelected ? 3 : 2,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.cyanAccent.withOpacity(0.3),
                    blurRadius: 15,
                    spreadRadius: 2,
                  ),
                ]
              : null,
        ),
        child: Padding(
          padding: const EdgeInsets.all(5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Código + ícone
              Row(
                children: [
                  Icon(
                    isProduto ? Icons.inventory_2 : Icons.build,
                    color: isProduto
                        ? Colors.lightBlueAccent
                        : Colors.purpleAccent,
                    size: 14,
                  ),
                  const SizedBox(width: 4),
                  if (codigo != null && codigo.isNotEmpty)
                    Flexible(
                      child: Text(
                        codigo,
                        style: const TextStyle(
                          color: Colors.white70,
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
                            : Colors.white.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: (estoque <= 0) 
                              ? Colors.redAccent.withOpacity(0.5) 
                              : Colors.white10,
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.inventory_2_outlined,
                            size: 8,
                            color: (estoque <= 0) ? Colors.redAccent : Colors.white54,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            estoque.toStringAsFixed(0),
                            style: TextStyle(
                              color: (estoque <= 0) ? Colors.redAccent : Colors.white70,
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
                    color: Colors.greenAccent.withOpacity(0.6),
                    size: 18,
                  ),
                ],
              ),
              const Spacer(),
              // Nome - destaque principal
              Text(
                nome.toUpperCase(),
                style: TextStyle(
                  color: Colors.yellow.shade200,
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                  height: 1.1,
                  letterSpacing: 0.3,
                  shadows: const [
                    Shadow(
                      color: Colors.black87,
                      blurRadius: 3,
                      offset: Offset(0, 1),
                    ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              // Preço
              Text(
                'R\$ ${preco.toStringAsFixed(2)}',
                style: TextStyle(
                  color: promocao ? Colors.orange : Colors.greenAccent,
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                ),
              ),
            ],
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
                  color: Colors.white.withOpacity(0.9),
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
                  color: Colors.cyanAccent.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.cyanAccent.withOpacity(0.4),
                      blurRadius: 10,
                      spreadRadius: 1,
                    ),
                    BoxShadow(
                      color: Colors.cyanAccent.withOpacity(0.2),
                      blurRadius: 20,
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Text(
                      '$_totalItens',
                      style: const TextStyle(
                        color: Colors.cyanAccent,
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _totalItens == 1 ? 'ITEM' : 'ITENS',
                      style: const TextStyle(
                        color: Colors.cyanAccent,
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
                        color: Colors.white.withOpacity(0.15),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Carrinho vazio',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.4),
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Adicione produtos para começar',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.25),
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
                          onRemover: () => _removerItem(reversedIndex),
                          onRemoverDescontoDirect: () {
                            setState(() {
                              _carrinho[reversedIndex].desconto = 0.0;
                            });
                            _salvarCarrinho();
                          },
                          onDarBaixa: () => _darBaixaEstoqueItem(reversedIndex),
                          onAdicionarObservacao: () => _adicionarObservacaoItem(reversedIndex),
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
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'DESCONTO TOTAL',
                                style: TextStyle(
                                  color: Colors.orangeAccent,
                                  fontSize: isVerySmallHeight ? 8 : 10,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1,
                                ),
                              ),
                              Row(
                                children: [
                                  Text(
                                    '- R\$ ${_descontoTotal.toStringAsFixed(2)}',
                                    style: TextStyle(
                                      color: Colors.orangeAccent,
                                      fontSize: isVerySmallHeight ? 9 : 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  GestureDetector(
                                    onTap: () {
                                       setState(() {
                                         _descontoTotal = 0.0;
                                       });
                                       _storage.salvar(_keyDescontoTotalPDV, 0.0);
                                    },
                                    child: Icon(
                                      Icons.close_rounded,
                                      color: Colors.orangeAccent.withOpacity(0.5),
                                      size: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ],
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
                        if (_descontoTotal == 0) ...[
                          const SizedBox(height: 8),
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
                        ],
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
                                  ? Colors.white.withOpacity(0.05)
                                  : Colors.orange.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(10),
                              boxShadow: _carrinho.isEmpty
                                  ? null
                                  : [
                                      BoxShadow(
                                        color: Colors.orange.withOpacity(0.3),
                                        blurRadius: 12,
                                      ),
                                    ],
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.bookmark_add_rounded,
                                  color: _carrinho.isEmpty
                                      ? Colors.white.withOpacity(0.2)
                                      : Colors.orange,
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'SALVAR',
                                  style: TextStyle(
                                    color: _carrinho.isEmpty
                                        ? Colors.white.withOpacity(0.2)
                                        : Colors.orange,
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
                                        Colors.greenAccent.withOpacity(0.3),
                                        Colors.green.withOpacity(0.3),
                                      ],
                                    ),
                              color: _carrinho.isEmpty
                                  ? Colors.white.withOpacity(0.05)
                                  : null,
                              borderRadius: BorderRadius.circular(10),
                              boxShadow: _carrinho.isEmpty
                                  ? null
                                  : [
                                      BoxShadow(
                                        color: Colors.greenAccent.withOpacity(
                                          0.4,
                                        ),
                                        blurRadius: 15,
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
                                      ? Colors.white.withOpacity(0.2)
                                      : Colors.greenAccent,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'FINALIZAR',
                                  style: TextStyle(
                                    color: _carrinho.isEmpty
                                        ? Colors.white.withOpacity(0.2)
                                        : Colors.greenAccent,
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
  final int quantidade;
  final int quantidadeTotal;
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
                                ? 'Qtd Total: ${widget.quantidadeTotal}'
                                : 'Quantidade: ${widget.quantidade}',
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
  final VoidCallback onRemover;
  final VoidCallback onRemoverDescontoDirect;
  final VoidCallback onDarBaixa;
  final VoidCallback onAdicionarObservacao;

  const _ItemCarrinhoComHover({
    required this.item,
    required this.index,
    required this.onAlterarQuantidade,
    required this.onAplicarDesconto,
    required this.onRemover,
    required this.onRemoverDescontoDirect,
    required this.onDarBaixa,
    required this.onAdicionarObservacao,
  });

  @override
  State<_ItemCarrinhoComHover> createState() => _ItemCarrinhoComHoverState();
}

class _ItemCarrinhoComHoverState extends State<_ItemCarrinhoComHover> {
  OverlayEntry? _overlayEntry;
  final GlobalKey _itemKey = GlobalKey();

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
    final item = widget.item;
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
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(isSmallHeight ? 12 : 16),
          border: Border.all(color: Colors.white.withOpacity(0.03)),
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
                    color: corBackground.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    item.isServico
                        ? Icons.build_rounded
                        : Icons.inventory_2_rounded,
                    color: corPrincipal.withOpacity(0.8),
                    size: isSmallHeight ? 16 : 20,
                  ),
                ),
                SizedBox(width: isSmallHeight ? 8 : 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.nome,
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: isSmallHeight ? 14 : 16,
                          height: 1.2,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
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
                                  Icon(Icons.add_circle_outline, color: Colors.greenAccent.withOpacity(0.5), size: 10),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      '${a.nome} (+ R\$ ${a.preco.toStringAsFixed(2)})',
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.5),
                                        fontSize: 10,
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
                    color: Colors.white.withOpacity(0.25),
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
                            color: Colors.white.withOpacity(0.7),
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
                    color: Colors.black.withOpacity(0.2),
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
                            color: Colors.white.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            Icons.remove_rounded,
                            color: item.quantidade > 1
                                ? Colors.white70
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
                            color: Colors.white,
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
                            color: corPrincipal.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            Icons.add_rounded,
                            color: corPrincipal,
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
                          : Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.discount_rounded,
                      color: item.desconto > 0
                          ? Colors.orangeAccent
                          : Colors.white30,
                      size: isSmallHeight ? 12 : 14,
                    ),
                  ),
                ),
                SizedBox(width: isSmallHeight ? 4 : 8),
                // Botão de Observações
                GestureDetector(
                  onTap: widget.onAdicionarObservacao,
                  child: Container(
                    padding: EdgeInsets.all(isSmallHeight ? 6 : 8),
                    decoration: BoxDecoration(
                      color: (item.observacao != null && item.observacao!.isNotEmpty)
                          ? Colors.blue.withOpacity(0.15)
                          : Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.notes_rounded,
                      color: (item.observacao != null && item.observacao!.isNotEmpty)
                          ? Colors.blueAccent
                          : Colors.white30,
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
                    Text(
                      'R\$ ${item.subtotal.toStringAsFixed(2)}',
                      style: TextStyle(
                        color: corPrincipal,
                        fontWeight: FontWeight.w900,
                        fontSize: isSmallHeight ? 14 : 16,
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

  @override
  Widget build(BuildContext context) {
    final clientes = _clientesFiltrados;

    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
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
  final Function(List<PagamentoPedido>) onConfirmar;
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
  int _selectedPaymentIndex = -1; // índice do pagamento selecionado na lista
  late TextEditingController _cpfController;
  late TextEditingController _nomeController;

  @override
  void initState() {
    super.initState();
    _pagamentos = List.from(widget.pagamentosIniciais);
    _cpfController = TextEditingController(text: widget.cpfCnpjInicial);
    _nomeController = TextEditingController(text: widget.nomeInicial);
    _focusNode.requestFocus();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _cpfController.dispose();
    _nomeController.dispose();
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

    final valorSugerido = _valorRestante > 0 ? _valorRestante : 0.0;

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

    _mostrarDialogPagamento(tipo, valorSugerido);
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
            widget.onConfirmar(_pagamentos);
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
                    children: TipoPagamento.values.asMap().entries.map((entry) {
                      final index = entry.key;
                      final tipo = entry.value;
                      final shortcut = index + 1;

                      return GestureDetector(
                        onTap: () => _adicionarPagamento(tipo),
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
                            widget.onConfirmar(_pagamentos);
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
  late AnimationController _moneyController;
  late Animation<double> _scaleAnimation;
  final List<_DinheiroAnimado> _dinheiros = [];
  final math.Random _random = math.Random();
  
  // Foco para botões
  final FocusNode _fecharNode = FocusNode();
  final FocusNode _nfceNode = FocusNode();

  @override
  void initState() {
    super.initState();

    // Animação de escala do popup
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _scaleAnimation = CurvedAnimation(
      parent: _scaleController,
      curve: Curves.elasticOut,
    );

    // Animação de dinheiro caindo
    _moneyController = AnimationController(
      duration: const Duration(milliseconds: 2500),
      vsync: this,
    );

    // Gerar notas de dinheiro
    for (int i = 0; i < 20; i++) {
      _dinheiros.add(
        _DinheiroAnimado(
          x: _random.nextDouble(),
          delay: _random.nextDouble() * 0.5,
          speed: 0.5 + _random.nextDouble() * 0.5,
          rotation: _random.nextDouble() * 2 * math.pi,
          rotationSpeed: (_random.nextDouble() - 0.5) * 4,
          size: 24 + _random.nextDouble() * 16,
        ),
      );
    }

    _scaleController.forward();
    _moneyController.repeat();

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

  @override
  void dispose() {
    _scaleController.dispose();
    _moneyController.dispose();
    _fecharNode.dispose();
    _nfceNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

    return KeyboardListener(
      focusNode: FocusNode(), // Capturar teclas globalmente no popup
      onKeyEvent: (event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.enter || 
              event.logicalKey == LogicalKeyboardKey.numpadEnter) {
            // Enter aciona o botão focado
            if (_nfceNode.hasFocus) {
              _emitir();
            } else {
              _fechar();
            }
          } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            // Seta esquerda move para NFC-e se existir
            if (widget.onEmitirNFCe != null) {
              _nfceNode.requestFocus();
            }
          } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
            // Seta direita volta para Fechar
            _fecharNode.requestFocus();
          } else if (event.logicalKey == LogicalKeyboardKey.escape) {
            _fechar();
          }
        }
      },
      child: Material(
        color: Colors.transparent,
        child: Stack(
          children: [
          // Dinheiro caindo por trás
          ...List.generate(_dinheiros.length, (index) {
            final dinheiro = _dinheiros[index];
            return AnimatedBuilder(
              animation: _moneyController,
              builder: (context, child) {
                final progress =
                    (_moneyController.value - dinheiro.delay).clamp(0.0, 1.0) *
                    dinheiro.speed;
                final y =
                    -50 +
                    (progress * (MediaQuery.of(context).size.height + 100));
                final rotation =
                    dinheiro.rotation +
                    (_moneyController.value * dinheiro.rotationSpeed);
                final opacity = progress < 0.1
                    ? progress * 10
                    : progress > 0.8
                    ? (1 - progress) * 5
                    : 1.0;

                return Positioned(
                  left: dinheiro.x * MediaQuery.of(context).size.width,
                  top: y,
                  child: Opacity(
                    opacity: opacity.clamp(0.0, 1.0),
                    child: Transform.rotate(
                      angle: rotation,
                      child: Text(
                        '💵',
                        style: TextStyle(fontSize: dinheiro.size),
                      ),
                    ),
                  ),
                );
              },
            );
          }),

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
                          child: Opacity(opacity: value, child: child),
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
                            onPressed: () {
                              Navigator.pop(context);
                              widget.onWhatsApp?.call();
                            },
                            icon: const Icon(Icons.chat_bubble_outline, size: 20),
                            label: const Text('WhatsApp'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF25D366),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                          ),

                        if (widget.onWhatsApp != null)
                          const SizedBox(width: 16),
                        
                        // Botão Imprimir Cupom Simples
                        if (widget.onImprimir != null)
                          ElevatedButton.icon(
                            onPressed: () {
                              widget.onImprimir?.call();
                            },
                            icon: const Icon(Icons.print_rounded, size: 20),
                            label: const Text(
                              'Imprimir',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white.withOpacity(0.9),
                              foregroundColor: Colors.blue.shade800,
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
  int _selectedIndex = 0;
  final ScrollController _scrollController = ScrollController();
  final NumberFormat _formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

  double get _totalCarrinho => widget.carrinho.fold(0.0, (sum, item) => sum + item.subtotalSemDesconto);
  int get _totalItens => widget.carrinho.fold(0, (sum, item) => sum + item.quantidade);

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
                                '${item.quantidade}x',
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

