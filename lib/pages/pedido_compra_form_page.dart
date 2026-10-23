import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../custom_app_bar.dart';
import '../models/estoque.dart';
import '../models/pedido_compra.dart';
import '../models/produto.dart';
import '../services/auth_service.dart';
import '../services/data_service.dart';
import '../theme.dart';
import '../utils/units.dart' as units;

/// Cadastro/edição de um pedido de compra.
///
/// O pedido nasce como rascunho; o botão "Salvar e enviar" já registra o envio
/// ao fornecedor. Depois de enviado, o pedido só pode ser recebido ou
/// cancelado (a edição fica disponível apenas enquanto for rascunho).
class PedidoCompraFormPage extends StatefulWidget {
  final PedidoCompra? pedido;

  const PedidoCompraFormPage({super.key, this.pedido});

  @override
  State<PedidoCompraFormPage> createState() => _PedidoCompraFormPageState();
}

class _PedidoCompraFormPageState extends State<PedidoCompraFormPage> {
  final TextEditingController _fornecedorController = TextEditingController();
  final TextEditingController _observacaoController = TextEditingController();
  final List<_ItemFormulario> _itens = [];

  DateTime? _previsaoEntrega;
  String _fornecedorId = '';
  String? _estoqueDestinoId;
  bool _salvando = false;

  static final NumberFormat _moeda = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: 'R\$',
  );
  static final DateFormat _data = DateFormat('dd/MM/yyyy');

  bool get _editando => widget.pedido != null;

  @override
  void initState() {
    super.initState();
    final pedido = widget.pedido;
    if (pedido == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final service = Provider.of<DataService>(context, listen: false);
        setState(() {
          _estoqueDestinoId = service.estoquePrincipalAtual?.id;
        });
      });
      return;
    }

    _fornecedorController.text = pedido.fornecedorNome;
    _observacaoController.text = pedido.observacao ?? '';
    _fornecedorId = pedido.fornecedorId;
    _previsaoEntrega = pedido.previsaoEntrega;
    _estoqueDestinoId = pedido.estoqueDestinoId;
    for (final item in pedido.itens) {
      _itens.add(
        _ItemFormulario(
          id: item.id,
          produtoId: item.produtoId,
          produtoNome: item.produtoNome,
          codigo: item.codigo,
          unidade: item.unidade,
          quantidade: item.quantidade,
          quantidadeRecebida: item.quantidadeRecebida,
          precoCusto: item.precoCusto,
        ),
      );
    }
  }

  @override
  void dispose() {
    _fornecedorController.dispose();
    _observacaoController.dispose();
    for (final item in _itens) {
      item.dispose();
    }
    super.dispose();
  }

  double get _totalPedido =>
      _itens.fold(0.0, (total, item) => total + item.valorTotal);

  double get _quantidadeTotal =>
      _itens.fold(0.0, (total, item) => total + item.quantidadeValor);

  Future<void> _escolherFornecedor() async {
    final service = Provider.of<DataService>(context, listen: false);
    final sugestoes = <String, String>{};
    for (final produto in service.produtos) {
      final nome = (produto.fornecedorNome ?? '').trim();
      if (nome.isEmpty) continue;
      final id = (produto.fornecedorId ?? '').trim();
      if (!sugestoes.containsKey(nome) || sugestoes[nome]!.isEmpty) {
        sugestoes[nome] = id;
      }
    }
    final nomes = sugestoes.keys.toList()..sort();

    final escolhido = await showDialog<String>(
      context: context,
      builder: (ctx) => _SeletorFornecedorDialog(nomes: nomes),
    );
    if (escolhido == null || escolhido.isEmpty) return;
    setState(() {
      _fornecedorController.text = escolhido;
      _fornecedorId = sugestoes[escolhido] ?? '';
    });
  }

  Future<void> _adicionarProduto() async {
    final service = Provider.of<DataService>(context, listen: false);
    final selecionado = await showDialog<Produto>(
      context: context,
      builder: (ctx) => _SeletorProdutoDialog(produtos: service.produtos),
    );
    if (selecionado == null || !mounted) return;

    setState(() {
      _ItemFormulario? existente;
      for (final item in _itens) {
        if (item.produtoId == selecionado.id) {
          existente = item;
          break;
        }
      }
      if (existente != null) {
        existente.quantidade.text = units.formatarNumero(
          existente.quantidadeValor + 1,
        );
        return;
      }

      final falta = selecionado.estoqueMinimo - selecionado.estoque;
      final quantidade = falta > 0 ? falta : 1.0;
      _itens.add(
        _ItemFormulario(
          id: '',
          produtoId: selecionado.id,
          produtoNome: selecionado.nome,
          codigo: selecionado.codigo,
          unidade: selecionado.unidade,
          quantidade: quantidade,
          quantidadeRecebida: 0,
          precoCusto: selecionado.precoCusto ?? 0,
        ),
      );
    });
  }

  Future<void> _escolherPrevisao() async {
    final agora = DateTime.now();
    final escolhida = await showDatePicker(
      context: context,
      initialDate: _previsaoEntrega ?? agora.add(const Duration(days: 7)),
      firstDate: DateTime(agora.year - 1),
      lastDate: DateTime(agora.year + 5),
      helpText: 'Previsão de entrega',
      cancelText: 'Cancelar',
      confirmText: 'Confirmar',
    );
    if (escolhida == null) return;
    setState(() => _previsaoEntrega = escolhida);
  }

  String? _validar() {
    if (_fornecedorController.text.trim().isEmpty) {
      return 'Informe o fornecedor do pedido.';
    }
    if (_itens.isEmpty) {
      return 'Adicione pelo menos um produto ao pedido.';
    }
    if (_itens.any((item) => item.quantidadeValor <= 0)) {
      return 'Todas as quantidades precisam ser maiores que zero.';
    }
    return null;
  }

  Future<void> _salvar({required bool enviar}) async {
    if (_salvando) return;
    final erro = _validar();
    if (erro != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(erro), backgroundColor: Colors.orange.shade800),
      );
      return;
    }

    setState(() => _salvando = true);
    final service = Provider.of<DataService>(context, listen: false);
    final auth = Provider.of<AuthService>(context, listen: false);
    final usuario = auth.usuarioAtual?.nome ?? auth.usuarioAtual?.email;
    final fornecedor = _fornecedorController.text.trim();
    final observacao = _observacaoController.text.trim();
    final itens = _itens
        .map(
          (item) => ItemPedidoCompra(
            id: item.id,
            produtoId: item.produtoId,
            produtoNome: item.produtoNome,
            codigo: item.codigo,
            unidade: item.unidade,
            quantidade: item.quantidadeValor,
            quantidadeRecebida: item.quantidadeRecebida,
            precoCusto: item.valorCusto,
          ),
        )
        .toList();
    final estoqueNome = _estoqueDestinoId == null
        ? null
        : nomeDoEstoque(service.estoques, _estoqueDestinoId);

    try {
      if (_editando) {
        final original = widget.pedido!;
        final atualizado = PedidoCompra(
          id: original.id,
          numero: original.numero,
          fornecedorId: _fornecedorId,
          fornecedorNome: fornecedor,
          fornecedorCnpj: original.fornecedorCnpj,
          fornecedorTelefone: original.fornecedorTelefone,
          status: enviar ? StatusPedidoCompra.enviado : original.status,
          itens: itens,
          observacao: observacao.isEmpty ? null : observacao,
          usuario: usuario ?? original.usuario,
          estoqueDestinoId: _estoqueDestinoId,
          estoqueDestinoNome: estoqueNome,
          dataCriacao: original.dataCriacao,
          dataEnvio: enviar
              ? (original.dataEnvio ?? DateTime.now())
              : original.dataEnvio,
          previsaoEntrega: _previsaoEntrega,
          dataRecebimento: original.dataRecebimento,
          dataCancelamento: original.dataCancelamento,
          motivoCancelamento: original.motivoCancelamento,
          createdAt: original.createdAt,
        );
        await service.atualizarPedidoCompra(atualizado);
        if (!mounted) return;
        Navigator.pop(context, atualizado);
      } else {
        final criado = await service.criarPedidoCompra(
          fornecedorNome: fornecedor,
          fornecedorId: _fornecedorId,
          itens: itens,
          observacao: observacao.isEmpty ? null : observacao,
          usuario: usuario,
          previsaoEntrega: _previsaoEntrega,
          estoqueDestinoId: _estoqueDestinoId,
          estoqueDestinoNome: estoqueNome,
          enviar: enviar,
        );
        if (!mounted) return;
        Navigator.pop(context, criado);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _salvando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Não foi possível salvar o pedido: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = Provider.of<DataService>(context);
    final estoques = service.estoques;
    final titulo = _editando
        ? 'Editar Pedido ${widget.pedido!.numero}'
        : 'Novo Pedido de Compra';

    return AppTheme.appBackground(
      child: Scaffold(
        appBar: CustomAppBar(title: titulo),
        body: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                children: [
                  _cardFornecedor(estoques),
                  const SizedBox(height: 14),
                  _cabecalhoItens(),
                  const SizedBox(height: 8),
                  if (_itens.isEmpty) _estadoItensVazio(),
                  ..._itens.map(_construirItem),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _salvando ? null : _adicionarProduto,
                    icon: const Icon(Icons.add_shopping_cart_rounded),
                    label: const Text('ADICIONAR PRODUTO'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.cyanAccent,
                      side: BorderSide(
                        color: Colors.cyanAccent.withOpacity(0.45),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _cardObservacoes(),
                ],
              ),
            ),
            _barraSalvar(),
          ],
        ),
      ),
    );
  }

  Widget _cardFornecedor(List<Estoque> estoques) {
    final estoqueSelecionado =
        estoques.any((estoque) => estoque.id == _estoqueDestinoId)
        ? _estoqueDestinoId
        : null;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'DADOS DO PEDIDO',
            style: TextStyle(
              color: Colors.white38,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _fornecedorController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Fornecedor *',
                    hintText: 'Nome do fornecedor',
                    prefixIcon: const Icon(Icons.local_shipping_outlined),
                    suffixIcon: IconButton(
                      tooltip: 'Escolher fornecedor já cadastrado nos produtos',
                      onPressed: _escolherFornecedor,
                      icon: const Icon(Icons.list_alt_rounded),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: _escolherPrevisao,
                  borderRadius: BorderRadius.circular(12),
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: 'Previsão de entrega',
                      prefixIcon: const Icon(Icons.event_outlined),
                      suffixIcon: _previsaoEntrega == null
                          ? const Icon(Icons.arrow_drop_down)
                          : IconButton(
                              tooltip: 'Limpar previsão',
                              onPressed: () =>
                                  setState(() => _previsaoEntrega = null),
                              icon: const Icon(Icons.close, size: 18),
                            ),
                    ),
                    child: Text(
                      _previsaoEntrega == null
                          ? 'Sem data definida'
                          : _data.format(_previsaoEntrega!),
                      style: TextStyle(
                        color: _previsaoEntrega == null
                            ? Colors.white38
                            : Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String?>(
                  value: estoqueSelecionado,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Estoque de destino',
                    prefixIcon: Icon(Icons.warehouse_outlined),
                  ),
                  dropdownColor: const Color(0xFF1E1E2E),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Estoque principal'),
                    ),
                    ...estoques.map(
                      (estoque) => DropdownMenuItem<String?>(
                        value: estoque.id,
                        child: Text(
                          estoque.principal
                              ? '${estoque.nome} (principal)'
                              : estoque.nome,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                  onChanged: (valor) =>
                      setState(() => _estoqueDestinoId = valor),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _cabecalhoItens() {
    return Row(
      children: [
        const Icon(
          Icons.shopping_basket_outlined,
          color: Colors.cyanAccent,
          size: 18,
        ),
        const SizedBox(width: 8),
        const Text(
          'ITENS DO PEDIDO',
          style: TextStyle(
            color: Colors.white70,
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
        const Spacer(),
        Text(
          '${_itens.length} item(ns)',
          style: const TextStyle(color: Colors.white38, fontSize: 11),
        ),
      ],
    );
  }

  Widget _estadoItensVazio() {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.02),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        children: [
          Icon(
            Icons.shopping_cart_outlined,
            size: 42,
            color: Colors.white.withOpacity(0.15),
          ),
          const SizedBox(height: 10),
          Text(
            'Nenhum produto no pedido.\nUse "Adicionar produto" para começar.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withOpacity(0.35),
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _construirItem(_ItemFormulario item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: Colors.cyanAccent.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(
                  Icons.inventory_2_outlined,
                  color: Colors.cyanAccent,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.produtoNome,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        if ((item.codigo ?? '').isNotEmpty)
                          'Cód.: ${item.codigo}',
                        'Un.: ${item.unidade}',
                        if (item.quantidadeRecebida > 0)
                          'Já recebido: ${units.formatarNumero(item.quantidadeRecebida)}',
                      ].join('  •  '),
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 9.5,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Remover item',
                onPressed: () => setState(() {
                  _itens.remove(item);
                  item.dispose();
                }),
                icon: const Icon(
                  Icons.delete_outline_rounded,
                  color: Colors.redAccent,
                  size: 19,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: item.quantidade,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.cyanAccent,
                    fontWeight: FontWeight.bold,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Quantidade',
                    isDense: true,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 3,
                child: TextField(
                  controller: item.custo,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Custo unit. (R\$)',
                    isDense: true,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: Container(
                  height: 48,
                  alignment: Alignment.centerRight,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text(
                        'TOTAL',
                        style: TextStyle(color: Colors.white38, fontSize: 8),
                      ),
                      Text(
                        _moeda.format(item.valorTotal),
                        style: const TextStyle(
                          color: Color(0xFF00FF9D),
                          fontSize: 13,
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
    );
  }

  Widget _cardObservacoes() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: TextField(
        controller: _observacaoController,
        maxLines: 3,
        style: const TextStyle(color: Colors.white),
        decoration: const InputDecoration(
          labelText: 'Observação do pedido',
          hintText: 'Prazo, condições de pagamento, frete...',
          alignLabelWithHint: true,
          prefixIcon: Icon(Icons.notes_rounded),
        ),
      ),
    );
  }

  Widget _barraSalvar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        border: Border(top: BorderSide(color: Colors.white.withOpacity(0.07))),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text(
                  '${units.formatarNumero(_quantidadeTotal)} item(ns)',
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
                const Spacer(),
                const Text(
                  'TOTAL DO PEDIDO: ',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  _moeda.format(_totalPedido),
                  style: const TextStyle(
                    color: Color(0xFF00FF9D),
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _salvando ? null : () => _salvar(enviar: false),
                    icon: const Icon(Icons.save_outlined, size: 18),
                    label: Text(
                      _editando ? 'SALVAR ALTERAÇÕES' : 'SALVAR RASCUNHO',
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white70,
                      side: BorderSide(color: Colors.white.withOpacity(0.2)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _salvando ? null : () => _salvar(enviar: true),
                    icon: _salvando
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send_rounded, size: 18),
                    label: const Text('SALVAR E ENVIAR'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Item em edição no formulário (guarda os controllers de quantidade/custo).
class _ItemFormulario {
  final String id;
  final String produtoId;
  final String produtoNome;
  final String? codigo;
  final String unidade;
  final double quantidadeRecebida;
  final TextEditingController quantidade;
  final TextEditingController custo;

  _ItemFormulario({
    required this.id,
    required this.produtoId,
    required this.produtoNome,
    required this.codigo,
    required this.unidade,
    required double quantidade,
    required this.quantidadeRecebida,
    required double precoCusto,
  }) : quantidade = TextEditingController(
         text: units.formatarNumero(quantidade),
       ),
       custo = TextEditingController(text: precoCusto.toStringAsFixed(2));

  double get quantidadeValor =>
      double.tryParse(quantidade.text.trim().replaceAll(',', '.')) ?? 0;

  double get valorCusto =>
      double.tryParse(custo.text.trim().replaceAll(',', '.')) ?? 0;

  double get valorTotal => quantidadeValor * valorCusto;

  void dispose() {
    quantidade.dispose();
    custo.dispose();
  }
}

/// Lista de fornecedores já usados no cadastro de produtos.
class _SeletorFornecedorDialog extends StatefulWidget {
  final List<String> nomes;

  const _SeletorFornecedorDialog({required this.nomes});

  @override
  State<_SeletorFornecedorDialog> createState() =>
      _SeletorFornecedorDialogState();
}

class _SeletorFornecedorDialogState extends State<_SeletorFornecedorDialog> {
  String _busca = '';

  @override
  Widget build(BuildContext context) {
    final filtrados = widget.nomes
        .where((nome) => nome.toLowerCase().contains(_busca.toLowerCase()))
        .toList();
    return AlertDialog(
      backgroundColor: const Color(0xFF0F172A),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: Colors.white.withOpacity(0.08)),
      ),
      title: const Text(
        'Fornecedores cadastrados',
        style: TextStyle(color: Colors.white, fontSize: 16),
      ),
      content: SizedBox(
        width: 420,
        height: 400,
        child: Column(
          children: [
            TextField(
              autofocus: true,
              onChanged: (valor) => setState(() => _busca = valor),
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                hintText: 'Filtrar fornecedor...',
                prefixIcon: Icon(Icons.search),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: filtrados.isEmpty
                  ? Center(
                      child: Text(
                        widget.nomes.isEmpty
                            ? 'Nenhum fornecedor cadastrado nos produtos.\nDigite o nome no formulário.'
                            : 'Nenhum fornecedor encontrado.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 12,
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: filtrados.length,
                      itemBuilder: (context, index) {
                        final nome = filtrados[index];
                        return ListTile(
                          dense: true,
                          leading: const Icon(
                            Icons.local_shipping_outlined,
                            color: Colors.cyanAccent,
                            size: 20,
                          ),
                          title: Text(
                            nome,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                            ),
                          ),
                          onTap: () => Navigator.pop(context, nome),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('FECHAR', style: TextStyle(color: Colors.white38)),
        ),
      ],
    );
  }
}

/// Busca e escolhe um produto do cadastro.
class _SeletorProdutoDialog extends StatefulWidget {
  final List<Produto> produtos;

  const _SeletorProdutoDialog({required this.produtos});

  @override
  State<_SeletorProdutoDialog> createState() => _SeletorProdutoDialogState();
}

class _SeletorProdutoDialogState extends State<_SeletorProdutoDialog> {
  final TextEditingController _buscaController = TextEditingController();
  String _busca = '';

  static final NumberFormat _moeda = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: 'R\$',
  );

  @override
  void dispose() {
    _buscaController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final termo = _busca.trim().toLowerCase();
    final filtrados = widget.produtos.where((produto) {
      if (termo.isEmpty) return true;
      return produto.nome.toLowerCase().contains(termo) ||
          (produto.codigo ?? '').toLowerCase().contains(termo) ||
          (produto.codigoBarras ?? '').toLowerCase().contains(termo);
    }).toList()..sort((a, b) => a.nome.compareTo(b.nome));

    return AlertDialog(
      backgroundColor: const Color(0xFF0F172A),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: Colors.white.withOpacity(0.08)),
      ),
      title: const Text(
        'Adicionar produto',
        style: TextStyle(color: Colors.white, fontSize: 16),
      ),
      content: SizedBox(
        width: 620,
        height: 500,
        child: Column(
          children: [
            TextField(
              controller: _buscaController,
              autofocus: true,
              onChanged: (valor) => setState(() => _busca = valor),
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                hintText: 'Nome, código ou código de barras...',
                prefixIcon: Icon(Icons.search),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: filtrados.isEmpty
                  ? const Center(
                      child: Text(
                        'Nenhum produto encontrado.',
                        style: TextStyle(color: Colors.white38, fontSize: 12),
                      ),
                    )
                  : ListView.builder(
                      itemCount: filtrados.length,
                      itemBuilder: (context, index) {
                        final produto = filtrados[index];
                        return ListTile(
                          dense: true,
                          leading: const Icon(
                            Icons.inventory_2_outlined,
                            color: Colors.cyanAccent,
                            size: 20,
                          ),
                          title: Text(
                            produto.nome,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                            ),
                          ),
                          subtitle: Text(
                            [
                              if ((produto.codigo ?? '').isNotEmpty)
                                'Cód.: ${produto.codigo}',
                              'Estoque: ${units.formatarNumero(produto.estoque)} ${produto.unidade}',
                              if (produto.precoCusto != null)
                                'Custo: ${_moeda.format(produto.precoCusto!)}',
                              if ((produto.fornecedorNome ?? '').isNotEmpty)
                                'Forn.: ${produto.fornecedorNome}',
                            ].join('  •  '),
                            style: const TextStyle(
                              color: Colors.white38,
                              fontSize: 10,
                            ),
                          ),
                          trailing: const Icon(
                            Icons.add_circle_outline,
                            color: Colors.greenAccent,
                            size: 20,
                          ),
                          onTap: () => Navigator.pop(context, produto),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text(
            'CANCELAR',
            style: TextStyle(color: Colors.white38),
          ),
        ),
      ],
    );
  }
}
