import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../services/data_service.dart';
import '../models/pedido.dart';
import '../models/cliente.dart';
import '../models/servico.dart';
import '../models/item_servico.dart';
import '../models/forma_pagamento.dart';
import '../widgets/pagamento_widget.dart';
import '../theme.dart';
import 'pdv_page.dart';

/// Página de lançamento de serviços com cadastro integrado
class LancarServicoPage extends StatefulWidget {
  final Pedido? pedidoExistente;
  final Cliente? clienteInicial;

  const LancarServicoPage({
    super.key,
    this.pedidoExistente,
    this.clienteInicial,
  });

  @override
  State<LancarServicoPage> createState() => _LancarServicoPageState();
}

class _LancarServicoPageState extends State<LancarServicoPage> {
  final _formKey = GlobalKey<FormState>();
  final _nomeServicoController = TextEditingController();
  final _descricaoController = TextEditingController();
  final _precoBaseController = TextEditingController();
  final _valorAdicionalController = TextEditingController();
  final _descricaoAdicionalController = TextEditingController();
  final _observacoesController = TextEditingController();

  // Estado do serviço
  Cliente? _clienteSelecionado;
  List<ItemServico> _servicosSelecionados = [];
  List<PagamentoPedido> _pagamentos = [];
  String _statusPedido = 'Pendente';
  String _numeroPedido = '';

  // Lista de status disponíveis
  final List<String> _statusDisponiveis = [
    'Pendente',
    'Em Andamento',
    'Concluído',
    'Cancelado',
  ];

  @override
  void initState() {
    super.initState();
    
    if (widget.pedidoExistente != null) {
      _carregarPedidoExistente();
    } else {
      if (widget.clienteInicial != null) {
        _clienteSelecionado = widget.clienteInicial;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _gerarNumeroPedido();
      });
    }
  }

  @override
  void dispose() {
    _nomeServicoController.dispose();
    _descricaoController.dispose();
    _precoBaseController.dispose();
    _valorAdicionalController.dispose();
    _descricaoAdicionalController.dispose();
    _observacoesController.dispose();
    super.dispose();
  }

  void _gerarNumeroPedido() {
    final dataService = Provider.of<DataService>(context, listen: false);
    setState(() {
      _numeroPedido = dataService.getProximoNumeroServico();
    });
  }

  void _carregarPedidoExistente() {
    final pedido = widget.pedidoExistente!;
    final dataService = Provider.of<DataService>(context, listen: false);

    _numeroPedido = pedido.numero;

    if (pedido.clienteId != null) {
      _clienteSelecionado = dataService.clientes
          .where((c) => c.id == pedido.clienteId)
          .firstOrNull;
    }

    _servicosSelecionados = List.from(pedido.servicos);
    _pagamentos = List.from(pedido.pagamentos);
    _statusPedido = pedido.status;
    _observacoesController.text = pedido.observacoes ?? '';
  }

  double get _totalServicos {
    final total = _servicosSelecionados.fold(
      0.0,
      (sum, item) => sum + item.valor + item.valorAdicional,
    );
    return total;
  }

  void _adicionarServico() {
    if (_nomeServicoController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Informe o nome do serviço'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final precoBase = double.tryParse(
          _precoBaseController.text.replaceAll(',', '.'),
        ) ??
        0.0;
    final valorAdicional = double.tryParse(
          _valorAdicionalController.text.replaceAll(',', '.'),
        ) ??
        0.0;

    if (precoBase <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Informe um preço válido'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final novoServico = ItemServico(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      descricao: _nomeServicoController.text,
      valor: precoBase,
      valorAdicional: valorAdicional,
      descricaoAdicional: _descricaoAdicionalController.text.isEmpty
          ? null
          : _descricaoAdicionalController.text,
    );

    setState(() {
      _servicosSelecionados.add(novoServico);
    });

    // Limpar campos
    _nomeServicoController.clear();
    _descricaoController.clear();
    _precoBaseController.clear();
    _valorAdicionalController.clear();
    _descricaoAdicionalController.clear();

    // Cadastrar serviço automaticamente se tiver valor adicional
    if (valorAdicional > 0) {
      _cadastrarServicoAutomaticamente(novoServico);
    }
  }

  void _cadastrarServicoAutomaticamente(ItemServico itemServico) {
    final dataService = Provider.of<DataService>(context, listen: false);
    final precoTotal = itemServico.valor + itemServico.valorAdicional;
    final nomeServico = itemServico.descricaoAdicional != null &&
            itemServico.descricaoAdicional!.isNotEmpty
        ? '${itemServico.descricao} - ${itemServico.descricaoAdicional}'
        : '${itemServico.descricao} (com adicional)';

    // Verificar se já existe
    final servicoExistente = dataService.servicos.firstWhere(
      (s) => s.nome == nomeServico && s.preco == precoTotal,
      orElse: () => Servico(
        id: '',
        nome: '',
        preco: 0,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );

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
      dataService.addTipoServico(novoServico);
    }
  }

  Future<void> _salvarPedido() async {
    if (_servicosSelecionados.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Adicione pelo menos um serviço'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final dataService = Provider.of<DataService>(context, listen: false);

    final pedido = Pedido(
      id: widget.pedidoExistente?.id ??
          DateTime.now().millisecondsSinceEpoch.toString(),
      numero: _numeroPedido,
      clienteId: _clienteSelecionado?.id,
      clienteNome: _clienteSelecionado?.nome,
      dataPedido: widget.pedidoExistente?.dataPedido ?? DateTime.now(),
      status: _statusPedido,
      total: _totalServicos,
      observacoes: _observacoesController.text.isNotEmpty
          ? _observacoesController.text
          : null,
      produtos: [],
      servicos: _servicosSelecionados,
      pagamentos: _pagamentos,
      createdAt: widget.pedidoExistente?.createdAt ?? DateTime.now(),
      updatedAt: DateTime.now(),
    );

    if (widget.pedidoExistente != null) {
      dataService.updatePedido(pedido);
      if (mounted) {
        Navigator.of(context).pop(pedido);
      }
    } else {
      await dataService.addPedido(pedido);
      
      // Navegar para a tela de receber (PDV) após salvar
      if (mounted) {
        Navigator.of(context).pop(); // Fechar a tela de lançamento
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => PdvPage(
              pedidoInicial: pedido,
              abaInicial: 0, // Aba de receber
            ),
          ),
        );
      }
    }
  }

  Color _getCorStatus(String status) {
    switch (status) {
      case 'Pendente':
        return Colors.orange;
      case 'Em Andamento':
        return Colors.blue;
      case 'Concluído':
        return Colors.green;
      case 'Cancelado':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final dataService = Provider.of<DataService>(context);
    final clientes = dataService.clientes;
    final isEdicao = widget.pedidoExistente != null;

    return AppTheme.appBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Column(
            children: [
              Text(isEdicao ? 'Editar Serviço' : 'Lançar Serviço'),
              if (_numeroPedido.isNotEmpty)
                Text(
                  _numeroPedido,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withOpacity(0.7),
                    fontWeight: FontWeight.normal,
                  ),
                ),
            ],
          ),
          centerTitle: true,
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
          actions: [
            TextButton.icon(
              onPressed: _servicosSelecionados.isNotEmpty ? _salvarPedido : null,
              icon: const Icon(Icons.save, color: Colors.white),
              label: Text(
                isEdicao ? 'Atualizar' : 'Salvar',
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Seleção de Cliente
                _buildSelecaoCliente(clientes),
                const SizedBox(height: 16),

                // Status
                _buildStatus(),
                const SizedBox(height: 16),

                // Seção de Buscar Serviço Cadastrado
                _buildBuscarServicoCadastrado(),
                const SizedBox(height: 16),

                // Divisor
                const Divider(),
                const SizedBox(height: 16),

                // Formulário de Cadastro de Serviço
                _buildFormularioServico(),
                const SizedBox(height: 16),

                // Botão Adicionar Serviço
                ElevatedButton.icon(
                  onPressed: _adicionarServico,
                  icon: const Icon(Icons.add),
                  label: const Text('Adicionar Serviço'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
                const SizedBox(height: 24),

                // Lista de Serviços Adicionados
                if (_servicosSelecionados.isNotEmpty) ...[
                  _buildListaServicos(),
                  const SizedBox(height: 24),
                ],

                // Tela de Pagamento
                _buildSecaoPagamentos(),

                // Observações
                const SizedBox(height: 16),
                TextField(
                  controller: _observacoesController,
                  maxLines: 3,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Observações',
                    labelStyle: const TextStyle(color: Colors.white70),
                    filled: true,
                    fillColor: Colors.black.withOpacity(0.3),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSelecaoCliente(List<Cliente> clientes) {
    return DropdownButtonFormField<Cliente?>(
      value: _clienteSelecionado,
      decoration: InputDecoration(
        labelText: 'Cliente (opcional)',
        labelStyle: const TextStyle(color: Colors.white70),
        prefixIcon: const Icon(Icons.person, color: Colors.white70),
        filled: true,
        fillColor: const Color(0xFF181A1B),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
      dropdownColor: const Color(0xFF23272A),
      style: const TextStyle(color: Colors.white),
      items: [
        const DropdownMenuItem<Cliente?>(
          value: null,
          child: Text(
            'Sem cliente',
            style: TextStyle(color: Colors.white70),
          ),
        ),
        ...clientes.map(
          (cliente) => DropdownMenuItem(
            value: cliente,
            child: Text(cliente.nome),
          ),
        ),
      ],
      onChanged: (cliente) {
        setState(() {
          _clienteSelecionado = cliente;
        });
      },
    );
  }

  Widget _buildStatus() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: _getCorStatus(_statusPedido),
        borderRadius: BorderRadius.circular(20),
      ),
      child: DropdownButton<String>(
        value: _statusPedido,
        underline: const SizedBox(),
        dropdownColor: const Color(0xFF23272A),
        isDense: true,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 14,
        ),
        icon: const Icon(Icons.arrow_drop_down, color: Colors.white, size: 20),
        items: _statusDisponiveis.map(
          (status) => DropdownMenuItem(
            value: status,
            child: Text(status, style: const TextStyle(fontSize: 14)),
          ),
        ).toList(),
        onChanged: (status) {
          if (status != null) {
            setState(() {
              _statusPedido = status;
            });
          }
        },
      ),
    );
  }

  Widget _buildBuscarServicoCadastrado() {
    final dataService = Provider.of<DataService>(context);
    final servicosCadastrados = dataService.servicos;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.green.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Buscar Serviço Cadastrado',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Autocomplete<Servico>(
            optionsBuilder: (TextEditingValue textEditingValue) {
              if (textEditingValue.text.isEmpty) {
                return servicosCadastrados;
              }
              return servicosCadastrados.where(
                (Servico s) => s.nome.toLowerCase().contains(
                      textEditingValue.text.toLowerCase(),
                    ),
              );
            },
            displayStringForOption: (Servico s) => 
                '${s.nome} - R\$ ${NumberFormat.currency(locale: 'pt_BR', symbol: '').format(s.preco)}',
            fieldViewBuilder:
                (context, controller, focusNode, onFieldSubmitted) {
              return TextField(
                controller: controller,
                focusNode: focusNode,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Buscar serviço...',
                  labelStyle: const TextStyle(color: Colors.white70),
                  hintText: 'Digite o nome do serviço',
                  hintStyle: const TextStyle(color: Colors.white54),
                  prefixIcon: const Icon(Icons.search, color: Colors.white70),
                  filled: true,
                  fillColor: const Color(0xFF181A1B),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              );
            },
            onSelected: (Servico servico) {
              // Preencher os campos do formulário automaticamente com os dados do serviço selecionado
              String nomeServico = servico.nome;
              String? descricaoAdicional;
              double valorBase = servico.preco;
              double valorAdicional = 0.0;
              
              // Verificar se o nome contém indicação de adicional (ex: "Nome - Descrição Adicional")
              if (servico.nome.contains(' - ')) {
                final partes = servico.nome.split(' - ');
                if (partes.length > 1) {
                  nomeServico = partes[0];
                  descricaoAdicional = partes[1];
                }
              }
              
              // Tentar extrair valor adicional da descrição se houver informação
              if (servico.descricao != null && servico.descricao!.isNotEmpty) {
                // Verificar se a descrição menciona valor adicional
                final regexAdicional = RegExp(r'adicional.*?R\$?\s*([\d,\.]+)', caseSensitive: false);
                final match = regexAdicional.firstMatch(servico.descricao!);
                if (match != null) {
                  final valorEncontrado = double.tryParse(match.group(1)!.replaceAll(',', '.')) ?? 0.0;
                  if (valorEncontrado > 0 && valorEncontrado < servico.preco) {
                    valorAdicional = valorEncontrado;
                    valorBase = servico.preco - valorAdicional;
                    if (descricaoAdicional == null) {
                      descricaoAdicional = servico.descricao;
                    }
                  }
                } else if (descricaoAdicional == null) {
                  descricaoAdicional = servico.descricao;
                }
              }

              // Preencher os campos do formulário
              setState(() {
                _nomeServicoController.text = nomeServico;
                _descricaoController.text = servico.descricao ?? '';
                _precoBaseController.text = valorBase.toStringAsFixed(2);
                _valorAdicionalController.text = valorAdicional.toStringAsFixed(2);
                _descricaoAdicionalController.text = descricaoAdicional ?? '';
              });

              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Serviço "${nomeServico}" carregado! Preencha os campos e clique em "Adicionar Serviço"',
                  ),
                  backgroundColor: Colors.blue,
                  duration: const Duration(seconds: 3),
                ),
              );
            },
            optionsViewBuilder: (context, onSelected, options) {
              return Align(
                alignment: Alignment.topLeft,
                child: Material(
                  color: const Color(0xFF23272A),
                  borderRadius: BorderRadius.circular(12),
                  elevation: 4,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 200),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: options.length,
                      itemBuilder: (context, index) {
                        final servico = options.elementAt(index);
                        return ListTile(
                          title: Text(
                            servico.nome,
                            style: const TextStyle(color: Colors.white),
                          ),
                          subtitle: Text(
                            'R\$ ${NumberFormat.currency(locale: 'pt_BR', symbol: '').format(servico.preco)}',
                            style: const TextStyle(color: Colors.white70),
                          ),
                          onTap: () => onSelected(servico),
                        );
                      },
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildFormularioServico() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.blue.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Cadastrar Novo Serviço',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _nomeServicoController,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: 'Nome do Serviço *',
              labelStyle: const TextStyle(color: Colors.white70),
              filled: true,
              fillColor: const Color(0xFF181A1B),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _descricaoController,
            style: const TextStyle(color: Colors.white),
            maxLines: 2,
            decoration: InputDecoration(
              labelText: 'Descrição',
              labelStyle: const TextStyle(color: Colors.white70),
              filled: true,
              fillColor: const Color(0xFF181A1B),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _precoBaseController,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Preço Base (R\$) *',
                    labelStyle: const TextStyle(color: Colors.white70),
                    filled: true,
                    fillColor: const Color(0xFF181A1B),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _valorAdicionalController,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Valor Adicional (R\$)',
                    labelStyle: const TextStyle(color: Colors.white70),
                    filled: true,
                    fillColor: const Color(0xFF181A1B),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _descricaoAdicionalController,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: 'Descrição do Valor Adicional',
              labelStyle: const TextStyle(color: Colors.white70),
              filled: true,
              fillColor: const Color(0xFF181A1B),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildListaServicos() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.3),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Serviços Adicionados',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          ..._servicosSelecionados.map(
            (item) => Card(
              color: const Color(0xFF181A1B),
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: Text(
                  item.descricao,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Base: ${NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(item.valor)}',
                      style: const TextStyle(color: Colors.white70),
                    ),
                    if (item.valorAdicional > 0) ...[
                      Text(
                        'Adicional: ${NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(item.valorAdicional)}',
                        style: const TextStyle(color: Colors.white70),
                      ),
                      if (item.descricaoAdicional != null)
                        Text(
                          'Descrição: ${item.descricaoAdicional}',
                          style: const TextStyle(color: Colors.white54, fontSize: 12),
                        ),
                    ],
                    Text(
                      'Total: ${NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(item.valor + item.valorAdicional)}',
                      style: const TextStyle(
                        color: Colors.greenAccent,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () {
                    setState(() {
                      _servicosSelecionados.remove(item);
                    });
                  },
                ),
              ),
            ),
          ),
          const Divider(color: Colors.white24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Total:',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(_totalServicos),
                style: const TextStyle(
                  color: Colors.greenAccent,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSecaoPagamentos() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.purple.withOpacity(0.3)),
      ),
      child: PagamentoWidget(
        totalPedido: _totalServicos,
        pagamentos: _pagamentos,
        clienteId: _clienteSelecionado?.id,
        onPagamentosChanged: (novosPagamentos) {
          setState(() {
            _pagamentos = novosPagamentos;
          });
        },
      ),
    );
  }
}

