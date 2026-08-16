import os

file_path = r"c:\Users\charles\.antigravity\sistema_exodo_15-04-2026\lib\models\venda_balcao.dart"

with open(file_path, "r", encoding="utf-8") as f:
    content = f.read()

# --- 1. Adicionar o import ---
target_import = "import 'package:sistema_exodo_novo/models/delivery_info.dart';"
replacement_import = """import 'package:sistema_exodo_novo/models/delivery_info.dart';
import 'package:sistema_exodo_novo/models/pergunta_selecao.dart';"""

content = content.replace(target_import, replacement_import)


# --- 2. Adicionar o atributo opcoesCombo em ItemVendaBalcao ---
target_fields = """  final String? observacao;
  final List<AdicionalProduto> adicionais;

  ItemVendaBalcao({"""

replacement_fields = """  final String? observacao;
  final List<AdicionalProduto> adicionais;
  final List<OpcaoPerguntaSelecao> opcoesCombo;

  ItemVendaBalcao({"""

content = content.replace(target_fields, replacement_fields)

target_ctor = """    List<AdicionalProduto>? adicionais,
  }) : adicionais = adicionais ?? [];"""

replacement_ctor = """    List<AdicionalProduto>? adicionais,
    List<OpcaoPerguntaSelecao>? opcoesCombo,
  }) : adicionais = adicionais ?? [],
       opcoesCombo = opcoesCombo ?? [];"""

content = content.replace(target_ctor, replacement_ctor)


# --- 3. Atualizar subtotal ---
target_subtotals = """  double get subtotal {
    final totalAdicionais = adicionais.fold(0.0, (sum, a) => sum + a.preco);
    return (precoUnitario + totalAdicionais) * quantidade;
  }

  /// Subtotal efetivo (descontando devoluções)
  double get subtotalEfetivo {
    final totalAdicionais = adicionais.fold(0.0, (sum, a) => sum + a.preco);
    return (precoUnitario + totalAdicionais) * quantidadeEfetiva;
  }"""

replacement_subtotals = """  double get subtotal {
    final totalAdicionais = adicionais.fold(0.0, (sum, a) => sum + a.preco);
    final totalCombo = opcoesCombo.fold(0.0, (sum, o) => sum + o.precoAdicional);
    return (precoUnitario + totalAdicionais + totalCombo) * quantidade;
  }

  /// Subtotal efetivo (descontando devoluções)
  double get subtotalEfetivo {
    final totalAdicionais = adicionais.fold(0.0, (sum, a) => sum + a.preco);
    final totalCombo = opcoesCombo.fold(0.0, (sum, o) => sum + o.precoAdicional);
    return (precoUnitario + totalAdicionais + totalCombo) * quantidadeEfetiva;
  }"""

content = content.replace(target_subtotals, replacement_subtotals)


# --- 4. Atualizar fromMap ---
target_frommap = """      adicionais: (getList('adicionais', 'adicionais', map) as List<dynamic>?)
          ?.map((a) => AdicionalProduto.fromMap(a as Map<String, dynamic>))
          .toList() ?? [],
    );"""

replacement_frommap = """      adicionais: (getList('adicionais', 'adicionais', map) as List<dynamic>?)
          ?.map((a) => AdicionalProduto.fromMap(a as Map<String, dynamic>))
          .toList() ?? [],
      opcoesCombo: (getList('opcoesCombo', 'opcoes_combo', map) as List<dynamic>?)
          ?.map((o) => OpcaoPerguntaSelecao.fromMap(o as Map<String, dynamic>))
          .toList() ?? [],
    );"""

content = content.replace(target_frommap, replacement_frommap)


# --- 5. Atualizar toMap ---
target_tomap = """      'adicionais': adicionais.map((a) => a.toMap()).toList(),
    };"""

replacement_tomap = """      'adicionais': adicionais.map((a) => a.toMap()).toList(),
      'opcoes_combo': opcoesCombo.map((o) => o.toMap()).toList(),
    };"""

content = content.replace(target_tomap, replacement_tomap)


# --- 6. Atualizar copyWith ---
target_copywith_params = """    double? quantidadeTrocada,
    String? trocadoPor,
    String? fornecedorNome,
    String? observacao,
    List<AdicionalProduto>? adicionais,
  }) {"""

replacement_copywith_params = """    double? quantidadeTrocada,
    String? trocadoPor,
    String? fornecedorNome,
    String? observacao,
    List<AdicionalProduto>? adicionais,
    List<OpcaoPerguntaSelecao>? opcoesCombo,
  }) {"""

content = content.replace(target_copywith_params, replacement_copywith_params)

target_copywith_return = """      fornecedorNome: fornecedorNome ?? this.fornecedorNome,
      observacao: observacao ?? this.observacao,
      adicionais: adicionais ?? this.adicionais,
    );"""

replacement_copywith_return = """      fornecedorNome: fornecedorNome ?? this.fornecedorNome,
      observacao: observacao ?? this.observacao,
      adicionais: adicionais ?? this.adicionais,
      opcoesCombo: opcoesCombo ?? this.opcoesCombo,
    );"""

content = content.replace(target_copywith_return, replacement_copywith_return)
print("MODELO_ITEM_VENDA_BALCAO_ATUALIZADO")

with open(file_path, "w", encoding="utf-8") as f:
    f.write(content)
