import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/produto.dart';
import '../services/data_service.dart';
import '../services/grupo_service.dart';
import '../theme.dart';

class GerenciarGruposPage extends StatefulWidget {
  const GerenciarGruposPage({super.key});

  @override
  State<GerenciarGruposPage> createState() => _GerenciarGruposPageState();
}

class _GerenciarGruposPageState extends State<GerenciarGruposPage> {
  @override
  Widget build(BuildContext context) {
    final service = Provider.of<DataService>(context);
    final grupos = GrupoService.obterGrupos(service.produtos);
    final contagem = GrupoService.contarProdutosPorGrupo(service.produtos);
    final valoresEstoque = GrupoService.calcularValorEstoquePorGrupo(
      service.produtos,
    );

    return AppTheme.appBackground(
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Gerenciar Grupos'),
          elevation: 0,
          backgroundColor: Colors.transparent,
          centerTitle: true,
        ),
        body: Column(
          children: [
            // Lista de grupos
            Expanded(
              child: grupos.isEmpty
                  ? Center(
                      child: Text(
                        'Nenhum grupo cadastrado',
                        style: TextStyle(
                          color: Theme.of(
                            context,
                          ).colorScheme.onPrimary.withOpacity(0.7),
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: grupos.length,
                      itemBuilder: (context, index) {
                        final grupo = grupos[index];
                        final qtd = contagem[grupo] ?? 0;
                        final valor = valoresEstoque[grupo] ?? 0.0;

                        return Card(
                          color: Theme.of(context).cardColor.withOpacity(0.8),
                          margin: const EdgeInsets.symmetric(vertical: 8),
                          child: ExpansionTile(
                            title: Text(
                              grupo,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.onPrimary,
                              ),
                            ),
                            subtitle: Text(
                              '$qtd produtos | Valor: R\$ ${valor.toStringAsFixed(2)}',
                              style: TextStyle(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onPrimary.withOpacity(0.7),
                              ),
                            ),
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    // Botão Alterar Preço
                                    ElevatedButton.icon(
                                      icon: const Icon(Icons.attach_money),
                                      label: const Text('Alterar Preço'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.blue,
                                      ),
                                      onPressed: () =>
                                          _mostrarDialogoAlterarPreco(
                                            context,
                                            grupo,
                                            service,
                                          ),
                                    ),
                                    const SizedBox(height: 8),
                                    // Botão Alterar Estoque
                                    ElevatedButton.icon(
                                      icon: const Icon(Icons.storage),
                                      label: const Text('Alterar Estoque'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.green,
                                      ),
                                      onPressed: () =>
                                          _mostrarDialogoAlterarEstoque(
                                            context,
                                            grupo,
                                            service,
                                          ),
                                    ),
                                    const SizedBox(height: 8),
                                    // Botão Renomear Grupo
                                    ElevatedButton.icon(
                                      icon: const Icon(Icons.edit),
                                      label: const Text('Renomear Grupo'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.orange,
                                      ),
                                      onPressed: () =>
                                          _mostrarDialogoRenomearGrupo(
                                            context,
                                            grupo,
                                            service,
                                          ),
                                    ),
                                    const SizedBox(height: 8),
                                    // Botão Ver Produtos
                                    ElevatedButton.icon(
                                      icon: const Icon(Icons.visibility),
                                      label: const Text('Ver Produtos'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.purple,
                                      ),
                                      onPressed: () => _mostrarProdutosDoGrupo(
                                        context,
                                        grupo,
                                        service.produtos,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
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

  void _mostrarDialogoAlterarPreco(
    BuildContext context,
    String grupo,
    DataService service,
  ) {
    final controller = TextEditingController();
    bool multiplicar = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('Alterar Preço - $grupo'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: multiplicar
                      ? 'Multiplicador (ex: 1.1 para +10%)'
                      : 'Novo Preço',
                  prefixIcon: const Icon(Icons.attach_money),
                ),
              ),
              const SizedBox(height: 16),
              CheckboxListTile(
                title: const Text('Multiplicar preço atual'),
                value: multiplicar,
                onChanged: (value) =>
                    setState(() => multiplicar = value ?? false),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () {
                final valor = double.tryParse(controller.text);
                if (valor != null && valor > 0) {
                  final produtosAtualizados =
                      GrupoService.atualizarPrecoPorGrupo(
                        service.produtos,
                        grupo,
                        valor,
                        multiplicar: multiplicar,
                      );

                  for (var produto in produtosAtualizados) {
                    if (produto.grupo == grupo) {
                      service.updateProduto(produto);
                    }
                  }

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('✓ Preços atualizados com sucesso!'),
                      backgroundColor: Colors.green,
                    ),
                  );
                  Navigator.pop(context);
                }
              },
              child: const Text('Atualizar'),
            ),
          ],
        ),
      ),
    );
  }

  void _mostrarDialogoAlterarEstoque(
    BuildContext context,
    String grupo,
    DataService service,
  ) {
    final controller = TextEditingController();
    bool adicionar = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('Alterar Estoque - $grupo'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: adicionar
                      ? 'Quantidade a adicionar'
                      : 'Novo Estoque',
                  prefixIcon: const Icon(Icons.storage),
                ),
              ),
              const SizedBox(height: 16),
              CheckboxListTile(
                title: const Text('Adicionar ao estoque atual'),
                value: adicionar,
                onChanged: (value) =>
                    setState(() => adicionar = value ?? false),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () {
                final valor = int.tryParse(controller.text);
                if (valor != null && valor >= 0) {
                  final produtosAtualizados =
                      GrupoService.atualizarEstoquePorGrupo(
                        service.produtos,
                        grupo,
                        valor,
                        adicionar: adicionar,
                      );

                  for (var produto in produtosAtualizados) {
                    if (produto.grupo == grupo) {
                      service.updateProduto(produto);
                    }
                  }

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('✓ Estoque atualizado com sucesso!'),
                      backgroundColor: Colors.green,
                    ),
                  );
                  Navigator.pop(context);
                }
              },
              child: const Text('Atualizar'),
            ),
          ],
        ),
      ),
    );
  }

  void _mostrarDialogoRenomearGrupo(
    BuildContext context,
    String grupo,
    DataService service,
  ) {
    final controller = TextEditingController(text: grupo);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Renomear Grupo'),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: 'Novo nome',
            prefixIcon: const Icon(Icons.edit),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              final novoNome = controller.text.trim();
              if (novoNome.isNotEmpty && novoNome != grupo) {
                final produtosAtualizados = GrupoService.renomearGrupo(
                  service.produtos,
                  grupo,
                  novoNome,
                );

                for (var produto in produtosAtualizados) {
                  if (produto.grupo == novoNome) {
                    service.updateProduto(produto);
                  }
                }

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('✓ Grupo renomeado para "$novoNome"!'),
                    backgroundColor: Colors.green,
                  ),
                );
                Navigator.pop(context);
              }
            },
            child: const Text('Renomear'),
          ),
        ],
      ),
    );
  }

  void _mostrarProdutosDoGrupo(
    BuildContext context,
    String grupo,
    List<Produto> produtos,
  ) {
    final produtosGrupo = GrupoService.obterProdutosPorGrupo(produtos, grupo);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Produtos - $grupo'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            itemCount: produtosGrupo.length,
            itemBuilder: (context, index) {
              final produto = produtosGrupo[index];
              return ListTile(
                title: Text(produto.nome),
                subtitle: Text(
                  'R\$ ${produto.preco.toStringAsFixed(2)} | Est: ${produto.estoque}',
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }
}
