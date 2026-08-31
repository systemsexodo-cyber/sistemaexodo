import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../models/produto.dart';
import '../models/item_composicao.dart';
import '../services/data_service.dart';
import '../theme.dart';

/// Tela de Produção / Manufatura.
/// Permite montar produtos finais a partir de matérias-primas,
/// consumindo estoque dos ingredientes e dando entrada no produto final.
class ProducaoPage extends StatefulWidget {
  const ProducaoPage({super.key});

  @override
  State<ProducaoPage> createState() => _ProducaoPageState();
}

class _ProducaoPageState extends State<ProducaoPage> {
  final _qtdController = TextEditingController(text: '1');
  final _buscaController = TextEditingController();
  String _busca = '';
  final NumberFormat _fmtMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  Produto? _produtoSelecionado;
  bool _processando = false;

  @override
  void dispose() {
    _qtdController.dispose();
    _buscaController.dispose();
    super.dispose();
  }

  List<Produto> _produtosCompostos(DataService ds) {
    return ds.produtos
        .where((p) => p.ehComposto && p.composicao.isNotEmpty)
        .toList()
      ..sort((a, b) => a.nome.compareTo(b.nome));
  }

  @override
  Widget build(BuildContext context) {
    final ds = Provider.of<DataService>(context, listen: true);
    final compostos = _produtosCompostos(ds);
    final qtdProduzir = double.tryParse(_qtdController.text.replaceAll(',', '.')) ?? 1;

    return AppTheme.appBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Produção / Manufatura'),
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        body: compostos.isEmpty
            ? _buildEmptyState()
            : SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Busca
                    TextField(
                      controller: _buscaController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Buscar produto composto...',
                        hintStyle: TextStyle(color: Colors.white.withOpacity(0.4)),
                        prefixIcon: const Icon(Icons.search, color: Colors.white38),
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.06),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onChanged: (v) => setState(() => _busca = v),
                    ),
                    const SizedBox(height: 16),

                    // Lista de produtos compostos
                    ...compostos.where((p) {
                      if (_busca.isEmpty) return true;
                      return p.nome.toLowerCase().contains(_busca.toLowerCase());
                    }).map((p) => _buildCardProdutoComposto(p, ds, qtdProduzir)),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.engineering, size: 80, color: Colors.white.withOpacity(0.2)),
          const SizedBox(height: 16),
          Text(
            'Nenhum produto composto cadastrado',
            style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 16),
          ),
          const SizedBox(height: 8),
          Text(
            'Cadastre produtos com composição (matérias-primas)\nno formulário de produto.',
            style: TextStyle(color: Colors.white.withOpacity(0.35), fontSize: 13),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildCardProdutoComposto(Produto produto, DataService ds, double qtdBase) {
    final ingredientes = produto.composicao;
    
    // Calcular disponibilidade
    bool temEstoqueSuficiente = true;
    double custoTotal = 0;
    final List<Map<String, dynamic>> detalhes = [];

    for (final item in ingredientes) {
      final ingrediente = ds.produtos.cast<Produto?>().firstWhere(
        (p) => p?.id == item.produtoId,
        orElse: () => null,
      );
      final nome = ingrediente?.nome ?? 'Desconhecido';
      final unidade = ingrediente?.unidade ?? 'UN';
      final estoqueAtual = ingrediente?.estoque ?? 0;
      final custoUnit = ingrediente?.precoCusto ?? 0;
      
      final qtdNecessaria = qtdBase * item.quantidade;
      final disponivel = estoqueAtual >= qtdNecessaria;
      if (!disponivel) temEstoqueSuficiente = false;
      
      custoTotal += custoUnit * item.quantidade;

      detalhes.add({
        'nome': nome,
        'unidade': unidade,
        'qtdNecessaria': qtdNecessaria,
        'estoqueAtual': estoqueAtual,
        'disponivel': disponivel,
        'custoUnit': custoUnit,
      });
    }

    final isExpanded = _produtoSelecionado?.id == produto.id;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isExpanded
              ? Colors.blueAccent.withOpacity(0.6)
              : temEstoqueSuficiente
                  ? Colors.greenAccent.withOpacity(0.2)
                  : Colors.redAccent.withOpacity(0.3),
          width: isExpanded ? 2 : 1,
        ),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() {
              _produtoSelecionado = isExpanded ? null : produto;
              _qtdController.text = '1';
            }),
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  // Ícone
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.blueAccent.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.engineering, color: Colors.blueAccent, size: 24),
                  ),
                  const SizedBox(width: 12),
                  // Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          produto.nome,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            _badge(
                              '${ingredientes.length} ingrediente(s)',
                              Colors.blueAccent,
                            ),
                            const SizedBox(width: 8),
                            _badge(
                              temEstoqueSuficiente ? 'Estoque OK' : 'Estoque insuficiente',
                              temEstoqueSuficiente ? Colors.greenAccent : Colors.redAccent,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Seta
                  Icon(
                    isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    color: Colors.white38,
                  ),
                ],
              ),
            ),
          ),

          // Detalhes expandidos
          if (isExpanded) ...[
            const Divider(color: Colors.white10, height: 1),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Quantidade a produzir
                  Row(
                    children: [
                      const Text(
                        'Quantidade a produzir:',
                        style: TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 80,
                        child: TextField(
                          controller: _qtdController,
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: Colors.white.withOpacity(0.08),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide.none,
                            ),
                          ),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
                          ],
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        produto.unidade,
                        style: const TextStyle(color: Colors.white54, fontSize: 13),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Ingredientes necessários
                  const Text(
                    'Matérias-primas necessárias:',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),

                  ...detalhes.map((d) {
                    final percentual = d['estoqueAtual'] > 0
                        ? (d['qtdNecessaria'] / d['estoqueAtual']).clamp(0.0, 1.0)
                        : 1.0;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: d['disponivel']
                            ? Colors.greenAccent.withOpacity(0.05)
                            : Colors.redAccent.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: d['disponivel']
                              ? Colors.greenAccent.withOpacity(0.2)
                              : Colors.redAccent.withOpacity(0.3),
                        ),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Icon(
                                d['disponivel'] ? Icons.check_circle : Icons.error,
                                color: d['disponivel'] ? Colors.greenAccent : Colors.redAccent,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      d['nome'],
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    Text(
                                      'Necessário: ${d['qtdNecessaria'].toStringAsFixed(2)} ${d['unidade']}  ·  Estoque: ${d['estoqueAtual'].toStringAsFixed(2)} ${d['unidade']}',
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.5),
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (d['custoUnit'] > 0)
                                Text(
                                  _fmtMoeda.format(d['custoUnit'] * d['qtdNecessaria']),
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.6),
                                    fontSize: 12,
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: percentual,
                              backgroundColor: Colors.white10,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                d['disponivel'] ? Colors.greenAccent : Colors.redAccent,
                              ),
                              minHeight: 4,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),

                  // Custo total
                  if (custoTotal > 0) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.blueAccent.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Custo da produção:',
                            style: TextStyle(color: Colors.white70, fontSize: 13),
                          ),
                          Text(
                            _fmtMoeda.format(custoTotal * qtdBase),
                            style: const TextStyle(
                              color: Colors.blueAccent,
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // Botão produzir
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: temEstoqueSuficiente && !_processando
                          ? () => _processarProducao(produto, ds, qtdBase)
                          : null,
                      icon: _processando
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.build_circle, size: 20),
                      label: Text(
                        _processando
                            ? 'Processando...'
                            : temEstoqueSuficiente
                                ? 'PRODUZIR ${qtdBase.toStringAsFixed(0)} ${produto.unidade}'
                                : 'Estoque insuficiente',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: temEstoqueSuficiente ? Colors.green : Colors.grey,
                        foregroundColor: Colors.white,
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
        ],
      ),
    );
  }

  Widget _badge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
      ),
    );
  }

  Future<void> _processarProducao(Produto produto, DataService ds, double qtdProduzir) async {
    setState(() => _processando = true);

    try {
      // 1. Baixar estoque de cada ingrediente
      for (final item in produto.composicao) {
        final qtdNecessaria = qtdProduzir * item.quantidade;
        await ds.registrarSaidaEstoque(
          produtoId: item.produtoId,
          quantidade: qtdNecessaria,
          motivo: 'producao',
          observacao: 'Produção de ${qtdProduzir} ${produto.unidade} de ${produto.nome}',
        );
      }

      // 2. Dar entrada no produto final
      await ds.registrarEntradaEstoque(
        produtoId: produto.id,
        quantidade: qtdProduzir,
        observacao: 'Produção de ${qtdProduzir} ${produto.unidade} de ${produto.nome}',
      );

      if (mounted) {
        setState(() {
          _processando = false;
          _produtoSelecionado = null;
          _qtdController.text = '1';
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ ${qtdProduzir.toStringAsFixed(0)} ${produto.unidade} de ${produto.nome} produzido(s) com sucesso!'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _processando = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Erro ao produzir: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
