import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../models/produto.dart';
import '../services/data_service.dart';
import '../theme.dart';
import '../custom_app_bar.dart';
import '../produto_form.dart' as produto_form;

class EstoqueReposicaoPage extends StatefulWidget {
  const EstoqueReposicaoPage({super.key});

  @override
  State<EstoqueReposicaoPage> createState() => _EstoqueReposicaoPageState();
}

class _EstoqueReposicaoPageState extends State<EstoqueReposicaoPage> {
  String _busca = '';
  final _buscaController = TextEditingController();

  @override
  void dispose() {
    _buscaController.dispose();
    super.dispose();
  }

  void _showForm(BuildContext context, {Produto? produto}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: produto_form.ProdutoServicoForm(
            item: produto,
            onSave: (newProduto) {
              final service = Provider.of<DataService>(context, listen: false);
              service.updateProduto(newProduto);
            },
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final service = Provider.of<DataService>(context);
    final produtosAviso = service.produtos.where((p) => p.estoqueMinimo > 0 && p.estoque <= p.estoqueMinimo).toList();
    
    // Filtro de busca
    final filtrados = produtosAviso.where((p) {
      if (_busca.isEmpty) return true;
      return p.nome.toLowerCase().contains(_busca.toLowerCase()) || 
             (p.codigo?.toLowerCase().contains(_busca.toLowerCase()) ?? false);
    }).toList();

    // Ordenar por criticidade (estoque 0 primeiro, depois os mais distantes do mínimo)
    filtrados.sort((a, b) {
      if (a.estoque == 0 && b.estoque > 0) return -1;
      if (b.estoque == 0 && a.estoque > 0) return 1;
      return a.estoque.compareTo(b.estoque);
    });

    return AppTheme.appBackground(
      child: Scaffold(
        appBar: const CustomAppBar(title: 'Relatório de Reposição'),
        body: Column(
          children: [
            // Resumo Superior
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.red.shade900.withOpacity(0.3), Colors.orange.shade900.withOpacity(0.1)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.redAccent.withOpacity(0.2)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 32),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${produtosAviso.length} ITENS PARA REPOSIÇÃO',
                          style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Produtos com estoque igual ou abaixo do mínimo configurado.',
                          style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Barra de busca
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _buscaController,
                onChanged: (v) => setState(() => _busca = v),
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Filtrar produtos...',
                  hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                  prefixIcon: Icon(Icons.search, color: Colors.white.withOpacity(0.3), size: 20),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.05),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Lista
            Expanded(
              child: filtrados.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.inventory_rounded, size: 64, color: Colors.white.withOpacity(0.1)),
                          const SizedBox(height: 16),
                          Text(
                            _busca.isEmpty ? 'Tudo em dia! Nenhum produto\nprecisa de reposição agora.' : 'Nenhum produto crítico encontrado.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white.withOpacity(0.4)),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: filtrados.length,
                      itemBuilder: (context, index) {
                        final p = filtrados[index];
                        final isCritico = p.estoque == 0;
                        final percent = p.estoqueMinimo > 0 ? (p.estoque / p.estoqueMinimo).clamp(0.0, 1.0) : 0.0;

                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.03),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: isCritico ? Colors.redAccent.withOpacity(0.2) : Colors.white.withOpacity(0.05)),
                          ),
                          child: InkWell(
                            onTap: () => _showForm(context, produto: p),
                            borderRadius: BorderRadius.circular(16),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        width: 40,
                                        height: 40,
                                        decoration: BoxDecoration(
                                          color: (isCritico ? Colors.redAccent : Colors.orangeAccent).withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        alignment: Alignment.center,
                                        child: Text(
                                          p.codigo?.replaceAll('COD-', '') ?? '?',
                                          style: TextStyle(
                                            color: isCritico ? Colors.redAccent : Colors.orangeAccent,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              p.nome,
                                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                                            ),
                                            Text(
                                              'Forn: ${p.fornecedorNome ?? "Não informado"}',
                                              style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 11),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.end,
                                        children: [
                                          Text(
                                            '${p.estoque} / ${p.estoqueMinimo}',
                                            style: TextStyle(
                                              color: isCritico ? Colors.redAccent : Colors.orangeAccent,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                            ),
                                          ),
                                          Text(
                                            'Faltam: ${p.estoqueMinimo - p.estoque}',
                                            style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 10),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(4),
                                    child: LinearProgressIndicator(
                                      value: percent,
                                      backgroundColor: Colors.white.withOpacity(0.05),
                                      valueColor: AlwaysStoppedAnimation<Color>(isCritico ? Colors.redAccent : Colors.orangeAccent),
                                      minHeight: 4,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
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
