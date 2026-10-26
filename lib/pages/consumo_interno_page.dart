import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../services/data_service.dart';
import '../services/auth_service.dart';
import '../models/estoque_historico.dart';
import '../models/produto.dart';
import '../theme.dart';
import '../custom_app_bar.dart';

/// Dashboard e lançamento de CONSUMO INTERNO da loja.
///
/// Tudo que sai do estoque para uso próprio/descarte controlado da empresa
/// (não é venda, não é quebra) fica registrado aqui com motivo
/// 'consumo_interno'. O dashboard mostra quantos lançamentos foram feitos,
/// quantas unidades saíram e o quanto isso custou (a preço de custo).
class ConsumoInternoPage extends StatefulWidget {
  const ConsumoInternoPage({super.key});

  @override
  State<ConsumoInternoPage> createState() => _ConsumoInternoPageState();
}

class _ConsumoInternoPageState extends State<ConsumoInternoPage> {
  String? _periodoFiltro; // null = tudo, 'hoje', '7dias', 'mes'
  String _busca = '';
  final TextEditingController _buscaController = TextEditingController();

  @override
  void dispose() {
    _buscaController.dispose();
    super.dispose();
  }

  DateTime? _dataInicio(String? periodo) {
    final agora = DateTime.now();
    switch (periodo) {
      case 'hoje':
        return DateTime(agora.year, agora.month, agora.day);
      case '7dias':
        return agora.subtract(const Duration(days: 7));
      case 'mes':
        return DateTime(agora.year, agora.month, 1);
      default:
        return null;
    }
  }

  /// Diálogo de lançamento MANUAL de consumo interno (produto + quantidade +
  /// motivo). Baixa do estoque imediata, com o valor de custo registrado.
  Future<void> _abrirNovoConsumo() async {
    final dataService = Provider.of<DataService>(context, listen: false);
    final authService = Provider.of<AuthService>(context, listen: false);

    final produto = await showDialog<Produto>(
      context: context,
      builder: (context) =>
          _DialogSelecionarProdutoConsumo(produtos: dataService.produtos),
    );
    if (produto == null || !mounted) return;

    final quantidadeController = TextEditingController(text: '1');
    final motivoController = TextEditingController();
    // Nome de quem consumiu: vem pré-preenchido com o operador logado, mas é
    // editável — na loja quem registra o consumo nem sempre é quem consumiu.
    final usuarioController = TextEditingController(
      text: authService.usuarioAtual?.nome ??
          authService.usuarioAtual?.email ??
          '',
    );
    final custoUnit = produto.precoCusto ?? 0.0;
    var quantidade = 1.0;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final valorCusto = quantidade * custoUnit;
          return AlertDialog(
            backgroundColor: const Color(0xFF1E1E2E),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.lightBlueAccent.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.store_mall_directory_outlined,
                    color: Colors.lightBlueAccent,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Consumo Interno da Loja',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    produto.nome,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Estoque: ${produto.estoque.toStringAsFixed(2)}  •  Custo: R\$ ${custoUnit.toStringAsFixed(2)}/un',
                    style: const TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Quantidade consumida:',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: quantidadeController,
                    autofocus: true,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.05),
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onChanged: (v) {
                      quantidade =
                          double.tryParse(v.replaceAll(',', '.')) ?? 0;
                      setDialogState(() {});
                    },
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Text(
                        'Custo do consumo:',
                        style: TextStyle(color: Colors.white54, fontSize: 13),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'R\$ ${valorCusto.toStringAsFixed(2)}',
                        style: const TextStyle(
                          color: Colors.lightBlueAccent,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Motivo / uso (opcional):',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: motivoController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText:
                          'Ex: uso da equipe, evento, teste de produto...',
                      hintStyle: TextStyle(
                        color: Colors.white.withOpacity(0.3),
                      ),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.05),
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Quem consumiu:',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: usuarioController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Nome de quem consumiu (funcionário)...',
                      hintStyle: TextStyle(
                        color: Colors.white.withOpacity(0.3),
                      ),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.05),
                      isDense: true,
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
                  'CANCELAR',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.check_circle_outline, size: 18),
                onPressed: () async {
                  if (quantidade <= 0) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Informe uma quantidade válida.'),
                        backgroundColor: Colors.redAccent,
                      ),
                    );
                    return;
                  }
                  final motivo = motivoController.text.trim().isEmpty
                      ? null
                      : motivoController.text.trim();
                  final usuarioDigitado = usuarioController.text.trim();
                  final usuario = usuarioDigitado.isNotEmpty
                      ? usuarioDigitado
                      : (authService.usuarioAtual?.nome ??
                          authService.usuarioAtual?.email ??
                          'Operador');
                  await dataService.registrarConsumoInterno(
                    produtoId: produto.id,
                    quantidade: quantidade,
                    observacao: motivo,
                    usuario: usuario,
                  );
                  if (!context.mounted) return;
                  Navigator.pop(context);
                  if (mounted) setState(() {});
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        '✓ Consumo registrado: ${produto.nome} • ${quantidade.toStringAsFixed(2)} un • Custo: R\$ ${valorCusto.toStringAsFixed(2)}',
                      ),
                      backgroundColor: Colors.lightBlueAccent,
                      duration: const Duration(seconds: 3),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.lightBlueAccent,
                  foregroundColor: Colors.black,
                ),
                label: const Text('REGISTRAR CONSUMO'),
              ),
            ],
          );
        },
      ),
    );
    quantidadeController.dispose();
    motivoController.dispose();
    usuarioController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final service = Provider.of<DataService>(context);
    final historico = service.estoqueHistorico;
    final produtos = service.produtos;

    // Apenas saídas de consumo interno
    final consumos =
        historico.where((h) => h.ehConsumoInterno && !h.ehZeramento).toList();

    final dataInicio = _dataInicio(_periodoFiltro);
    List<EstoqueHistorico> filtrado = consumos.where((h) {
      if (dataInicio != null && h.data.isBefore(dataInicio)) return false;
      if (_busca.isNotEmpty) {
        final prod = produtos.firstWhere(
          (p) => p.id == h.produtoId,
          orElse: () => _produtoExcluido(),
        );
        final q = _busca.toLowerCase();
        final bateProduto = prod.nome.toLowerCase().contains(q) ||
            (prod.codigo?.toLowerCase().contains(q) ?? false);
        final batePessoa = (h.usuario ?? '').toLowerCase().contains(q);
        if (!bateProduto && !batePessoa) return false;
      }
      return true;
    }).toList();
    filtrado.sort((a, b) => b.data.compareTo(a.data));

    // Dashboard: lançamentos, unidades e custo total consumido
    final totais = service.totaisConsumoInterno(filtrado);

    return AppTheme.appBackground(
      child: Scaffold(
        appBar: CustomAppBar(
          title: 'Consumo Interno da Loja',
          actions: [
            IconButton(
              icon: const Icon(
                Icons.add_circle_outline,
                color: Colors.lightBlueAccent,
              ),
              tooltip: 'Novo Consumo Interno',
              onPressed: _abrirNovoConsumo,
            ),
          ],
        ),
        body: Column(
          children: [
            _buildFiltrosPeriodo(),
            const SizedBox(height: 12),
            _buildResumo(totais.lancamentos, totais.unidades, totais.custo),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _buscaController,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Buscar por produto, código ou quem consumiu...',
                  hintStyle: TextStyle(
                    color: Colors.white.withOpacity(0.3),
                    fontSize: 13,
                  ),
                  prefixIcon: const Icon(
                    Icons.search,
                    color: Colors.white38,
                    size: 20,
                  ),
                  suffixIcon: _busca.isNotEmpty
                      ? IconButton(
                          icon: const Icon(
                            Icons.close,
                            color: Colors.white38,
                            size: 18,
                          ),
                          onPressed: () {
                            _buscaController.clear();
                            setState(() => _busca = '');
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.05),
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: (v) => setState(() => _busca = v.trim()),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: filtrado.isEmpty
                  ? const Center(
                      child: Text(
                        'Nenhum consumo interno registrado',
                        style: TextStyle(color: Colors.white24),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                      itemCount: filtrado.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 6),
                      itemBuilder: (context, index) =>
                          _buildItemConsumo(filtrado[index], produtos),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFiltrosPeriodo() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          _chipPeriodo('Tudo', null),
          _chipPeriodo('Hoje', 'hoje'),
          _chipPeriodo('7 dias', '7dias'),
          _chipPeriodo('Mês', 'mes'),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.lightBlueAccent.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.store_mall_directory_outlined,
                  color: Colors.lightBlueAccent,
                  size: 16,
                ),
                SizedBox(width: 6),
                Text(
                  'Uso próprio da loja',
                  style: TextStyle(color: Colors.lightBlueAccent, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chipPeriodo(String label, String? valor) {
    final ativo = _periodoFiltro == valor;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        onTap: () => setState(() => _periodoFiltro = valor),
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: ativo ? Colors.lightBlueAccent : Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: ativo ? Colors.black : Colors.white70,
              fontSize: 12,
              fontWeight: ativo ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildResumo(int lancamentos, double unidades, double custo) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          _cardResumo(
            'LANÇAMENTOS',
            '$lancamentos',
            Icons.playlist_add_check_circle_outlined,
            Colors.lightBlueAccent,
          ),
          const SizedBox(width: 12),
          _cardResumo(
            'UNIDADES',
            unidades.toStringAsFixed(1),
            Icons.square_foot,
            Colors.amberAccent,
          ),
          const SizedBox(width: 12),
          _cardResumo(
            'CUSTO CONSUMIDO',
            'R\$ ${custo.toStringAsFixed(2)}',
            Icons.attach_money,
            Colors.redAccent,
          ),
        ],
      ),
    );
  }

  Widget _cardResumo(String label, String valor, IconData icone, Color cor) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cor.withOpacity(0.06),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icone, color: cor, size: 18),
            const SizedBox(height: 6),
            Text(
              valor,
              style: TextStyle(color: cor, fontSize: 16, fontWeight: FontWeight.bold),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              label,
              style: TextStyle(color: cor.withOpacity(0.6), fontSize: 8.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItemConsumo(
    EstoqueHistorico h,
    List<Produto> produtos,
  ) {
    final p = produtos.firstWhere(
      (prod) => prod.id == h.produtoId,
      orElse: () => _produtoExcluido(),
    );
    final custo = h.valorCusto ?? 0.0;
    // Motivo/uso descrito no lançamento (sem o prefixo "Consumo interno:")
    var motivo = (h.observacao ?? '')
        .replaceAll('Consumo interno:', '')
        .replaceAll(RegExp(r'\(Motivo: [a-z_]+\)'), '')
        .trim();
    if (motivo.isEmpty) motivo = 'Uso próprio da loja';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.lightBlueAccent.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.lightBlueAccent.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.lightBlueAccent.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.store_mall_directory_outlined,
              color: Colors.lightBlueAccent,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.nome,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${DateFormat('dd/MM/yy HH:mm').format(h.data)} • $motivo',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.4),
                    fontSize: 11,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(
                      Icons.person_outline,
                      color: Colors.lightBlueAccent,
                      size: 13,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        'Consumido por: ${h.usuario ?? '—'}',
                        style: const TextStyle(
                          color: Colors.lightBlueAccent,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '−${h.quantidade.abs().toStringAsFixed(2)}',
                style: const TextStyle(
                  color: Colors.lightBlueAccent,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                custo > 0 ? 'R\$ ${custo.toStringAsFixed(2)}' : '—',
                style: TextStyle(
                  color: custo > 0 ? Colors.redAccent : Colors.white24,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Produto _produtoExcluido() => Produto(
    id: '',
    nome: 'Produto Excluído',
    preco: 0,
    estoque: 0,
    unidade: 'un',
    grupo: 'Geral',
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );
}

/// Diálogo de seleção de produto para lançar o consumo interno manualmente.
/// Busca por nome/código/código de barras e mostra o estoque/custo.
class _DialogSelecionarProdutoConsumo extends StatefulWidget {
  final List<Produto> produtos;
  const _DialogSelecionarProdutoConsumo({required this.produtos});

  @override
  State<_DialogSelecionarProdutoConsumo> createState() =>
      _DialogSelecionarProdutoConsumoState();
}

class _DialogSelecionarProdutoConsumoState
    extends State<_DialogSelecionarProdutoConsumo> {
  String _busca = '';
  final TextEditingController _buscaController = TextEditingController();

  @override
  void dispose() {
    _buscaController.dispose();
    super.dispose();
  }

  List<Produto> get _filtrados {
    final q = _busca.trim().toLowerCase();
    if (q.isEmpty) return widget.produtos;
    return widget.produtos.where((p) {
      return p.nome.toLowerCase().contains(q) ||
          (p.codigo?.toLowerCase().contains(q) ?? false) ||
          (p.codigoBarras?.toLowerCase().contains(q) ?? false);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtrados = _filtrados;
    return AlertDialog(
      backgroundColor: const Color(0xFF1E1E2E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text(
        'Selecione o produto consumido',
        style: TextStyle(
          color: Colors.white,
          fontSize: 17,
          fontWeight: FontWeight.bold,
        ),
      ),
      content: SizedBox(
        width: 480,
        height: 420,
        child: Column(
          children: [
            TextField(
              controller: _buscaController,
              autofocus: true,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Buscar por nome, código ou código de barras...',
                hintStyle: TextStyle(
                  color: Colors.white.withOpacity(0.3),
                  fontSize: 13,
                ),
                prefixIcon: const Icon(
                  Icons.search,
                  color: Colors.white38,
                  size: 20,
                ),
                filled: true,
                fillColor: Colors.white.withOpacity(0.05),
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (v) => setState(() => _busca = v),
              onSubmitted: (_) {
                if (filtrados.isNotEmpty) {
                  Navigator.pop(context, filtrados.first);
                }
              },
            ),
            const SizedBox(height: 12),
            Expanded(
              child: filtrados.isEmpty
                  ? const Center(
                      child: Text(
                        'Nenhum produto encontrado',
                        style: TextStyle(color: Colors.white24),
                      ),
                    )
                  : ListView.builder(
                      itemCount: filtrados.length,
                      itemBuilder: (context, index) {
                        final p = filtrados[index];
                        final custo = p.precoCusto ?? 0.0;
                        return ListTile(
                          dense: true,
                          leading: const Icon(
                            Icons.store_mall_directory_outlined,
                            color: Colors.lightBlueAccent,
                            size: 20,
                          ),
                          title: Text(
                            p.nome,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            'Estoque: ${p.estoque.toStringAsFixed(2)} • Custo: R\$ ${custo.toStringAsFixed(2)}/un',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.4),
                              fontSize: 11,
                            ),
                          ),
                          onTap: () => Navigator.pop(context, p),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
