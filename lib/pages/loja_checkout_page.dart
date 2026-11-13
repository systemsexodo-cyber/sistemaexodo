import 'package:flutter/material.dart';
import 'html_helper_stub.dart' if (dart.library.html) 'html_helper_web.dart' as html_helper;
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:provider/provider.dart';
import 'package:sistema_exodo_novo/models/carrinho_item.dart';
import 'package:sistema_exodo_novo/models/link_vendedor.dart';
import 'package:sistema_exodo_novo/models/empresa.dart';
import 'package:sistema_exodo_novo/services/nfce_service.dart';
import 'package:sistema_exodo_novo/models/pedido.dart';
import 'package:sistema_exodo_novo/models/item_pedido.dart';
import 'package:sistema_exodo_novo/models/item_servico.dart';
import 'package:sistema_exodo_novo/models/cliente.dart';
import 'package:sistema_exodo_novo/models/endereco_cliente.dart';
import 'package:sistema_exodo_novo/models/comissao_vendedor.dart';
import 'package:sistema_exodo_novo/models/produto.dart';
import 'package:sistema_exodo_novo/models/forma_pagamento.dart';
import 'package:sistema_exodo_novo/models/delivery_info.dart';
import 'package:sistema_exodo_novo/models/entrega.dart';
import 'package:sistema_exodo_novo/services/data_service.dart';
import 'package:sistema_exodo_novo/services/auth_service.dart';
import 'package:sistema_exodo_novo/services/cliente_auth_service.dart';
import 'package:sistema_exodo_novo/services/frete_service.dart';
import 'package:sistema_exodo_novo/services/horario_loja_service.dart';
import 'package:sistema_exodo_novo/models/opcao_frete.dart';
import 'package:sistema_exodo_novo/models/zona_entrega.dart';
import 'package:sistema_exodo_novo/pages/cliente_cadastro_page.dart';
import 'package:sistema_exodo_novo/theme.dart';
import 'package:sistema_exodo_novo/services/carrinho_service.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'package:url_launcher/url_launcher.dart';

class LojaCheckoutPage extends StatefulWidget {
  final LinkVendedor? linkVendedor;
  final OpcaoFrete? opcaoFreteInicial;

  const LojaCheckoutPage({
    super.key,
    this.linkVendedor,
    this.opcaoFreteInicial,
  });

  @override
  State<LojaCheckoutPage> createState() => _LojaCheckoutPageState();
}

class _LojaCheckoutPageState extends State<LojaCheckoutPage> {
  final _formKey = GlobalKey<FormState>();
  final _nomeController = TextEditingController();
  final _telefoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _cpfController = TextEditingController();
  final _enderecoController = TextEditingController();
  final _numeroController = TextEditingController();
  final _complementoController = TextEditingController();
  final _bairroController = TextEditingController();
  final _cidadeController = TextEditingController();
  final _estadoController = TextEditingController();
  final _cepController = TextEditingController();
  final _observacoesController = TextEditingController();

  Cliente? _clienteEncontradoTelefone;
  bool _buscandoClienteTelefone = false;
  int _sequenciaBuscaTelefone = 0;

  bool _isLoading = false;
  bool _buscandoCep = false;
  bool _calculandoFrete = false;
  double _valorFrete = 0.0;
  int _prazoFrete = 0; // Prazo em dias Ãºteis
  bool _freteCalculado = false;
  String? _estadoLoja;
  String? _cepLoja;
  String? _bairroLoja;
  String? _cidadeLoja;
  List<OpcaoFrete> _opcoesFrete = [];
  OpcaoFrete? _opcaoFreteSelecionada;

  /// Retirada na loja Ã© o padrÃ£o: garante que o cliente consiga concluir o pedido mesmo quando a loja nÃ£o tem frete/transportadora configurada.
  bool _retiradaNaLoja = true;
  TipoPagamento _tipoPagamento = TipoPagamento.pix;
  @override
  void initState() {
    super.initState();
    _retiradaNaLoja = widget.opcaoFreteInicial == null;
    _carregarDadosLoja();
    _carregarDadosCliente();

    // Inicializar frete se houver uma opÃ§Ã£o inicial
    if (widget.opcaoFreteInicial != null) {
      _opcaoFreteSelecionada = widget.opcaoFreteInicial;
      _valorFrete = widget.opcaoFreteInicial!.valor;
      _prazoFrete = widget.opcaoFreteInicial!.prazo;
      _freteCalculado = true;
      _opcoesFrete = [widget.opcaoFreteInicial!];
    }
  }

  void _carregarDadosLoja() {
    final authService = Provider.of<AuthService>(context, listen: false);
    final empresa = authService.empresaAtual;
    if (empresa != null) {
      setState(() {
        _estadoLoja = empresa.estado;
        _cepLoja = empresa.cep;
        _bairroLoja = empresa.bairro;
        _cidadeLoja = empresa.cidade;
        // Abre jÃ¡ na primeira forma liberada pela loja (PIX por padrÃ£o).
        _tipoPagamento = _formasPagamentoDisponiveis.first;
      });
    }
  }

  bool _clienteLogado = false;

  /// Carrega dados do cliente logado e preenche os campos automaticamente
  void _carregarDadosCliente() {
    final clienteAuthService = Provider.of<ClienteAuthService>(context, listen: false);
    final cliente = clienteAuthService.clienteAtual;
    
    setState(() {
      _clienteLogado = cliente != null;
    });
    
    if (cliente != null) {
      _clienteEncontradoTelefone = cliente;
      // Preencher campos automaticamente com dados do cliente logado
      _nomeController.text = cliente.nome;
      _telefoneController.text = cliente.telefone;
      _emailController.text = cliente.email ?? '';
      _cpfController.text = cliente.cpfCnpj ?? '';
      _enderecoController.text = cliente.endereco ?? '';
      _numeroController.text = cliente.numero ?? '';
      _complementoController.text = cliente.complemento ?? '';
      _bairroController.text = cliente.bairro ?? '';
      _cidadeController.text = cliente.cidade ?? '';
      _estadoController.text = cliente.estado ?? '';
      _cepController.text = cliente.cep ?? '';
      
      // Calcular frete automaticamente se tiver CEP e a entrega estiver marcada
      if (!_retiradaNaLoja &&
          cliente.cep != null &&
          cliente.cep!.replaceAll(RegExp(r'[^\d]'), '').length == 8) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _calcularFrete();
        });
      }
    }
  }

  /// Navega para pÃ¡gina de cadastro e retorna com dados preenchidos

  /// Procura o cadastro existente pelo telefone e reaproveita o mesmo cliente.
  Future<void> _buscarClientePeloTelefone(String valor) async {
    if (_clienteLogado) { return; }
    final digitos = valor.replaceAll(RegExp(r'\D'), '');
    final sequencia = ++_sequenciaBuscaTelefone;
    if (mounted) {
      setState(() {
        _clienteEncontradoTelefone = null;
        _buscandoClienteTelefone = digitos.length >= 10;
      });
    }
    if (digitos.length < 10) { return; }
    await Future.delayed(const Duration(milliseconds: 350));
    if (!mounted) { return; }
    if (sequencia != _sequenciaBuscaTelefone ||
        _telefoneController.text.replaceAll(RegExp(r'\D'), '') != digitos) {
      return;
    }
    setState(() => _buscandoClienteTelefone = true);
    try {
      final dataService = Provider.of<DataService>(context, listen: false);
      final encontrados = await dataService.buscarClientePorTelefone(digitos);
      if (!mounted) { return; }
      if (sequencia != _sequenciaBuscaTelefone) { return; }
      final cliente = encontrados.isEmpty ? null : encontrados.first;
      setState(() {
        _clienteEncontradoTelefone = cliente;
        _buscandoClienteTelefone = false;
      });
      if (cliente == null) { return; }
      _nomeController.text = cliente.nome;
      if ((cliente.email ?? '').isNotEmpty) _emailController.text = cliente.email!;
      if ((cliente.cpfCnpj ?? '').isNotEmpty) _cpfController.text = cliente.cpfCnpj!;
      var logradouro = cliente.endereco;
      var numero = cliente.numero;
      var complemento = cliente.complemento;
      var bairro = cliente.bairro;
      var cidade = cliente.cidade;
      var estado = cliente.estado;
      var cep = cliente.cep;
      if ((logradouro ?? '').trim().isEmpty && cliente.enderecos.isNotEmpty) {
        final salvo = cliente.enderecos.firstWhere(
          (e) => e.isDefault,
          orElse: () => cliente.enderecos.first,
        );
        logradouro = salvo.logradouro;
        numero = salvo.numero;
        complemento = salvo.complemento;
        bairro = salvo.bairro;
        cidade = salvo.cidade;
        estado = salvo.uf;
        cep = salvo.cep;
      }
      _enderecoController.text = logradouro ?? '';
      _numeroController.text = numero ?? '';
      _complementoController.text = complemento ?? '';
      _bairroController.text = bairro ?? '';
      _cidadeController.text = cidade ?? '';
      _estadoController.text = estado ?? '';
      _cepController.text = cep ?? '';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Cadastro encontrado: ${cliente.nome}. Dados preenchidos.')),
      );
    } catch (e) {
      if (mounted && sequencia == _sequenciaBuscaTelefone) {
        setState(() => _buscandoClienteTelefone = false);
        debugPrint('Erro ao localizar cliente pelo telefone: $e');
      }
    }
  }

  Future<void> _irParaCadastro() async {
    final resultado = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => const ClienteCadastroPage(),
      ),
    );

    if (resultado == true) {
      // Recarregar dados do cliente apÃ³s cadastro
      _carregarDadosCliente();
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Conta criada com sucesso! Seus dados foram preenchidos automaticamente.'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  void dispose() {
    _nomeController.dispose();
    _telefoneController.dispose();
    _emailController.dispose();
    _cpfController.dispose();
    _enderecoController.dispose();
    _numeroController.dispose();
    _complementoController.dispose();
    _bairroController.dispose();
    _cidadeController.dispose();
    _estadoController.dispose();
    _cepController.dispose();
    _observacoesController.dispose();
    super.dispose();
  }

  double _calcularTotal() {
    final carrinhoService = Provider.of<CarrinhoService>(context, listen: false);
    return carrinhoService.valorTotal;
  }

  Map<String, dynamic>? get _configEcommerce {
    final empresa = Provider.of<AuthService>(context, listen: false).empresaAtual;
    final config = empresa?.configuracoes?['ecommerce'];
    return config is Map<String, dynamic> ? config : null;
  }

  bool get _descontoPixAtivo =>
      _configEcommerce?['descontoPixAtivo'] as bool? ?? true;

  double get _percentualDescontoPix =>
      (_configEcommerce?['percentualDescontoPix'] as num?)?.toDouble() ?? 5.0;

  /// Formas de pagamento que a loja liberou em Personalizar Loja > Pagamento.
  /// Se nada foi configurado, usa a lista padrÃ£o do e-commerce. Nunca fica
  /// vazia: sem nenhuma marcada, o cliente ainda consegue pagar com PIX.
  List<TipoPagamento> get _formasPagamentoDisponiveis {
    final configuradas = _configEcommerce?['formasPagamentoLoja'];
    final nomes = configuradas is List
        ? configuradas.map((e) => e.toString()).toList()
        : formasPagamentoLojaPadrao;
    final tipos = TipoPagamento.values
        .where((tipo) => nomes.contains(tipo.name))
        .toList();
    return tipos.isEmpty ? const [TipoPagamento.pix] : tipos;
  }

  double _calcularDescontoPix() {
    if (!_descontoPixAtivo || _tipoPagamento != TipoPagamento.pix) return 0.0;
    final desconto = _calcularTotal() * (_percentualDescontoPix / 100);
    return desconto > 0 ? desconto : 0.0;
  }

  double _calcularTotalComFrete() {
    final frete = _retiradaNaLoja
        ? 0.0
        : (_opcaoFreteSelecionada?.valor ?? _valorFrete);
    return (_calcularTotal() - _calcularDescontoPix()) + frete;
  }

  String _enderecoLojaFormatado() {
    final empresa = Provider.of<AuthService>(context, listen: false).empresaAtual;
    if (empresa == null) return '';
    final partes = <String?>[
      empresa.endereco,
      empresa.numero,
      empresa.complemento,
      empresa.bairro,
      empresa.cidade,
      empresa.estado,
      empresa.cep,
    ].where((p) => p != null && p.trim().isNotEmpty).cast<String>();
    return partes.join(', ');
  }

  String? _normalizarTelefone(String? valor) {
    var digitos = (valor ?? '').replaceAll(RegExp(r'\D'), '');
    if (digitos.isEmpty) return null;
    if (digitos.startsWith('0')) digitos = digitos.substring(1);
    if (!digitos.startsWith('55')) digitos = '55$digitos';
    if (digitos.length < 12 || digitos.length > 15) return null;
    return digitos;
  }

  String? _telefoneLoja() {
    final empresa = Provider.of<AuthService>(context, listen: false).empresaAtual;
    final config = _configEcommerce;
    final candidatos = <String?>[
      config?['whatsapp']?.toString(),
      empresa?.celular,
      empresa?.telefone,
    ];
    for (final candidato in candidatos) {
      final normalizado = _normalizarTelefone(candidato);
      if (normalizado != null) return normalizado;
    }
    return null;
  }

  double _calcularPesoTotal() {
    final dataService = Provider.of<DataService>(context, listen: false);
    final carrinhoService = Provider.of<CarrinhoService>(context, listen: false);
    double pesoTotal = 0.0;
    
    for (var item in carrinhoService.itens) {
      if (item.isProduto) {
        final produto = dataService.produtos.firstWhere(
          (p) => p.id == item.itemId,
          orElse: () => Produto(
            id: '',
            nome: '',
            unidade: '',
            grupo: '',
            preco: 0,
            estoque: 0,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        );
        final pesoProduto = produto.pesoGramas ?? 500; // Peso padrÃ£o 500g
        pesoTotal += pesoProduto * item.quantidade;
      }
    }
    
    return pesoTotal;
  }

  Future<void> _buscarCEP() async {
    final cep = _cepController.text.replaceAll(RegExp(r'[^\d]'), '');
    if (cep.length != 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('CEP deve ter 8 dÃ­gitos'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _buscandoCep = true);

    try {
      final endereco = await FreteService.buscarEnderecoPorCEP(cep);
      
      setState(() {
        _enderecoController.text = endereco['endereco'] ?? '';
        _bairroController.text = endereco['bairro'] ?? '';
        _cidadeController.text = endereco['cidade'] ?? '';
        _estadoController.text = endereco['estado'] ?? '';
        _cepController.text = endereco['cep'] ?? '';
        _buscandoCep = false;
      });

      // Calcular frete automaticamente apÃ³s buscar CEP
      if (_estadoController.text.isNotEmpty && _estadoLoja != null) {
        _calcularFrete();
      }
    } catch (e) {
      setState(() => _buscandoCep = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao buscar CEP: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _calcularFrete() async {
    if (_retiradaNaLoja) return;
    if (_estadoController.text.isEmpty || _estadoLoja == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Preencha o estado (UF) para calcular o frete'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    setState(() {
      _calculandoFrete = true;
      _freteCalculado = false;
      _opcoesFrete = [];
      _opcaoFreteSelecionada = null;
    });

    try {
      final pesoTotal = _calcularPesoTotal();
      final valorPedido = _calcularTotal();
      final dataService = Provider.of<DataService>(context, listen: false);
      final authService = Provider.of<AuthService>(context, listen: false);
      
      // Obter valor mÃ­nimo para frete grÃ¡tis da configuraÃ§Ã£o
      final empresa = authService.empresaAtual;
      final valorMinimoFreteGratis = empresa?.configuracoes?['ecommerce']?['valorFreteGratis'] as num? ?? 399.90;

      // Limpar CEPs para garantir formato correto
      final cepDestinoLimpo = _cepController.text.replaceAll(RegExp(r'[^\d]'), '');
      
      // Obter configuraÃ§Ãµes de frete do e-commerce
      final configFrete = empresa?.configuracoes?['ecommerce']?['frete'] as Map<String, dynamic>?;
      
      // Carregar Zonas de Entrega Inteligentes
      final zonasData = configFrete?['zonasEntrega'] as List<dynamic>? ?? [];
      final zonasEntrega = zonasData
          .map((z) => ZonaEntrega.fromMap(z as Map<String, dynamic>))
          .toList();
      
      // Configurar credenciais das transportadoras (se disponÃ­veis)
      FreteService.configurarCorreios(
        codigoEmpresa: configFrete?['correiosCodigo'] as String?,
        senha: configFrete?['correiosSenha'] as String?,
      );
      FreteService.configurarCredenciaisTransportadoras(
        jadlogToken: configFrete?['jadlogToken'] as String?,
        totalExpressToken: configFrete?['totalExpressToken'] as String?,
        azulCargoToken: configFrete?['azulCargoToken'] as String?,
        loggiToken: configFrete?['loggiToken'] as String?,
        melhorEnvioToken: configFrete?['melhorEnvioToken'] as String?,
        melhorEnvioEmail: configFrete?['melhorEnvioEmail'] as String?,
      );
      
      // Calcular todas as opÃ§Ãµes de frete (SISTEMA HÃBRIDO)
      final opcoes = await FreteService.calcularOpcoesFrete(
        estadoOrigem: _estadoLoja!,
        estadoDestino: _estadoController.text.trim().toUpperCase(),
        pesoTotal: pesoTotal,
        valorPedido: valorPedido,
        cepOrigem: _cepLoja != null && _cepLoja!.replaceAll(RegExp(r'[^\d]'), '').length == 8
            ? _cepLoja!.replaceAll(RegExp(r'[^\d]'), '')
            : null,
        cepDestino: cepDestinoLimpo.length == 8 ? cepDestinoLimpo : null,
        bairroOrigem: _bairroLoja,
        cidadeOrigem: _cidadeLoja,
        bairroDestino: _bairroController.text.trim().isNotEmpty ? _bairroController.text.trim() : null,
        cidadeDestino: _cidadeController.text.trim().isNotEmpty ? _cidadeController.text.trim() : null,
        taxasEntrega: dataService.taxasEntrega,
        valorMinimoFreteGratis: valorMinimoFreteGratis.toDouble(),
        configFrete: configFrete,
        zonasEntrega: zonasEntrega.isNotEmpty ? zonasEntrega : null,
      );

      if (mounted) {
        debugPrint('>>> [Checkout] OpÃ§Ãµes de frete calculadas: ${opcoes.length}');
        for (var opcao in opcoes) {
          debugPrint('>>> [Checkout] - ${opcao.nome}: R\$ ${opcao.valor.toStringAsFixed(2)} (${opcao.prazo} dias)');
        }
        
        setState(() {
          _opcoesFrete = opcoes;
          // Selecionar automaticamente a primeira opÃ§Ã£o (geralmente a mais barata)
          if (opcoes.isNotEmpty) {
            _opcaoFreteSelecionada = opcoes.first;
            _valorFrete = opcoes.first.valor;
            _prazoFrete = opcoes.first.prazo;
            debugPrint('>>> [Checkout] OpÃ§Ã£o selecionada: ${opcoes.first.nome}');
          } else {
            debugPrint('>>> [Checkout] âš ï¸ Nenhuma opÃ§Ã£o de frete encontrada!');
          }
          _freteCalculado = true;
          _calculandoFrete = false;
        });

        // Mostrar mensagem de sucesso
        if (opcoes.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${opcoes.length} opÃ§Ã£o(Ãµes) de frete encontrada(s)!'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Nenhuma opÃ§Ã£o de frete disponÃ­vel. Verifique os dados informados.'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('>>> Erro ao calcular frete: $e');
      if (mounted) {
        setState(() {
          _calculandoFrete = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao calcular frete: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _formatarCPF(String value) {
    final digits = value.replaceAll(RegExp(r'[^\d]'), '');
    if (digits.length <= 3) return digits;
    if (digits.length <= 6) return '${digits.substring(0, 3)}.${digits.substring(3)}';
    if (digits.length <= 9) {
      return '${digits.substring(0, 3)}.${digits.substring(3, 6)}.${digits.substring(6)}';
    }
    return '${digits.substring(0, 3)}.${digits.substring(3, 6)}.${digits.substring(6, 9)}-${digits.substring(9, 11)}';
  }

  String _formatarTelefone(String value) {
    final digits = value.replaceAll(RegExp(r'[^\d]'), '');
    if (digits.length <= 2) return digits;
    if (digits.length <= 7) return '(${digits.substring(0, 2)}) ${digits.substring(2)}';
    return '(${digits.substring(0, 2)}) ${digits.substring(2, 7)}-${digits.substring(7, 11)}';
  }

  String _formatarCEP(String value) {
    final digits = value.replaceAll(RegExp(r'[^\d]'), '');
    if (digits.length <= 5) return digits;
    return '${digits.substring(0, 5)}-${digits.substring(5, 8)}';
  }

  IconData _obterIconeTipoFrete(String tipo) {
    switch (tipo) {
      case 'taxa_bairro':
      case 'mesmo_bairro':
        return Icons.location_on;
      case 'correios_pac':
      case 'correios_pac_mini':
        return Icons.local_shipping;
      case 'correios_sedex':
      case 'correios_sedex_10':
      case 'correios_sedex_12':
        return Icons.flash_on;
      case 'jadlog':
        return Icons.local_shipping_outlined;
      case 'total_express':
        return Icons.delivery_dining;
      case 'azul_cargo':
        return Icons.flight;
      case 'loggi':
        return Icons.motorcycle;
      case 'entrega_rapida':
        return Icons.speed;
      case 'distancia':
        return Icons.straighten;
      case 'manual':
        return Icons.calculate;
      default:
        return Icons.local_shipping;
    }
  }

  Widget _buildTipoRecebimento() {
    return Card(
      color: Colors.white.withOpacity(0.1),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.delivery_dining, color: Colors.white),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Como vocÃª quer receber?',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Escolha entre entrega ou retirada na loja',
              style: TextStyle(color: Colors.white60, fontSize: 12),
            ),
            const SizedBox(height: 12),
            _buildOpcaoRecebimento(
              titulo: 'Entrega',
              descricao: 'Receba seu pedido no endereÃ§o informado',
              icone: Icons.delivery_dining,
              cor: Colors.blue,
              selecionado: !_retiradaNaLoja,
              onTap: () {
                if (_retiradaNaLoja) {
                  setState(() => _retiradaNaLoja = false);
                  if (_cepController.text.replaceAll(RegExp(r'[^\d]'), '').length == 8 &&
                      _estadoController.text.trim().isNotEmpty) {
                    _calcularFrete();
                  }
                }
              },
            ),
            const SizedBox(height: 10),
            _buildOpcaoRecebimento(
              titulo: 'Retirada na loja',
              descricao: 'Retire seu pedido diretamente no estabelecimento',
              icone: Icons.storefront,
              cor: Colors.green,
              selecionado: _retiradaNaLoja,
              onTap: () {
                if (!_retiradaNaLoja) {
                  setState(() {
                    _retiradaNaLoja = true;
                    _valorFrete = 0.0;
                    _opcaoFreteSelecionada = null;
                  });
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOpcaoRecebimento({
    required String titulo,
    required String descricao,
    required IconData icone,
    required Color cor,
    required bool selecionado,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: selecionado ? cor.withOpacity(0.15) : Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selecionado ? cor : Colors.white.withOpacity(0.2),
              width: selecionado ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: cor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icone, color: cor, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titulo,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      descricao,
                      style: const TextStyle(fontSize: 12, color: Colors.white60),
                    ),
                  ],
                ),
              ),
              Icon(
                selecionado ? Icons.check_circle : Icons.chevron_right,
                color: selecionado ? cor : Colors.white38,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTipoPagamento() {
    final formas = _formasPagamentoDisponiveis;
    final descontoPix = _calcularDescontoPix();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.account_balance_wallet, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Como vocÃª quer pagar?',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          'Escolha uma forma de pagamento para concluir o pedido',
          style: TextStyle(color: Colors.white60, fontSize: 12),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final duasColunas = constraints.maxWidth >= 520;
            final largura = duasColunas
                ? (constraints.maxWidth - 12) / 2
                : constraints.maxWidth;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: formas.map((tipo) {
                final selecionado = _tipoPagamento == tipo;
                return SizedBox(
                  width: largura,
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => setState(() => _tipoPagamento = tipo),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: selecionado
                              ? tipo.cor.withOpacity(0.18)
                              : Colors.white.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: selecionado
                                ? tipo.cor
                                : Colors.white.withOpacity(0.2),
                            width: selecionado ? 2 : 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: tipo.cor.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(tipo.icone, color: tipo.cor, size: 20),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    tipo.nome,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    tipo.descricao,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.white60,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (tipo == TipoPagamento.pix && descontoPix > 0) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.green.withOpacity(0.25),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '-${_percentualDescontoPix.toStringAsFixed(0)}%',
                                  style: TextStyle(
                                    color: Colors.green[300],
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                            const SizedBox(width: 8),
                            Container(
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: selecionado ? tipo.cor : Colors.transparent,
                                border: Border.all(
                                  color: selecionado
                                      ? tipo.cor
                                      : Colors.white.withOpacity(0.4),
                                  width: 2,
                                ),
                              ),
                              child: selecionado
                                  ? const Icon(Icons.check, size: 15, color: Colors.white)
                                  : null,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            );
          },
        ),
        if (descontoPix > 0) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.green.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.savings, size: 16, color: Colors.green[300]),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Desconto PIX de ${_percentualDescontoPix.toStringAsFixed(0)}% aplicado',
                    style: TextStyle(fontSize: 12, color: Colors.green[300]),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  /// NÃºmero do pedido pela trilha SEGURA multi-PC: bloco reservado + piso da
  /// nuvem (getProximoNumeroPedidoSeguro) antes do cÃ¡lculo local. Aqui era
  /// max(local)+1, o que colidia com pedido lanÃ§ado no PC da loja ou em outra
  /// mÃ¡quina â€” e podia voltar para PED-0001 se a lista local ainda nÃ£o tivesse
  /// carregado no portal.
  Future<String> _gerarNumeroPedido() async {
    final dataService = Provider.of<DataService>(context, listen: false);
    final usados = dataService.pedidos.map((p) => p.numero).toSet();
    var numero = await dataService.getProximoNumeroPedidoSeguro();

    // ColisÃ£o rara (bloco reservado x lista local): pula para o prÃ³ximo livre.
    final match = RegExp(r'^PED-(\d+)$').firstMatch(numero);
    if (match != null && usados.contains(numero)) {
      var proximo = int.parse(match.group(1)!);
      do {
        proximo++;
        numero = 'PED-${proximo.toString().padLeft(4, '0')}';
      } while (usados.contains(numero));
    }
    return numero;
  }

  Future<void> _enviarPedidoWhatsApp(Pedido pedido) async {
    final telefone = _telefoneLoja();
    if (telefone == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('WhatsApp da loja nÃ£o configurado.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }
    final moeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final linhas = <String>[
      'OlÃ¡! Acabei de fazer um pedido no site.',
      'Pedido: ${pedido.numero}',
      'Cliente: ${pedido.clienteNome ?? ''}',
      if ((pedido.clienteTelefone ?? '').isNotEmpty)
        'Telefone: ${pedido.clienteTelefone}',
      'Forma de recebimento: ${(pedido.origem ?? 'E-commerce').replaceFirst('E-commerce - ', '')}',
      if (pedido.pagamentos.isNotEmpty)
        'Pagamento: ${pedido.pagamentos.first.tipo.nome}',
      '',
      'Itens:',
      ...pedido.produtos.map(
        (item) =>
            '- ${item.quantidade.toStringAsFixed(item.quantidade % 1 == 0 ? 0 : 1)}x ${item.nome} â€” ${moeda.format(item.preco * item.quantidade)}',
      ),
      if (pedido.servicos.isNotEmpty) ...pedido.servicos.map(
        (item) => '- ${item.descricao} â€” ${moeda.format(item.valor + item.valorAdicional)}',
      ),
      '',
      'Total: ${moeda.format(pedido.totalGeral)}',
      if ((pedido.observacoes ?? '').trim().isNotEmpty) ...[
        '',
        'ObservaÃ§Ãµes:',
        pedido.observacoes!,
      ],
    ];
    final uri = Uri.parse(
      'https://wa.me/$telefone?text=${Uri.encodeComponent(linhas.join('\n'))}',
    );
    try {
      final abriu = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!abriu && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('NÃ£o foi possÃ­vel abrir o WhatsApp.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('NÃ£o foi possÃ­vel abrir o WhatsApp: $e'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  Future<void> _mostrarConfirmacaoPedido(Pedido pedido) async {
    final moeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          title: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green[300], size: 30),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Pedido recebido!',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pedido ${pedido.numero}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Recebimento: ${(pedido.origem ?? 'E-commerce').replaceFirst('E-commerce - ', '')}',
                  style: const TextStyle(color: Colors.white70),
                ),
                if (pedido.pagamentos.isNotEmpty)
                  Text(
                    'Pagamento: ${pedido.pagamentos.first.tipo.nome}',
                    style: const TextStyle(color: Colors.white70),
                  ),
                const SizedBox(height: 8),
                Text(
                  'Total: ${moeda.format(pedido.totalGeral)}',
                  style: TextStyle(
                    color: Colors.green[300],
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'O pedido jÃ¡ foi enviado para a tela de Pedidos da loja. '
                  'Guarde o nÃºmero acima. Se quiser, envie o resumo no WhatsApp para agilizar o atendimento.',
                  style: TextStyle(color: Colors.white60, fontSize: 13),
                ),
              ],
            ),
          ),
          actions: [
            if (pedido.linkCliente != null && pedido.linkCliente!.isNotEmpty)
              TextButton.icon(
                onPressed: () => _abrirAcompanhamento(pedido),
                icon: const Icon(Icons.local_shipping_outlined, size: 18),
                label: const Text('Acompanhar pedido'),
              ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Fechar'),
            ),
            ElevatedButton.icon(
              onPressed: () => _enviarPedidoWhatsApp(pedido),
              icon: const Icon(Icons.chat_bubble_outline, size: 18),
              label: const Text('Enviar no WhatsApp'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _abrirAcompanhamento(Pedido pedido) async {
    final codigo = pedido.linkCliente;
    if (codigo == null || codigo.isEmpty) return;
    final base = Uri.tryParse(html_helper.getWindowOrigin());
    final origem = (base != null && base.hasScheme)
        ? '${base.scheme}://${base.host}${base.hasPort ? ':${base.port}' : ''}'
        : 'https://exodosystems.tail9b4943.ts.net';
    final uri = Uri.parse('$origem/pedido/$codigo');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Link de acompanhamento: $uri')),
      );
    }
  }

  Future<void> _finalizarPedido() async {
    // Ãšltima barreira: a loja pode ter fechado com o checkout jÃ¡ aberto.
    final statusLoja = HorarioLojaService.status(ecommerce: _configEcommerce);
    if (!statusLoja.aberta) {
      if (mounted) {
        showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            icon: Icon(Icons.storefront_outlined, size: 40, color: Colors.red[400]),
            title: const Text('Loja fechada no momento'),
            content: Text(
              'O pedido nÃ£o pode ser enviado agora. '
              '${statusLoja.proximaAbertura ?? 'Volte dentro do horÃ¡rio de funcionamento.'}',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Entendi'),
              ),
            ],
          ),
        );
      }
      return;
    }

    if (!_formKey.currentState!.validate()) {
      return;
    }

    // Frete sÃ³ Ã© obrigatÃ³rio quando o cliente escolheu receber em casa.
    if (!_retiradaNaLoja) {
      if (!_freteCalculado || _opcoesFrete.isEmpty) {
        if (_estadoController.text.isNotEmpty) {
          await _calcularFrete();
          await Future.delayed(const Duration(milliseconds: 500));
        }
        if (!_freteCalculado || _opcoesFrete.isEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'NÃ£o foi possÃ­vel calcular o frete para este endereÃ§o. '
                  'Escolha "Retirar na loja" ou confira o CEP/bairro.',
                ),
                backgroundColor: Colors.orange,
                duration: Duration(seconds: 4),
              ),
            );
          }
          return;
        }
      }

      if (_opcaoFreteSelecionada == null && _opcoesFrete.isNotEmpty) {
        setState(() {
          _opcaoFreteSelecionada = _opcoesFrete.first;
          _valorFrete = _opcoesFrete.first.valor;
          _prazoFrete = _opcoesFrete.first.prazo;
        });
      }

      if (_opcaoFreteSelecionada == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Por favor, selecione uma opÃ§Ã£o de frete.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }
    } else {
      _valorFrete = 0.0;
      _opcaoFreteSelecionada = null;
    }

    setState(() => _isLoading = true);

    try {
      final dataService = Provider.of<DataService>(context, listen: false);

      // Reutilizar o cadastro localizado pelo telefone. O endereço digitado
      // pertence ao pedido e não substitui o endereço principal do cliente.
      Cliente? cliente = _clienteEncontradoTelefone;
      final cpfLimpo = _cpfController.text.replaceAll(RegExp(r'[^\d]'), '');
      final telefoneLimpo = _telefoneController.text.replaceAll(RegExp(r'[^\d]'), '');
      if (cliente == null) {
        final encontrados = await dataService.buscarClientePorTelefone(telefoneLimpo);
        if (encontrados.isNotEmpty) cliente = encontrados.first;
      }
      final enderecoCliente = _retiradaNaLoja ? null : _enderecoController.text.trim();
      final numeroCliente = _retiradaNaLoja ? null : _numeroController.text.trim();
      final complementoCliente = _retiradaNaLoja ? null :
          (_complementoController.text.trim().isNotEmpty ? _complementoController.text.trim() : null);
      final bairroCliente = _retiradaNaLoja ? null : _bairroController.text.trim();
      final cidadeCliente = _retiradaNaLoja ? null : _cidadeController.text.trim();
      final estadoCliente = _retiradaNaLoja ? null : _estadoController.text.trim();
      final cepCliente = _retiradaNaLoja ? null : _cepController.text.replaceAll(RegExp(r'[^\d]'), '');

      if (cliente != null) {
        final existente = cliente;
        final enderecos = List<EnderecoCliente>.from(existente.enderecos);
        if (!_retiradaNaLoja && (enderecoCliente ?? '').isNotEmpty && (bairroCliente ?? '').isNotEmpty) {
          String normalizar(String? v) => (v ?? '').toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
          final jaSalvo = enderecos.any((e) =>
              normalizar(e.logradouro) == normalizar(enderecoCliente) &&
              normalizar(e.numero) == normalizar(numeroCliente) &&
              normalizar(e.bairro) == normalizar(bairroCliente) &&
              normalizar(e.cidade) == normalizar(cidadeCliente));
          if (!jaSalvo) {
            enderecos.add(EnderecoCliente(
              tipo: 'Endereço de entrega', logradouro: enderecoCliente!,
              numero: numeroCliente ?? '', complemento: complementoCliente,
              bairro: bairroCliente!, cidade: cidadeCliente ?? '',
              uf: estadoCliente ?? '', cep: cepCliente, isDefault: false,
            ));
          }
        }
        cliente = existente.copyWith(
          nome: _nomeController.text.trim(),
          telefone: _telefoneController.text.trim(),
          email: _emailController.text.trim().isNotEmpty ? _emailController.text.trim() : existente.email,
          cpfCnpj: cpfLimpo.isNotEmpty ? cpfLimpo : existente.cpfCnpj,
          enderecos: enderecos,
          updatedAt: DateTime.now(),
        );
        await dataService.updateCliente(cliente);
      } else {
        final enderecos = <EnderecoCliente>[];
        if (!_retiradaNaLoja && (enderecoCliente ?? '').isNotEmpty && (bairroCliente ?? '').isNotEmpty) {
          enderecos.add(EnderecoCliente(
            tipo: 'Endereço de entrega', logradouro: enderecoCliente!,
            numero: numeroCliente ?? '', complemento: complementoCliente,
            bairro: bairroCliente!, cidade: cidadeCliente ?? '',
            uf: estadoCliente ?? '', cep: cepCliente, isDefault: false,
          ));
        }
        cliente = Cliente(
          id: const Uuid().v4(), nome: _nomeController.text.trim(),
          telefone: _telefoneController.text.trim(),
          email: _emailController.text.trim().isNotEmpty ? _emailController.text.trim() : null,
          cpfCnpj: cpfLimpo.isNotEmpty ? cpfLimpo : null,
          enderecos: enderecos, createdAt: DateTime.now(), updatedAt: DateTime.now(),
        );
        await dataService.addCliente(cliente);
      }

      final enderecoCompleto = [
        _enderecoController.text.trim(),
        _numeroController.text.trim(),
        _complementoController.text.trim(),
        _bairroController.text.trim(),
        _cidadeController.text.trim(),
        _estadoController.text.trim(),
        _cepController.text.trim(),
      ].where((s) => s.isNotEmpty).join(', ');
      final enderecoLoja = _enderecoLojaFormatado();
      final enderecoPedido = _retiradaNaLoja
          ? 'Retirada na loja${enderecoLoja.isNotEmpty ? ' - $enderecoLoja' : ''}'
          : enderecoCompleto;

      // Converter carrinho para itens de pedido
      final carrinhoService =
          Provider.of<CarrinhoService>(context, listen: false);
      final produtos = carrinhoService.itens
          .where((item) => item.isProduto)
          .map((item) => ItemPedido(
                id: item.itemId,
                nome: item.nome,
                quantidade: item.quantidade.toDouble(),
                preco: item.preco,
              ))
          .toList();

      final servicos = carrinhoService.itens
          .where((item) => item.isServico)
          .map((item) => ItemServico(
                id: item.itemId,
                descricao: item.nome,
                valor: item.preco,
                valorAdicional: item.valorAdicional ?? 0.0,
                descricaoAdicional: item.descricaoAdicional,
              ))
          .toList();

      if (produtos.isEmpty && servicos.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Seu carrinho estÃ¡ vazio.'),
              backgroundColor: Colors.orange,
            ),
          );
          setState(() => _isLoading = false);
        }
        return;
      }

      // O estoque pode ter mudado desde que o item entrou no carrinho (outro
      // cliente comprou antes). Confere tudo ANTES de criar o pedido, senÃ£o o
      // lojista recebe uma venda que nÃ£o pode atender.
      final faltasDeEstoque = <String>[];
      for (final item in carrinhoService.itens.where((i) => i.isProduto)) {
        Produto? produto;
        for (final p in dataService.produtos) {
          if (p.id == item.itemId) {
            produto = p;
            break;
          }
        }
        if (produto == null) continue;
        final falta = dataService.validarEstoqueDisponivel(
          produto,
          quantidade: item.quantidade.toDouble(),
        );
        if (falta != null) faltasDeEstoque.add('${item.nome}: $falta');
      }
      if (faltasDeEstoque.isNotEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Item sem estoque suficiente â€” ajuste a quantidade no carrinho.\n'
                '${faltasDeEstoque.join('\n')}',
              ),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 6),
            ),
          );
        }
        return;
      }

      final taxaEntrega = _retiradaNaLoja
          ? 0.0
          : (_opcaoFreteSelecionada?.valor ?? _valorFrete);
      final prazoEntrega = _opcaoFreteSelecionada?.prazo ?? _prazoFrete;
      final desconto = _calcularDescontoPix();
      final totalFinal = _calcularTotalComFrete();

      final deliveryInfo = _retiradaNaLoja
          ? null
          : DeliveryInfo(
              id: const Uuid().v4(),
              enderecoId: cliente.id,
              logradouro: _enderecoController.text.trim(),
              numero: _numeroController.text.trim(),
              bairro: _bairroController.text.trim(),
              cidade: _cidadeController.text.trim(),
              uf: _estadoController.text.trim().toUpperCase(),
              cep: _cepController.text.replaceAll(RegExp(r'[^\d]'), ''),
              taxaEntrega: taxaEntrega,
              status: 'Pendente',
              dataPedido: DateTime.now(),
              observacoes: 'Pedido e-commerce',
              previsaoEntrega:
                  '$prazoEntrega dia${prazoEntrega == 1 ? '' : 's'} Ãºtil${prazoEntrega == 1 ? '' : 'eis'}',
            );

      // A configuraÃ§Ã£o pode ter mudado com a tela aberta: garante que o
      // pedido nÃ£o seja salvo com uma forma que a loja nÃ£o aceita mais.
      final formasAtuais = _formasPagamentoDisponiveis;
      final tipoPagamentoFinal = formasAtuais.contains(_tipoPagamento)
          ? _tipoPagamento
          : formasAtuais.first;

      final pagamento = PagamentoPedido(
        id: const Uuid().v4(),
        tipo: tipoPagamentoFinal,
        valor: totalFinal,
        recebido: false,
        observacao: _retiradaNaLoja
            ? 'Pagamento na retirada'
            : 'Pagamento na entrega',
      );

      final observacoesPartes = <String>[];
      if (_retiradaNaLoja) {
        observacoesPartes.add('RETIRADA NA LOJA');
        if (enderecoLoja.isNotEmpty) {
          observacoesPartes.add('EndereÃ§o da loja: $enderecoLoja');
        }
      } else if (_opcaoFreteSelecionada != null) {
        observacoesPartes.add(
          'Entrega: ${_opcaoFreteSelecionada!.nome} - '
          'R\$ ${_opcaoFreteSelecionada!.valor.toStringAsFixed(2)} '
          '(${_opcaoFreteSelecionada!.prazo} dia${_opcaoFreteSelecionada!.prazo == 1 ? '' : 's'} Ãºtil${_opcaoFreteSelecionada!.prazo == 1 ? '' : 'eis'})',
        );
      }
      if (_observacoesController.text.trim().isNotEmpty) {
        observacoesPartes.add(_observacoesController.text.trim());
      }

      final numeroPedido = await _gerarNumeroPedido();
      final codigoAcompanhamento = const Uuid()
          .v4()
          .replaceAll('-', '')
          .substring(0, 8)
          .toUpperCase();
      final pedido = Pedido(
        id: const Uuid().v4(),
        numero: numeroPedido,
        linkCliente: codigoAcompanhamento,
        clienteId: cliente.id,
        clienteNome: cliente.nome,
        clienteTelefone: cliente.telefone,
        clienteEndereco: enderecoPedido,
        clienteCpfCnpj: cliente.cpfCnpj,
        vendedorId: widget.linkVendedor?.funcionarioId,
        vendedorNome: widget.linkVendedor?.funcionarioNome,
        linkVendedorId: widget.linkVendedor?.id,
        linkVendedorCodigo: widget.linkVendedor?.codigoLink,
        origemEcommerce: true,
        origem: _retiradaNaLoja
            ? 'E-commerce - Retirada'
            : 'E-commerce - Entrega',
        dataPedido: DateTime.now(),
        status: 'Pendente',
        total: totalFinal,
        descontoTotal: desconto,
        observacoes:
            observacoesPartes.isEmpty ? null : observacoesPartes.join('\n'),
        produtos: produtos,
        servicos: servicos,
        pagamentos: [pagamento],
        deliveryInfo: deliveryInfo,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      // Salvar pedido (local + nuvem). A tela de Pedidos escuta o DataService
      // e recebe o pedido automaticamente.
      await dataService.addPedido(pedido);

      // Criar registro de entrega para o controle de entregas, quando houver.
      if (deliveryInfo != null) {
        try {
          await dataService.addEntrega(
            Entrega(
              id: const Uuid().v4(),
              pedidoId: pedido.id,
              pedidoNumero: pedido.numero,
              clienteNome: cliente.nome,
              clienteTelefone: cliente.telefone,
              enderecoEntrega: enderecoCompleto,
              complemento: _complementoController.text.trim().isNotEmpty
                  ? _complementoController.text.trim()
                  : null,
              bairro: _bairroController.text.trim(),
              cidade: _cidadeController.text.trim(),
              cep: _cepController.text.replaceAll(RegExp(r'[^\d]'), ''),
              status: StatusEntrega.aguardando,
              dataCriacao: DateTime.now(),
              taxaEntrega: taxaEntrega,
              tipoEntrega: 'E-commerce',
              observacoes: 'Pedido ${pedido.numero}',
            ),
          );
        } catch (e) {
          debugPrint('>>> [Checkout] Entrega nÃ£o criada: $e');
        }
      }

      // Criar comissÃ£o se houver link de vendedor
      if (widget.linkVendedor != null && widget.linkVendedor!.id.isNotEmpty) {
        final valorComissao =
            totalFinal * (widget.linkVendedor!.percentualComissao / 100);

        final comissao = ComissaoVendedor(
          id: const Uuid().v4(),
          linkVendedorId: widget.linkVendedor!.id,
          funcionarioId: widget.linkVendedor!.funcionarioId,
          funcionarioNome: widget.linkVendedor!.funcionarioNome,
          pedidoId: pedido.id,
          pedidoNumero: pedido.numero,
          valorPedido: totalFinal,
          percentualComissao: widget.linkVendedor!.percentualComissao,
          valorComissao: valorComissao,
          status: 'Pendente',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        await dataService.addComissaoVendedor(comissao);

        final linkAtualizado = widget.linkVendedor!.copyWith(
          totalVendas: widget.linkVendedor!.totalVendas + 1,
          totalComissao: widget.linkVendedor!.totalComissao + valorComissao,
          updatedAt: DateTime.now(),
        );
        await dataService.updateLinkVendedor(linkAtualizado);
      }

      if (mounted) {
        carrinhoService.limparCarrinho();
        await _mostrarConfirmacaoPedido(pedido);
        if (mounted) {
          Navigator.of(context).pop(pedido);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao finalizar pedido: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

    return AppTheme.appBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Finalizar Compra'),
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        bottomNavigationBar: Consumer<CarrinhoService>(
          builder: (context, carrinhoService, _) {
            final totalComFrete = _calcularTotalComFrete();
            return Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                border: Border.all(color: Colors.white10),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 20,
                    offset: const Offset(0, -5),
                  ),
                ],
              ),
              child: SafeArea(
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Total do Pedido',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                          Text(
                            formatoMoeda.format(totalComFrete),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 1,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _finalizarPedido,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(context).colorScheme.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          elevation: 0,
                        ),
                        child: _isLoading
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'Finalizar',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        body: _isLoading

            ? const Center(child: CircularProgressIndicator())
            : Form(
                key: _formKey,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Resumo do pedido
                      Card(
                        color: Colors.white.withOpacity(0.1),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.shopping_cart, color: Colors.white),
                                  const SizedBox(width: 8),
                                  const Text(
                                    'Resumo do Pedido',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Consumer<CarrinhoService>(
                                builder: (context, carrinhoService, _) {
                                  return Column(
                                    children: carrinhoService.itens.map((item) => Padding(
                                      padding: const EdgeInsets.only(bottom: 12),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  item.nome,
                                                  style: const TextStyle(
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.w500,
                                                    color: Colors.white,
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  'Qtd: ${item.quantidade}',
                                                  style: const TextStyle(
                                                    fontSize: 12,
                                                    color: Colors.white70,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Text(
                                            formatoMoeda.format(item.subtotal),
                                            style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ],
                                      ),
                                    )).toList(),
                                  );
                                },
                              ),                              const Divider(color: Colors.white24),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'Subtotal:',
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: Colors.white70,
                                    ),
                                  ),
                                  Text(
                                    formatoMoeda.format(_calcularTotal()),
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                              if (_calcularDescontoPix() > 0) ...[
                                const SizedBox(height: 6),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Desconto Pix (${_percentualDescontoPix.toStringAsFixed(0)}%):',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.green[300],
                                      ),
                                    ),
                                    Text(
                                      '- ${formatoMoeda.format(_calcularDescontoPix())}',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.green[300],
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                              if (!_retiradaNaLoja &&
                                  (_opcaoFreteSelecionada != null || _valorFrete > 0)) ...[
                                const SizedBox(height: 6),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text(
                                      'Frete:',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.white70,
                                      ),
                                    ),
                                    Text(
                                      formatoMoeda.format(
                                        _opcaoFreteSelecionada?.valor ?? _valorFrete,
                                      ),
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                              if (_calculandoFrete) ...[
                                const SizedBox(height: 8),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Calculando frete...',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.white70,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                              if (!_retiradaNaLoja && _freteCalculado && !_calculandoFrete && _opcoesFrete.isNotEmpty) ...[
                                const SizedBox(height: 16),
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).colorScheme.primary.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: Theme.of(context).colorScheme.primary.withOpacity(0.5),
                                      width: 2,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.local_shipping,
                                        color: Theme.of(context).colorScheme.primary,
                                        size: 24,
                                      ),
                                      const SizedBox(width: 12),
                                      const Expanded(
                                        child: Text(
                                          'Selecione o Tipo de Entrega:',
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 12),
                                ..._opcoesFrete.map((opcao) {
                                  final isSelecionada = _opcaoFreteSelecionada?.id == opcao.id;
                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    decoration: BoxDecoration(
                                      color: isSelecionada 
                                          ? Theme.of(context).colorScheme.primary.withOpacity(0.2)
                                          : Colors.white.withOpacity(0.05),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: isSelecionada
                                            ? Theme.of(context).colorScheme.primary
                                            : Colors.white.withOpacity(0.2),
                                        width: isSelecionada ? 2 : 1,
                                      ),
                                    ),
                                    child: Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        onTap: () {
                                          setState(() {
                                            _opcaoFreteSelecionada = opcao;
                                            _valorFrete = opcao.valor;
                                            _prazoFrete = opcao.prazo;
                                          });
                                          // Feedback visual
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(
                                              content: Text('${opcao.nome} selecionado'),
                                              duration: const Duration(seconds: 1),
                                              backgroundColor: Colors.green,
                                            ),
                                          );
                                        },
                                        borderRadius: BorderRadius.circular(12),
                                        child: Padding(
                                          padding: const EdgeInsets.all(16),
                                          child: Row(
                                            children: [
                                              // Radio button mais destacado
                                              Container(
                                                width: 28,
                                                height: 28,
                                                decoration: BoxDecoration(
                                                  shape: BoxShape.circle,
                                                  border: Border.all(
                                                    color: isSelecionada
                                                        ? Theme.of(context).colorScheme.primary
                                                        : Colors.white70,
                                                    width: isSelecionada ? 3 : 2,
                                                  ),
                                                  color: isSelecionada
                                                      ? Theme.of(context).colorScheme.primary
                                                      : Colors.transparent,
                                                ),
                                                child: isSelecionada
                                                    ? const Icon(
                                                        Icons.check,
                                                        size: 18,
                                                        color: Colors.white,
                                                      )
                                                    : null,
                                              ),
                                              const SizedBox(width: 16),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Row(
                                                      children: [
                                                        Icon(
                                                          _obterIconeTipoFrete(opcao.tipo),
                                                          size: 20,
                                                          color: isSelecionada
                                                              ? Theme.of(context).colorScheme.primary
                                                              : Colors.white70,
                                                        ),
                                                        const SizedBox(width: 8),
                                                        Expanded(
                                                          child: Text(
                                                            opcao.nome,
                                                            style: TextStyle(
                                                              fontSize: 16,
                                                              fontWeight: FontWeight.bold,
                                                              color: isSelecionada
                                                                  ? Theme.of(context).colorScheme.primary
                                                                  : Colors.white,
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                    if (opcao.descricao != null) ...[
                                                      const SizedBox(height: 4),
                                                      Text(
                                                        opcao.descricao!,
                                                        style: TextStyle(
                                                          fontSize: 13,
                                                          color: Colors.white70,
                                                        ),
                                                      ),
                                                    ],
                                                    const SizedBox(height: 6),
                                                    Row(
                                                      children: [
                                                        Icon(
                                                          Icons.access_time,
                                                          size: 14,
                                                          color: Colors.white60,
                                                        ),
                                                        const SizedBox(width: 4),
                                                        Text(
                                                          '${opcao.prazo} dia${opcao.prazo > 1 ? 's' : ''} Ãºtil${opcao.prazo > 1 ? 'eis' : ''}',
                                                          style: TextStyle(
                                                            fontSize: 13,
                                                            color: Colors.white70,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              Column(
                                                crossAxisAlignment: CrossAxisAlignment.end,
                                                children: [
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                                    decoration: BoxDecoration(
                                                      color: opcao.valor == 0.0
                                                          ? Colors.green.withOpacity(0.2)
                                                          : (isSelecionada
                                                              ? Theme.of(context).colorScheme.primary.withOpacity(0.2)
                                                              : Colors.white.withOpacity(0.1)),
                                                      borderRadius: BorderRadius.circular(8),
                                                    ),
                                                    child: Text(
                                                      opcao.valor == 0.0
                                                          ? 'GRÃTIS'
                                                          : formatoMoeda.format(opcao.valor),
                                                      style: TextStyle(
                                                        fontSize: 18,
                                                        fontWeight: FontWeight.bold,
                                                        color: opcao.valor == 0.0
                                                            ? Colors.green[300]
                                                            : (isSelecionada
                                                                ? Theme.of(context).colorScheme.primary
                                                                : Colors.white),
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
                                }).toList(),
                                const SizedBox(height: 12),
                                // Resumo da seleÃ§Ã£o
                                if (_opcaoFreteSelecionada != null) ...[
                                  Container(
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: Colors.green.withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: Colors.green.withOpacity(0.4),
                                        width: 2,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.check_circle,
                                          color: Colors.green[300],
                                          size: 28,
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'Entrega Selecionada:',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.green[200],
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                _opcaoFreteSelecionada!.nome,
                                                style: TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.green[100],
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                'Prazo: ${_opcaoFreteSelecionada!.prazo} dia${_opcaoFreteSelecionada!.prazo > 1 ? 's' : ''} Ãºtil${_opcaoFreteSelecionada!.prazo > 1 ? 'eis' : ''} | Valor: ${_opcaoFreteSelecionada!.valor == 0.0 ? 'GRÃTIS' : formatoMoeda.format(_opcaoFreteSelecionada!.valor)}',
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  color: Colors.green[200],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                              if (_freteCalculado && !_calculandoFrete && _opcoesFrete.isEmpty) ...[
                                const SizedBox(height: 8),
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.orange.withOpacity(0.3)),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(Icons.warning, size: 16, color: Colors.orange[300]),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'Nenhuma opÃ§Ã£o de frete disponÃ­vel. Verifique o CEP.',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.orange[300],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              const Divider(color: Colors.white24),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'Total:',
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                  Text(
                                    formatoMoeda.format(_calcularTotalComFrete()),
                                    style: TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold,
                                      color: Theme.of(context).colorScheme.primary,
                                    ),
                                  ),
                                ],
                              ),
                              if (widget.linkVendedor != null) ...[
                                const SizedBox(height: 12),
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.purple.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.purple.withOpacity(0.3)),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(Icons.person, size: 16, color: Colors.purple[300]),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'Vendedor: ${widget.linkVendedor!.funcionarioNome}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.purple[300],
                                          ),
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

                      // Banner de cadastro (se nÃ£o estiver logado)
                      if (!_clienteLogado) ...[
                        Card(
                          color: Colors.blue.withOpacity(0.2),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                Icon(Icons.info_outline, color: Colors.blue[300], size: 24),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Cadastro pelo telefone',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Informe seu telefone: se ja existir cadastro, seus dados serao preenchidos automaticamente. Voce pode informar outro endereco para esta entrega.',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: Colors.white70,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                ElevatedButton.icon(
                                  onPressed: _irParaCadastro,
                                  icon: const Icon(Icons.person_add, size: 18),
                                  label: const Text('Cadastrar'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.blue,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Dados do cliente
                      Card(
                        color: Colors.white.withOpacity(0.1),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.person, color: Colors.white),
                                  const SizedBox(width: 8),
                                  const Text(
                                    'Dados do Cliente',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                  if (_clienteLogado) ...[
                                    const Spacer(),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.green.withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: Colors.green.withOpacity(0.3)),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.check_circle, size: 14, color: Colors.green[300]),
                                          const SizedBox(width: 4),
                                          Text(
                                            'Logado',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.green[300],
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              if (_clienteLogado) ...[
                                const SizedBox(height: 8),
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.green.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.green.withOpacity(0.3)),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(Icons.info_outline, size: 16, color: Colors.green[300]),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'Seus dados foram preenchidos automaticamente. VocÃª pode editÃ¡-los se necessÃ¡rio.',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.green[300],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              const SizedBox(height: 16),
                              TextFormField(
                                controller: _nomeController,
                                style: const TextStyle(color: Colors.white),
                                decoration: InputDecoration(
                                  labelText: 'Nome completo *',
                                  labelStyle: TextStyle(color: Colors.white70),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(color: Colors.white30),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(color: Colors.white30),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(color: Theme.of(context).colorScheme.primary),
                                  ),
                                  filled: true,
                                  fillColor: Colors.white.withOpacity(0.1),
                                  prefixIcon: Icon(Icons.person_outline, color: Colors.white70),
                                ),
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return 'Campo obrigatÃ³rio';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextFormField(
                                      controller: _telefoneController,
                                      onChanged: _buscarClientePeloTelefone,
                                      style: const TextStyle(color: Colors.white),
                                      keyboardType: TextInputType.phone,
                                      inputFormatters: [
                                        TextInputFormatter.withFunction((oldValue, newValue) {
                                          final formatted = _formatarTelefone(newValue.text);
                                          return TextEditingValue(
                                            text: formatted,
                                            selection: TextSelection.collapsed(offset: formatted.length),
                                          );
                                        }),
                                      ],
                                      decoration: InputDecoration(
                                        labelText: 'Telefone *',
                                        labelStyle: TextStyle(color: Colors.white70),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(12),
                                          borderSide: BorderSide(color: Colors.white30),
                                        ),
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(12),
                                          borderSide: BorderSide(color: Colors.white30),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(12),
                                          borderSide: BorderSide(color: Theme.of(context).colorScheme.primary),
                                        ),
                                        filled: true,
                                        fillColor: Colors.white.withOpacity(0.1),
                                        prefixIcon: Icon(Icons.phone, color: Colors.white70),
                                        suffixIcon: _buscandoClienteTelefone
                                            ? const Padding(
                                                padding: EdgeInsets.all(12),
                                                child: SizedBox(
                                                  width: 18,
                                                  height: 18,
                                                  child: CircularProgressIndicator(strokeWidth: 2),
                                                ),
                                              )
                                            : (_clienteEncontradoTelefone != null
                                                ? const Icon(Icons.check_circle, color: Colors.green)
                                                : null),
                                        helperText: _clienteEncontradoTelefone != null
                                            ? 'Cadastro encontrado. Dados preenchidos.'
                                            : 'Informe seu telefone para localizar seu cadastro.',
                                        helperStyle: const TextStyle(color: Colors.white70),
                                      ),
                                      validator: (value) {
                                        if (value == null || value.trim().isEmpty) {
                                          return 'Campo obrigatÃ³rio';
                                        }
                                        final digits = value.replaceAll(RegExp(r'[^\d]'), '');
                                        if (digits.length < 10) {
                                          return 'Telefone invÃ¡lido';
                                        }
                                        return null;
                                      },
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              TextFormField(
                                controller: _emailController,
                                style: const TextStyle(color: Colors.white),
                                keyboardType: TextInputType.emailAddress,
                                decoration: InputDecoration(
                                  labelText: 'E-mail',
                                  labelStyle: TextStyle(color: Colors.white70),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(color: Colors.white30),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(color: Colors.white30),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(color: Theme.of(context).colorScheme.primary),
                                  ),
                                  filled: true,
                                  fillColor: Colors.white.withOpacity(0.1),
                                  prefixIcon: Icon(Icons.email_outlined, color: Colors.white70),
                                ),
                              ),
                              const SizedBox(height: 16),
                              TextFormField(
                                controller: _cpfController,
                                style: const TextStyle(color: Colors.white),
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  TextInputFormatter.withFunction((oldValue, newValue) {
                                    final formatted = _formatarCPF(newValue.text);
                                    return TextEditingValue(
                                      text: formatted,
                                      selection: TextSelection.collapsed(offset: formatted.length),
                                    );
                                  }),
                                  LengthLimitingTextInputFormatter(14),
                                ],
                                decoration: InputDecoration(
                                  labelText: 'CPF (opcional)',
                                  labelStyle: TextStyle(color: Colors.white70),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(color: Colors.white30),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(color: Colors.white30),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(color: Theme.of(context).colorScheme.primary),
                                  ),
                                  filled: true,
                                  fillColor: Colors.white.withOpacity(0.1),
                                  prefixIcon: Icon(Icons.badge_outlined, color: Colors.white70),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Como o cliente quer receber (entrega ou retirada)
                      _buildTipoRecebimento(),

                      if (!_retiradaNaLoja) ...[
                      const SizedBox(height: 24),

                      // EndereÃ§o
                      Card(
                        color: Colors.white.withOpacity(0.1),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.location_on, color: Colors.white),
                                  const SizedBox(width: 8),
                                  const Text(
                                    'EndereÃ§o de Entrega',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              // CEP com botÃ£o de busca
                              Row(
                                children: [
                                  Expanded(
                                    child: TextFormField(
                                      controller: _cepController,
                                      style: const TextStyle(color: Colors.white),
                                      keyboardType: TextInputType.number,
                                      inputFormatters: [
                                        TextInputFormatter.withFunction((oldValue, newValue) {
                                          final formatted = _formatarCEP(newValue.text);
                                          return TextEditingValue(
                                            text: formatted,
                                            selection: TextSelection.collapsed(offset: formatted.length),
                                          );
                                        }),
                                        LengthLimitingTextInputFormatter(9),
                                      ],
                                      decoration: InputDecoration(
                                        labelText: 'CEP *',
                                        labelStyle: TextStyle(color: Colors.white70),
                                        hintText: '00000-000',
                                        hintStyle: TextStyle(color: Colors.white38),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(12),
                                          borderSide: BorderSide(color: Colors.white30),
                                        ),
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(12),
                                          borderSide: BorderSide(color: Colors.white30),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(12),
                                          borderSide: BorderSide(color: Theme.of(context).colorScheme.primary),
                                        ),
                                        filled: true,
                                        fillColor: Colors.white.withOpacity(0.1),
                                        prefixIcon: Icon(Icons.pin_drop, color: Colors.white70),
                                      ),
                                      validator: (value) {
                                        if (value == null || value.trim().isEmpty) {
                                          return 'Campo obrigatÃ³rio';
                                        }
                                        final digits = value.replaceAll(RegExp(r'[^\d]'), '');
                                        if (digits.length != 8) {
                                          return 'CEP invÃ¡lido';
                                        }
                                        return null;
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  ElevatedButton.icon(
                                    onPressed: _buscandoCep ? null : _buscarCEP,
                                    icon: _buscandoCep
                                        ? const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(strokeWidth: 2),
                                          )
                                        : const Icon(Icons.search),
                                    label: Text(_buscandoCep ? 'Buscando...' : 'Buscar'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Theme.of(context).colorScheme.primary,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              TextFormField(
                                controller: _enderecoController,
                                style: const TextStyle(color: Colors.white),
                                decoration: InputDecoration(
                                  labelText: 'EndereÃ§o *',
                                  labelStyle: TextStyle(color: Colors.white70),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(color: Colors.white30),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(color: Colors.white30),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(color: Theme.of(context).colorScheme.primary),
                                  ),
                                  filled: true,
                                  fillColor: Colors.white.withOpacity(0.1),
                                  prefixIcon: Icon(Icons.home_outlined, color: Colors.white70),
                                ),
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return 'Campo obrigatÃ³rio';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  Expanded(
                                    flex: 2,
                                    child: TextFormField(
                                      controller: _numeroController,
                                      style: const TextStyle(color: Colors.white),
                                      decoration: InputDecoration(
                                        labelText: 'NÃºmero *',
                                        labelStyle: TextStyle(color: Colors.white70),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(12),
                                          borderSide: BorderSide(color: Colors.white30),
                                        ),
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(12),
                                          borderSide: BorderSide(color: Colors.white30),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(12),
                                          borderSide: BorderSide(color: Theme.of(context).colorScheme.primary),
                                        ),
                                        filled: true,
                                        fillColor: Colors.white.withOpacity(0.1),
                                        prefixIcon: Icon(Icons.numbers, color: Colors.white70),
                                      ),
                                      validator: (value) {
                                        if (value == null || value.trim().isEmpty) {
                                          return 'Campo obrigatÃ³rio';
                                        }
                                        return null;
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    flex: 3,
                                    child: TextFormField(
                                      controller: _complementoController,
                                      style: const TextStyle(color: Colors.white),
                                      decoration: InputDecoration(
                                        labelText: 'Complemento',
                                        labelStyle: TextStyle(color: Colors.white70),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(12),
                                          borderSide: BorderSide(color: Colors.white30),
                                        ),
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(12),
                                          borderSide: BorderSide(color: Colors.white30),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(12),
                                          borderSide: BorderSide(color: Theme.of(context).colorScheme.primary),
                                        ),
                                        filled: true,
                                        fillColor: Colors.white.withOpacity(0.1),
                                        prefixIcon: Icon(Icons.apartment, color: Colors.white70),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                                                            Builder(
                                builder: (context) {
                                  final bairros = Provider.of<DataService>(context, listen: false)
                                      .taxasEntrega.where((taxa) => taxa.ativo)
                                      .map((taxa) => taxa.bairro.trim())
                                      .where((bairro) => bairro.isNotEmpty).toSet().toList()
                                    ..sort();
                                  final atual = _bairroController.text.trim();
                                  if (atual.isNotEmpty && !bairros.any((b) => b.toLowerCase() == atual.toLowerCase())) {
                                    bairros.insert(0, atual);
                                  }
                                  return DropdownButtonFormField<String>(
                                    value: atual.isNotEmpty ? atual : null,
                                    isExpanded: true,
                                    dropdownColor: const Color(0xFF263238),
                                    style: const TextStyle(color: Colors.white),
                                    decoration: InputDecoration(
                                      labelText: 'Selecione o bairro *',
                                      labelStyle: const TextStyle(color: Colors.white70),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                      filled: true,
                                      fillColor: Colors.white.withOpacity(0.1),
                                      prefixIcon: const Icon(Icons.location_city, color: Colors.white70),
                                    ),
                                    hint: const Text('Escolha seu bairro', style: TextStyle(color: Colors.white54)),
                                    items: bairros.map((b) => DropdownMenuItem<String>(value: b, child: Text(b))).toList(),
                                    onChanged: (bairro) {
                                      if (bairro == null) return;
                                      _bairroController.text = bairro;
                                      _calcularFrete();
                                    },
                                    validator: (value) => value == null || value.trim().isEmpty ? 'Selecione seu bairro' : null,
                                  );
                                },
                              ),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  Expanded(
                                    flex: 3,
                                    child: TextFormField(
                                      controller: _cidadeController,
                                      style: const TextStyle(color: Colors.white),
                                      decoration: InputDecoration(
                                        labelText: 'Cidade *',
                                        labelStyle: TextStyle(color: Colors.white70),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(12),
                                          borderSide: BorderSide(color: Colors.white30),
                                        ),
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(12),
                                          borderSide: BorderSide(color: Colors.white30),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(12),
                                          borderSide: BorderSide(color: Theme.of(context).colorScheme.primary),
                                        ),
                                        filled: true,
                                        fillColor: Colors.white.withOpacity(0.1),
                                        prefixIcon: Icon(Icons.location_city, color: Colors.white70),
                                      ),
                                      validator: (value) {
                                        if (value == null || value.trim().isEmpty) {
                                          return 'Campo obrigatÃ³rio';
                                        }
                                        return null;
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    flex: 2,
                                    child: TextFormField(
                                      controller: _estadoController,
                                      style: const TextStyle(color: Colors.white),
                                      decoration: InputDecoration(
                                        labelText: 'UF *',
                                        labelStyle: TextStyle(color: Colors.white70),
                                        hintText: 'PR',
                                        hintStyle: TextStyle(color: Colors.white38),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(12),
                                          borderSide: BorderSide(color: Colors.white30),
                                        ),
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(12),
                                          borderSide: BorderSide(color: Colors.white30),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(12),
                                          borderSide: BorderSide(color: Theme.of(context).colorScheme.primary),
                                        ),
                                        filled: true,
                                        fillColor: Colors.white.withOpacity(0.1),
                                        prefixIcon: Icon(Icons.map_outlined, color: Colors.white70),
                                      ),
                                      textCapitalization: TextCapitalization.characters,
                                      maxLength: 2,
                                      validator: (value) {
                                        if (value == null || value.trim().isEmpty) {
                                          return 'Campo obrigatÃ³rio';
                                        }
                                        if (value.length != 2) {
                                          return 'UF invÃ¡lida';
                                        }
                                        return null;
                                      },
                                      onChanged: (value) {
                                        if (value.length == 2 && _estadoLoja != null) {
                                          // Aguardar um pouco antes de calcular para evitar mÃºltiplas chamadas
                                          Future.delayed(const Duration(milliseconds: 500), () {
                                            if (mounted && _estadoController.text.length == 2) {
                                              _calcularFrete();
                                            }
                                          });
                                        }
                                      },
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              // BotÃ£o para calcular frete manualmente
                              if (!_calculandoFrete && (!_freteCalculado || _opcoesFrete.isEmpty))
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    onPressed: () {
                                      if (_estadoController.text.isEmpty) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(
                                            content: Text('Preencha o estado (UF) para calcular o frete'),
                                            backgroundColor: Colors.orange,
                                          ),
                                        );
                                        return;
                                      }
                                      _calcularFrete();
                                    },
                                    icon: const Icon(Icons.local_shipping),
                                    label: Text(_freteCalculado && _opcoesFrete.isEmpty
                                        ? 'Recalcular Frete'
                                        : 'Calcular Frete'),
                                    style: ElevatedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(vertical: 16),
                                      backgroundColor: Theme.of(context).colorScheme.primary,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                  ),
                                ),
                              if (_freteCalculado && _opcaoFreteSelecionada != null && _opcaoFreteSelecionada!.valor > 0) ...[
                                const SizedBox(height: 16),
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.green.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: Colors.green.withOpacity(0.3)),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(Icons.local_shipping, color: Colors.green[300]),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              '${_opcaoFreteSelecionada!.nome} selecionado',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.green[300],
                                              ),
                                            ),
                                            Text(
                                              formatoMoeda.format(_opcaoFreteSelecionada!.valor),
                                              style: TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.green[300],
                                              ),
                                            ),
                                          ],
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

                      ],

                      const SizedBox(height: 24),

                      // Pagamento
                      Card(
                        color: Colors.white.withOpacity(0.1),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: _buildTipoPagamento(),
                        ),
                      ),

                      const SizedBox(height: 24),

                      // ObservaÃ§Ãµes
                      Card(
                        color: Colors.white.withOpacity(0.1),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.note_outlined, color: Colors.white),
                                  const SizedBox(width: 8),
                                  const Text(
                                    'ObservaÃ§Ãµes',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _observacoesController,
                                style: const TextStyle(color: Colors.white),
                                decoration: InputDecoration(
                                  labelText: 'ObservaÃ§Ãµes adicionais (opcional)',
                                  labelStyle: TextStyle(color: Colors.white70),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(color: Colors.white30),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(color: Colors.white30),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(color: Theme.of(context).colorScheme.primary),
                                  ),
                                  filled: true,
                                  fillColor: Colors.white.withOpacity(0.1),
                                ),
                                maxLines: 3,
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 32),

                      const SizedBox(height: 16),


                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}
