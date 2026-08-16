import os

file_path = r"c:\Users\charles\.antigravity\sistema_exodo_15-04-2026\lib\produto_form.dart"

with open(file_path, "r", encoding="utf-8") as f:
    content = f.read()

# --- 1. Adicionar os imports e a variável de estado ---
target_import = "import 'package:sistema_exodo_novo/models/item_composicao.dart';"
replacement_import = """import 'package:sistema_exodo_novo/models/item_composicao.dart';
import 'package:sistema_exodo_novo/models/pergunta_selecao.dart';"""

content = content.replace(target_import, replacement_import)

target_state_var = """  // Campos para Composição
  List<ItemComposicao> _composicao = [];"""

replacement_state_var = """  // Campos para Composição
  List<ItemComposicao> _composicao = [];
  
  // Campos para Perguntas de Seleção (Combos)
  List<PerguntaSelecao> _perguntasSelecao = [];"""

content = content.replace(target_state_var, replacement_state_var)
print("IMPORTS_E_VARIAVEIS_ESTADO_ADICIONADOS")


# --- 2. Injetar a carga no initState ---
target_initstate_edit = """      _composicao = widget.item is Produto 
          ? List<ItemComposicao>.from((widget.item as Produto).composicao)
          : [];"""

replacement_initstate_edit = """      _composicao = widget.item is Produto 
          ? List<ItemComposicao>.from((widget.item as Produto).composicao)
          : [];
      _perguntasSelecao = widget.item is Produto 
          ? List<PerguntaSelecao>.from((widget.item as Produto).perguntasSelecao)
          : [];"""

content = content.replace(target_initstate_edit, replacement_initstate_edit)

target_initstate_new = """      _composicao = [];"""
replacement_initstate_new = """      _composicao = [];
      _perguntasSelecao = [];"""

content = content.replace(target_initstate_new, replacement_initstate_new)
print("CARGA_INITSTATE_ADICIONADA")


# --- 3. Atualizar o tamanho de abas de 7 para 8 ---
content = content.replace("TabController(length: 7", "TabController(length: 8")
print("TAMANHO_TAB_CONTROLLER_ATUALIZADO")


# --- 4. Adicionar a aba visual e seu conteúdo ---
target_tabs = """                  Tab(text: 'Composição'),
                  Tab(text: 'Adicionais'),
                  Tab(text: 'Histórico'),"""

replacement_tabs = """                  Tab(text: 'Composição'),
                  Tab(text: 'Adicionais'),
                  Tab(text: 'Perguntas / Combos'),
                  Tab(text: 'Histórico'),"""

content = content.replace(target_tabs, replacement_tabs)

target_tabview_children = """                    SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                      child: _buildAbaComposicao(),
                    ),
                    SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                      child: _buildAbaAdicionais(),
                    ),"""

replacement_tabview_children = """                    SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                      child: _buildAbaComposicao(),
                    ),
                    SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                      child: _buildAbaAdicionais(),
                    ),
                    SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                      child: _buildAbaPerguntasCombos(),
                    ),"""

content = content.replace(target_tabview_children, replacement_tabview_children)
print("ABAS_VISUAIS_E_TABVIEW_ADICIONADOS")


# --- 5. Adicionar a passagem do campo na criação do Produto ---
target_save_product = """      ehComposto: _ehComposto,
      composicao: _composicao,
      observacaoPadrao: _observacaoPadraoController.text.trim().isNotEmpty ? _observacaoPadraoController.text.trim() : null,"""

replacement_save_product = """      ehComposto: _ehComposto,
      composicao: _composicao,
      observacaoPadrao: _observacaoPadraoController.text.trim().isNotEmpty ? _observacaoPadraoController.text.trim() : null,
      perguntasSelecao: _perguntasSelecao,"""

content = content.replace(target_save_product, replacement_save_product)
print("CAMPO_PRODUTO_FORM_SALVAR_ADICIONADO")


# --- 6. Injetar os métodos na classe _ProdutoServicoFormState (após _confirmarSalvamento) ---
target_confirmar_salvamento = """  void _confirmarSalvamento(Produto produto) {
    widget.onSave(produto);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('✓ Produto cadastrado com sucesso!'),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }"""

replacement_confirmar_salvamento = """  void _confirmarSalvamento(Produto produto) {
    widget.onSave(produto);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('✓ Produto cadastrado com sucesso!'),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Método para exibir a interface de cadastro de Perguntas de Seleção (Combos)
  Widget _buildAbaPerguntasCombos() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Perguntas de Seleção / Combo Interativo',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const SizedBox(height: 4),
                Text(
                  'Crie perguntas interativas para o cliente selecionar opções no PDV.',
                  style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.5)),
                ),
              ],
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
              onPressed: () => _exibirDialogoEditarPergunta(),
              icon: const Icon(Icons.add_circle_outline, color: Colors.white, size: 18),
              label: const Text('Nova Pergunta', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        const SizedBox(height: 20),
        if (_perguntasSelecao.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF161624) : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Column(
              children: [
                Icon(Icons.help_outline_rounded, size: 48, color: Colors.white30),
                SizedBox(height: 12),
                Text(
                  'Nenhuma pergunta de seleção cadastrada.',
                  style: TextStyle(color: Colors.white60, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _perguntasSelecao.length,
            separatorBuilder: (context, index) => const SizedBox(height: 16),
            itemBuilder: (context, index) {
              final pergunta = _perguntasSelecao[index];
              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header Pergunta
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                pergunta.titulo,
                                style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${pergunta.obrigatorio ? "Obrigatório" : "Opcional"} | Mínimo: ${pergunta.minimo} | Máximo: ${pergunta.maximo}',
                                style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, color: Colors.blueAccent, size: 20),
                              onPressed: () => _exibirDialogoEditarPergunta(perguntaEdicao: pergunta, indexEdicao: index),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20),
                              onPressed: () {
                                setState(() {
                                  _perguntasSelecao.removeAt(index);
                                });
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                    const Divider(color: Colors.white10, height: 20),
                    
                    // Opções
                    const Text('Opções disponíveis:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white70)),
                    const SizedBox(height: 8),
                    if (pergunta.opcoes.isEmpty)
                      const Text('Nenhum produto associado como opção.', style: TextStyle(color: Colors.white30, fontSize: 12))
                    else
                      Column(
                        children: pergunta.opcoes.map((opcao) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4.0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.subdirectory_arrow_right_rounded, size: 16, color: Colors.white38),
                                    const SizedBox(width: 8),
                                    Text(opcao.nome, style: const TextStyle(color: Colors.white, fontSize: 13)),
                                  ],
                                ),
                                Row(
                                  children: [
                                    if (opcao.precoAdicional > 0)
                                      Text(
                                        '+ R\$ ${opcao.precoAdicional.toStringAsFixed(2)}',
                                        style: const TextStyle(color: Colors.amber, fontSize: 13, fontWeight: FontWeight.bold),
                                      ),
                                    const SizedBox(width: 12),
                                    Text(
                                      'Baixa: ${opcao.quantidadeBaixa} UN',
                                      style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }

  /// Exibe diálogo para adicionar ou editar uma pergunta de seleção
  void _exibirDialogoEditarPergunta({PerguntaSelecao? perguntaEdicao, int? indexEdicao}) {
    final tituloCtrl = TextEditingController(text: perguntaEdicao?.titulo ?? '');
    final minimoCtrl = TextEditingController(text: perguntaEdicao?.minimo.toString() ?? '1');
    final maximoCtrl = TextEditingController(text: perguntaEdicao?.maximo.toString() ?? '1');
    bool obrigatorio = perguntaEdicao?.obrigatorio ?? true;
    List<OpcaoPerguntaSelecao> opcoesTemporarias = perguntaEdicao != null 
        ? List<OpcaoPerguntaSelecao>.from(perguntaEdicao.opcoes)
        : [];

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1E1E2E),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Text(
                perguntaEdicao == null ? 'Nova Pergunta de Seleção' : 'Editar Pergunta',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: tituloCtrl,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Título da Pergunta (Ex: Escolha a Bebida)',
                        labelStyle: TextStyle(color: Colors.white70),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: minimoCtrl,
                            keyboardType: TextInputType.number,
                            style: const TextStyle(color: Colors.white),
                            decoration: const InputDecoration(
                              labelText: 'Mínimo',
                              labelStyle: TextStyle(color: Colors.white70),
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextField(
                            controller: maximoCtrl,
                            keyboardType: TextInputType.number,
                            style: const TextStyle(color: Colors.white),
                            decoration: const InputDecoration(
                              labelText: 'Máximo',
                              labelStyle: TextStyle(color: Colors.white70),
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    CheckboxListTile(
                      title: const Text('Resposta Obrigatória', style: TextStyle(color: Colors.white, fontSize: 14)),
                      value: obrigatorio,
                      onChanged: (val) {
                        setStateDialog(() {
                          obrigatorio = val ?? true;
                        });
                      },
                    ),
                    const Divider(color: Colors.white10, height: 24),
                    
                    // Seção de Produtos Opções
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Produtos Associados', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
                        TextButton.icon(
                          onPressed: () {
                            // Dialogo para buscar e associar produto
                            _exibirDialogoAssociarProdutoOpcao((novaOpcao) {
                              setStateDialog(() {
                                opcoesTemporarias.add(novaOpcao);
                              });
                            });
                          },
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text('Adicionar Item'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (opcoesTemporarias.isEmpty)
                      const Text('Nenhum produto adicionado a esta pergunta.', style: TextStyle(color: Colors.white38, fontSize: 12))
                    else
                      Column(
                        children: List.generate(opcoesTemporarias.length, (idx) {
                          final o = opcoesTemporarias[idx];
                          return Card(
                            color: Colors.white.withOpacity(0.04),
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            child: ListTile(
                              dense: true,
                              title: Text(o.nome, style: const TextStyle(color: Colors.white)),
                              subtitle: Text(
                                'Preço Adicional: R\$ ${o.precoAdicional.toStringAsFixed(2)} | Baixa: ${o.quantidadeBaixa} UN',
                                style: const TextStyle(color: Colors.white54),
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete, color: Colors.redAccent, size: 18),
                                onPressed: () {
                                  setStateDialog(() {
                                    opcoesTemporarias.removeAt(idx);
                                  });
                                },
                              ),
                            ),
                          );
                        }),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
                ),
                ElevatedButton(
                  onPressed: () {
                    final titulo = tituloCtrl.text.trim();
                    if (titulo.isEmpty) return;
                    
                    final min = int.tryParse(minimoCtrl.text) ?? 1;
                    final max = int.tryParse(maximoCtrl.text) ?? 1;
                    
                    final novaPergunta = PerguntaSelecao(
                      id: perguntaEdicao?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
                      titulo: titulo,
                      obrigatorio: obrigatorio,
                      minimo: min,
                      maximo: max,
                      opcoes: opcoesTemporarias,
                    );
                    
                    setState(() {
                      if (indexEdicao == null) {
                        _perguntasSelecao.add(novaPergunta);
                      } else {
                        _perguntasSelecao[indexEdicao] = novaPergunta;
                      }
                    });
                    
                    Navigator.pop(dialogContext);
                  },
                  child: const Text('Salvar Pergunta'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// Exibe diálogo para associar um produto cadastrado como opção do combo
  void _exibirDialogoAssociarProdutoOpcao(Function(OpcaoPerguntaSelecao) onAdicionado) {
    String? produtoIdSelecionado;
    String produtoNome = '';
    final precoAdicionalCtrl = TextEditingController(text: '0.00');
    final baixaCtrl = TextEditingController(text: '1.0');
    
    // Lista de produtos ativos cadastrados no sistema
    final todosProdutos = Provider.of<DataService>(context, listen: false).produtos;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1E1E2E),
              title: const Text('Associar Produto', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    dropdownColor: const Color(0xFF1E1E2E),
                    value: produtoIdSelecionado,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'Selecione o Produto',
                      labelStyle: TextStyle(color: Colors.white70),
                      border: OutlineInputBorder(),
                    ),
                    items: todosProdutos.map((p) {
                      return DropdownMenuItem<String>(
                        value: p.id,
                        child: Text(p.nome, style: const TextStyle(color: Colors.white)),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        final prod = todosProdutos.firstWhere((p) => p.id == val);
                        setStateDialog(() {
                          produtoIdSelecionado = val;
                          produtoNome = prod.nome;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: precoAdicionalCtrl,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(color: Colors.white),
                          decoration: const InputDecoration(
                            labelText: 'Preço Adicional (R\$)',
                            labelStyle: TextStyle(color: Colors.white70),
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: TextField(
                          controller: baixaCtrl,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(color: Colors.white),
                          decoration: const InputDecoration(
                            labelText: 'Baixa de Estoque',
                            labelStyle: TextStyle(color: Colors.white70),
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (produtoIdSelecionado == null) return;
                    
                    final adicional = double.tryParse(precoAdicionalCtrl.text.replaceAll(',', '.')) ?? 0.0;
                    final qtdBaixa = double.tryParse(baixaCtrl.text.replaceAll(',', '.')) ?? 1.0;
                    
                    final opcao = OpcaoPerguntaSelecao(
                      id: DateTime.now().millisecondsSinceEpoch.toString(),
                      produtoId: produtoIdSelecionado!,
                      nome: produtoNome,
                      precoAdicional: adicional,
                      quantidadeBaixa: qtdBaixa,
                    );
                    
                    onAdicionado(opcao);
                    Navigator.pop(dialogContext);
                  },
                  child: const Text('Associar'),
                ),
              ],
            );
          },
        );
      },
    );
  }"""

content = content.replace(target_confirmar_salvamento, replacement_confirmar_salvamento)
print("INJECAO_DENTRO_DO_ESCOPO_CORRETO_SALVA")

with open(file_path, "w", encoding="utf-8") as f:
    f.write(content)
