import 'package:flutter/material.dart';
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
import 'package:sistema_exodo_novo/models/comissao_vendedor.dart';
import 'package:sistema_exodo_novo/models/produto.dart';
import 'package:sistema_exodo_novo/services/data_service.dart';
import 'package:sistema_exodo_novo/services/auth_service.dart';
import 'package:sistema_exodo_novo/services/cliente_auth_service.dart';
import 'package:sistema_exodo_novo/services/frete_service.dart';
import 'package:sistema_exodo_novo/models/opcao_frete.dart';
import 'package:sistema_exodo_novo/models/zona_entrega.dart';
import 'package:sistema_exodo_novo/pages/cliente_cadastro_page.dart';
import 'package:sistema_exodo_novo/theme.dart';
import 'package:sistema_exodo_novo/services/carrinho_service.dart';
import 'package:intl/intl.dart';

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

  bool _isLoading = false;
  bool _buscandoCep = false;
  bool _calculandoFrete = false;
  double _valorFrete = 0.0;
  int _prazoFrete = 0; // Prazo em dias úteis
  bool _freteCalculado = false;
  String? _estadoLoja;
  String? _cepLoja;
  String? _bairroLoja;
  String? _cidadeLoja;
  List<OpcaoFrete> _opcoesFrete = [];
  OpcaoFrete? _opcaoFreteSelecionada;

  @override
  void initState() {
    super.initState();
    _carregarDadosLoja();
    _carregarDadosCliente();

    // Inicializar frete se houver uma opção inicial
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
      
      // Calcular frete automaticamente se tiver CEP
      if (cliente.cep != null && cliente.cep!.replaceAll(RegExp(r'[^\d]'), '').length == 8) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _calcularFrete();
        });
      }
    }
  }

  /// Navega para página de cadastro e retorna com dados preenchidos
  Future<void> _irParaCadastro() async {
    final resultado = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => const ClienteCadastroPage(),
      ),
    );

    if (resultado == true) {
      // Recarregar dados do cliente após cadastro
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

  double _calcularTotalComFrete() {
    final frete = _opcaoFreteSelecionada?.valor ?? _valorFrete;
    return _calcularTotal() + frete;
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
        final pesoProduto = produto.pesoGramas ?? 500; // Peso padrão 500g
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
          content: Text('CEP deve ter 8 dígitos'),
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

      // Calcular frete automaticamente após buscar CEP
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
      
      // Obter valor mínimo para frete grátis da configuração
      final empresa = authService.empresaAtual;
      final valorMinimoFreteGratis = empresa?.configuracoes?['ecommerce']?['valorFreteGratis'] as num? ?? 399.90;

      // Limpar CEPs para garantir formato correto
      final cepDestinoLimpo = _cepController.text.replaceAll(RegExp(r'[^\d]'), '');
      
      // Obter configurações de frete do e-commerce
      final configFrete = empresa?.configuracoes?['ecommerce']?['frete'] as Map<String, dynamic>?;
      
      // Carregar Zonas de Entrega Inteligentes
      final zonasData = configFrete?['zonasEntrega'] as List<dynamic>? ?? [];
      final zonasEntrega = zonasData
          .map((z) => ZonaEntrega.fromMap(z as Map<String, dynamic>))
          .toList();
      
      // Configurar credenciais das transportadoras (se disponíveis)
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
      
      // Calcular todas as opções de frete (SISTEMA HÍBRIDO)
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
        debugPrint('>>> [Checkout] Opções de frete calculadas: ${opcoes.length}');
        for (var opcao in opcoes) {
          debugPrint('>>> [Checkout] - ${opcao.nome}: R\$ ${opcao.valor.toStringAsFixed(2)} (${opcao.prazo} dias)');
        }
        
        setState(() {
          _opcoesFrete = opcoes;
          // Selecionar automaticamente a primeira opção (geralmente a mais barata)
          if (opcoes.isNotEmpty) {
            _opcaoFreteSelecionada = opcoes.first;
            _valorFrete = opcoes.first.valor;
            _prazoFrete = opcoes.first.prazo;
            debugPrint('>>> [Checkout] Opção selecionada: ${opcoes.first.nome}');
          } else {
            debugPrint('>>> [Checkout] ⚠️ Nenhuma opção de frete encontrada!');
          }
          _freteCalculado = true;
          _calculandoFrete = false;
        });

        // Mostrar mensagem de sucesso
        if (opcoes.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${opcoes.length} opção(ões) de frete encontrada(s)!'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Nenhuma opção de frete disponível. Verifique os dados informados.'),
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

  String _gerarNumeroPedido() {
    final dataService = Provider.of<DataService>(context, listen: false);
    final pedidos = dataService.pedidos;
    final ultimoNumero = pedidos.isEmpty
        ? 0
        : pedidos
            .map((p) {
              final match = RegExp(r'PED-(\d+)').firstMatch(p.numero);
              return match != null ? int.parse(match.group(1)!) : 0;
            })
            .reduce((a, b) => a > b ? a : b);
    return 'PED-${(ultimoNumero + 1).toString().padLeft(4, '0')}';
  }

  Future<void> _finalizarPedido() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    // Validar se o frete foi calculado e uma opção foi selecionada
    if (!_freteCalculado || _opcoesFrete.isEmpty) {
      if (_estadoController.text.isNotEmpty) {
        await _calcularFrete();
        // Aguardar um pouco para as opções serem calculadas
        await Future.delayed(const Duration(milliseconds: 500));
      }
      
      if (!_freteCalculado || _opcoesFrete.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Por favor, calcule e selecione uma opção de frete antes de finalizar o pedido.'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 3),
          ),
        );
        return;
      }
    }
    
    if (_opcaoFreteSelecionada == null && _opcoesFrete.isNotEmpty) {
      // Se não selecionou, selecionar a primeira automaticamente
      setState(() {
        _opcaoFreteSelecionada = _opcoesFrete.first;
        _valorFrete = _opcoesFrete.first.valor;
        _prazoFrete = _opcoesFrete.first.prazo;
      });
    }
    
    if (_opcaoFreteSelecionada == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Por favor, selecione uma opção de frete antes de finalizar o pedido.'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final dataService = Provider.of<DataService>(context, listen: false);

      // Criar ou buscar cliente
      Cliente? cliente;
      final clientes = dataService.clientes;
      final cpfLimpo = _cpfController.text.replaceAll(RegExp(r'[^\d]'), '');
      
      Cliente? clienteExistente;
      try {
        clienteExistente = clientes.firstWhere(
          (c) => c.cpfCnpj != null && 
                 c.cpfCnpj!.replaceAll(RegExp(r'[^\d]'), '') == cpfLimpo && 
                 cpfLimpo.isNotEmpty,
        );
      } catch (e) {
        clienteExistente = null;
      }

      if (clienteExistente != null) {
        // Atualizar cliente existente
        cliente = clienteExistente.copyWith(
          nome: _nomeController.text.trim(),
          telefone: _telefoneController.text.trim(),
          email: _emailController.text.trim().isNotEmpty ? _emailController.text.trim() : null,
          endereco: _enderecoController.text.trim(),
          numero: _numeroController.text.trim(),
          complemento: _complementoController.text.trim().isNotEmpty ? _complementoController.text.trim() : null,
          bairro: _bairroController.text.trim(),
          cidade: _cidadeController.text.trim(),
          estado: _estadoController.text.trim(),
          cep: _cepController.text.trim(),
          updatedAt: DateTime.now(),
        );
        dataService.updateCliente(cliente);
      } else {
        // Criar novo cliente
        cliente = Cliente(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          nome: _nomeController.text.trim(),
          telefone: _telefoneController.text.trim(),
          email: _emailController.text.trim().isNotEmpty ? _emailController.text.trim() : null,
          cpfCnpj: cpfLimpo.isNotEmpty ? cpfLimpo : null,
          endereco: _enderecoController.text.trim(),
          numero: _numeroController.text.trim(),
          complemento: _complementoController.text.trim().isNotEmpty ? _complementoController.text.trim() : null,
          bairro: _bairroController.text.trim(),
          cidade: _cidadeController.text.trim(),
          estado: _estadoController.text.trim(),
          cep: _cepController.text.trim(),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        await dataService.addCliente(cliente);
      }

      // Montar endereço completo
      final enderecoCompleto = [
        _enderecoController.text.trim(),
        _numeroController.text.trim(),
        _complementoController.text.trim(),
        _bairroController.text.trim(),
        _cidadeController.text.trim(),
        _estadoController.text.trim(),
        _cepController.text.trim(),
      ].where((s) => s.isNotEmpty).join(', ');

      // Converter carrinho para itens de pedido
      final carrinhoService = Provider.of<CarrinhoService>(context, listen: false);
      final produtos = carrinhoService.itens
          .where((item) => item.isProduto)
          .map((item) => ItemPedido(
                id: item.itemId,
                nome: item.nome,
                quantidade: item.quantidade,
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

      // Criar pedido
      final totalComFrete = _calcularTotalComFrete();
      final pedido = Pedido(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        numero: _gerarNumeroPedido(),
        clienteId: cliente.id,
        clienteNome: cliente.nome,
        clienteTelefone: cliente.telefone,
        clienteEndereco: enderecoCompleto,
        clienteCpfCnpj: cliente.cpfCnpj,
        vendedorId: widget.linkVendedor?.funcionarioId,
        vendedorNome: widget.linkVendedor?.funcionarioNome,
        linkVendedorId: widget.linkVendedor?.id,
        linkVendedorCodigo: widget.linkVendedor?.codigoLink,
        origemEcommerce: true, // SEMPRE marcar como pedido do e-commerce
        dataPedido: DateTime.now(),
        status: 'Pendente',
        total: totalComFrete,
        observacoes: _observacoesController.text.trim().isNotEmpty
            ? '${_observacoesController.text.trim()}\nFrete: ${_opcaoFreteSelecionada?.nome ?? "Padrão"} - R\$ ${(_opcaoFreteSelecionada?.valor ?? _valorFrete).toStringAsFixed(2)} (${_opcaoFreteSelecionada?.prazo ?? _prazoFrete} dia${(_opcaoFreteSelecionada?.prazo ?? _prazoFrete) > 1 ? 's' : ''} útil${(_opcaoFreteSelecionada?.prazo ?? _prazoFrete) > 1 ? 'eis' : ''})'
            : 'Frete: ${_opcaoFreteSelecionada?.nome ?? "Padrão"} - R\$ ${(_opcaoFreteSelecionada?.valor ?? _valorFrete).toStringAsFixed(2)} (${_opcaoFreteSelecionada?.prazo ?? _prazoFrete} dia${(_opcaoFreteSelecionada?.prazo ?? _prazoFrete) > 1 ? 's' : ''} útil${(_opcaoFreteSelecionada?.prazo ?? _prazoFrete) > 1 ? 'eis' : ''})',
        produtos: produtos,
        servicos: servicos,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      // Salvar pedido
      await dataService.addPedido(pedido);

      // Criar comissão se houver link de vendedor
      if (widget.linkVendedor != null && widget.linkVendedor!.id.isNotEmpty) {
        final valorComissao = totalComFrete * (widget.linkVendedor!.percentualComissao / 100);
        
        final comissao = ComissaoVendedor(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          linkVendedorId: widget.linkVendedor!.id,
          funcionarioId: widget.linkVendedor!.funcionarioId,
          funcionarioNome: widget.linkVendedor!.funcionarioNome,
          pedidoId: pedido.id,
          pedidoNumero: pedido.numero,
          valorPedido: totalComFrete,
          percentualComissao: widget.linkVendedor!.percentualComissao,
          valorComissao: valorComissao,
          status: 'Pendente',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        await dataService.addComissaoVendedor(comissao);

        // Atualizar estatísticas do link
        final linkAtualizado = widget.linkVendedor!.copyWith(
          totalVendas: widget.linkVendedor!.totalVendas + 1,
          totalComissao: widget.linkVendedor!.totalComissao + valorComissao,
          updatedAt: DateTime.now(),
        );
        await dataService.updateLinkVendedor(linkAtualizado);
      }

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Pedido ${pedido.numero} criado com sucesso!'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
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
                              ),
                              const Divider(color: Colors.white24),
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
                              if ((Provider.of<AuthService>(context, listen: false).empresaAtual?.moduloPet ?? false) && _freteCalculado && !_calculandoFrete && _opcoesFrete.isNotEmpty) ...[
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
                                                          '${opcao.prazo} dia${opcao.prazo > 1 ? 's' : ''} útil${opcao.prazo > 1 ? 'eis' : ''}',
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
                                                          ? 'GRÁTIS'
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
                                // Resumo da seleção
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
                                                'Prazo: ${_opcaoFreteSelecionada!.prazo} dia${_opcaoFreteSelecionada!.prazo > 1 ? 's' : ''} útil${_opcaoFreteSelecionada!.prazo > 1 ? 'eis' : ''} | Valor: ${_opcaoFreteSelecionada!.valor == 0.0 ? 'GRÁTIS' : formatoMoeda.format(_opcaoFreteSelecionada!.valor)}',
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
                                          'Nenhuma opção de frete disponível. Verifique o CEP.',
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

                      // Banner de cadastro (se não estiver logado)
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
                                        'Crie sua conta',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Cadastre-se para não precisar preencher seus dados toda vez',
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
                                          'Seus dados foram preenchidos automaticamente. Você pode editá-los se necessário.',
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
                                    return 'Campo obrigatório';
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
                                      ),
                                      validator: (value) {
                                        if (value == null || value.trim().isEmpty) {
                                          return 'Campo obrigatório';
                                        }
                                        final digits = value.replaceAll(RegExp(r'[^\d]'), '');
                                        if (digits.length < 10) {
                                          return 'Telefone inválido';
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

                      // Endereço
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
                                    'Endereço de Entrega',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              // CEP com botão de busca
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
                                          return 'Campo obrigatório';
                                        }
                                        final digits = value.replaceAll(RegExp(r'[^\d]'), '');
                                        if (digits.length != 8) {
                                          return 'CEP inválido';
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
                                  labelText: 'Endereço *',
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
                                    return 'Campo obrigatório';
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
                                        labelText: 'Número *',
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
                                          return 'Campo obrigatório';
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
                              TextFormField(
                                controller: _bairroController,
                                style: const TextStyle(color: Colors.white),
                                decoration: InputDecoration(
                                  labelText: 'Bairro *',
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
                                    return 'Campo obrigatório';
                                  }
                                  return null;
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
                                          return 'Campo obrigatório';
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
                                          return 'Campo obrigatório';
                                        }
                                        if (value.length != 2) {
                                          return 'UF inválida';
                                        }
                                        return null;
                                      },
                                      onChanged: (value) {
                                        if (value.length == 2 && _estadoLoja != null) {
                                          // Aguardar um pouco antes de calcular para evitar múltiplas chamadas
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
                              // Botão para calcular frete manualmente
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

                      const SizedBox(height: 24),

                      // Observações
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
                                    'Observações',
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
                                  labelText: 'Observações adicionais (opcional)',
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
