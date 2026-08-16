import os

file_path = r"c:\Users\charles\.antigravity\sistema_exodo_15-04-2026\lib\pages\venda_direta_page.dart"

with open(file_path, "r", encoding="utf-8") as f:
    content = f.read()

# --- 1. Adicionar os imports ---
target_import = "import '../models/funcionario.dart';"
replacement_import = """import '../models/funcionario.dart';
import 'package:sistema_exodo_novo/models/pergunta_selecao.dart';
import 'package:sistema_exodo_novo/widgets/popup_perguntas_combo.dart';"""

content = content.replace(target_import, replacement_import)


# --- 2. Atualizar a classe ItemCarrinho para suportar opcoesCombo ---
target_item_carrinho_fields = """  String? observacao;
  final List<AdicionalProduto> adicionais;
  bool isBrinde; // Identifica se o produto é vendido como brinde (grátis)

  ItemCarrinho({"""

replacement_item_carrinho_fields = """  String? observacao;
  final List<AdicionalProduto> adicionais;
  final List<OpcaoPerguntaSelecao> opcoesCombo;
  bool isBrinde; // Identifica se o produto é vendido como brinde (grátis)

  ItemCarrinho({"""

content = content.replace(target_item_carrinho_fields, replacement_item_carrinho_fields)

target_item_carrinho_ctor = """    List<AdicionalProduto>? adicionais,
    this.isBrinde = false,
  }) : adicionais = adicionais ?? [];"""

replacement_item_carrinho_ctor = """    List<AdicionalProduto>? adicionais,
    List<OpcaoPerguntaSelecao>? opcoesCombo,
    this.isBrinde = false,
  }) : adicionais = adicionais ?? [],
       opcoesCombo = opcoesCombo ?? [];"""

content = content.replace(target_item_carrinho_ctor, replacement_item_carrinho_ctor)

# Atualizar subtotal
target_subtotal = """  double get subtotal {
    if (isBrinde) return 0.0;
    final totalAdicionais = adicionais.fold(0.0, (sum, a) => sum + a.preco);
    return ((preco + totalAdicionais) * quantidade) - desconto;
  }
  double get subtotalSemDesconto {
    if (isBrinde) return 0.0;
    final totalAdicionais = adicionais.fold(0.0, (sum, a) => sum + a.preco);
    return (preco + totalAdicionais) * quantidade;
  }"""

replacement_subtotal = """  double get subtotal {
    if (isBrinde) return 0.0;
    final totalAdicionais = adicionais.fold(0.0, (sum, a) => sum + a.preco);
    final totalCombo = opcoesCombo.fold(0.0, (sum, o) => sum + o.precoAdicional);
    return ((preco + totalAdicionais + totalCombo) * quantidade) - desconto;
  }
  double get subtotalSemDesconto {
    if (isBrinde) return 0.0;
    final totalAdicionais = adicionais.fold(0.0, (sum, a) => sum + a.preco);
    final totalCombo = opcoesCombo.fold(0.0, (sum, o) => sum + o.precoAdicional);
    return (preco + totalAdicionais + totalCombo) * quantidade;
  }"""

content = content.replace(target_subtotal, replacement_subtotal)

# Atualizar toMap e fromMap do ItemCarrinho
target_tomap = """      'adicionais': adicionais.map((a) => a.toMap()).toList(),
      'isBrinde': isBrinde,
    };"""

replacement_tomap = """      'adicionais': adicionais.map((a) => a.toMap()).toList(),
      'opcoesCombo': opcoesCombo.map((o) => o.toMap()).toList(),
      'isBrinde': isBrinde,
    };"""

content = content.replace(target_tomap, replacement_tomap)

target_frommap = """      adicionais: (map['adicionais'] as List<dynamic>?)
          ?.map((a) => AdicionalProduto.fromMap(a as Map<String, dynamic>))
          .toList() ?? [],
      isBrinde: map['isBrinde'] ?? false,
    );"""

replacement_frommap = """      adicionais: (map['adicionais'] as List<dynamic>?)
          ?.map((a) => AdicionalProduto.fromMap(a as Map<String, dynamic>))
          .toList() ?? [],
      opcoesCombo: (map['opcoesCombo'] as List<dynamic>?)
          ?.map((o) => OpcaoPerguntaSelecao.fromMap(o as Map<String, dynamic>))
          .toList() ?? [],
      isBrinde: map['isBrinde'] ?? false,
    );"""

content = content.replace(target_frommap, replacement_frommap)
print("CLASSE_ITEM_CARRINHO_ATUALIZADA")


# --- 3. Atualizar _adicionarAoCarrinho para exibir o PopupPerguntasCombo ---
target_adicionar_ao_carrinho_begin = """  void _adicionarAoCarrinho(dynamic item, {bool manterFoco = false}) {
    if (item is! Produto) {
      _efetivarAdicaoAoCarrinho(item, manterFoco: manterFoco);
      return;
    }

    final produto = item as Produto;"""

replacement_adicionar_ao_carrinho_begin = """  void _adicionarAoCarrinho(dynamic item, {bool manterFoco = false}) {
    if (item is! Produto) {
      _efetivarAdicaoAoCarrinho(item, manterFoco: manterFoco);
      return;
    }

    final produto = item as Produto;
    final isServico = item is Servico;

    // INTERCEPTADOR DE COMBOS / PERGUNTAS DE SELEÇÃO
    if (produto.perguntasSelecao.isNotEmpty) {
      showDialog<List<OpcaoPerguntaSelecao>>(
        context: context,
        barrierDismissible: false,
        builder: (context) => PopupPerguntasCombo(produto: produto),
      ).then((opcoes) {
        if (opcoes != null) {
          _efetivarAdicaoAoCarrinho(
            produto,
            manterFoco: manterFoco,
            opcoesCombo: opcoes,
          );
        }
      });
      return;
    }"""

content = content.replace(target_adicionar_ao_carrinho_begin, replacement_adicionar_ao_carrinho_begin)
print("INTERCEPTADOR_POPUP_COMBO_ADICIONADO")


# --- 4. Atualizar assinatura e corpo do _efetivarAdicaoAoCarrinho ---
target_efetivar_sig = """  void _efetivarAdicaoAoCarrinho(dynamic item, {String? fornecedorNome, bool manterFoco = false}) {"""
replacement_efetivar_sig = """  void _efetivarAdicaoAoCarrinho(dynamic item, {String? fornecedorNome, bool manterFoco = false, List<OpcaoPerguntaSelecao>? opcoesCombo}) {"""

content = content.replace(target_efetivar_sig, replacement_efetivar_sig)

# Excluir agrupamento de itens com combos no carrinho para não misturar escolhas de combos diferentes
target_agrupamento = """    // Verificar se já existe no carrinho com MESMO fornecedor
    final index = _carrinho.indexWhere((c) => c.id == id && c.adicionais.isEmpty && c.fornecedorNome == fNome);"""

replacement_agrupamento = """    // Verificar se já existe no carrinho com MESMO fornecedor
    // Não agrupa itens de combo para manter as seleções separadas no carrinho
    final index = (opcoesCombo != null && opcoesCombo.isNotEmpty) 
        ? -1 
        : _carrinho.indexWhere((c) => c.id == id && c.adicionais.isEmpty && c.opcoesCombo.isEmpty && c.fornecedorNome == fNome);"""

content = content.replace(target_agrupamento, replacement_agrupamento)

target_item_carrinho_instantiation = """        _carrinho.add(
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
        );"""

replacement_item_carrinho_instantiation = """        _carrinho.add(
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
            opcoesCombo: opcoesCombo,
          ),
        );"""

content = content.replace(target_item_carrinho_instantiation, replacement_item_carrinho_instantiation)
print("EFETIVAR_ADICAO_AO_CARRINHO_ATUALIZADO")


# --- 5. Renderizar opções do combo abaixo do nome do item no carrinho ---
target_render_adicionais = """                      if (item.adicionais != null && item.adicionais!.isNotEmpty)
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
                        ),"""

replacement_render_adicionais = """                      if (item.adicionais != null && item.adicionais!.isNotEmpty)
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
                      if (item.opcoesCombo != null && item.opcoesCombo.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: item.opcoesCombo.map((o) => Padding(
                              padding: const EdgeInsets.only(bottom: 2),
                              child: Row(
                                children: [
                                  Icon(Icons.subdirectory_arrow_right_rounded, color: Colors.blueAccent.withOpacity(0.6), size: 10),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      '${o.nome}${o.precoAdicional > 0 ? " (+ R\$ ${o.precoAdicional.toStringAsFixed(2)})" : ""}',
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.55),
                                        fontSize: 10.5,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            )).toList(),
                          ),
                        ),"""

content = content.replace(target_render_adicionais, replacement_render_adicionais)
print("VISUALIZACAO_CARRINHO_PDV_ATUALIZADA")

with open(file_path, "w", encoding="utf-8") as f:
    f.write(content)
