import os

file_path = r"c:\Users\charles\.antigravity\sistema_exodo_15-04-2026\lib\models\produto.dart"

with open(file_path, "r", encoding="utf-8") as f:
    content = f.read()

# --- 1. Adicionar o import ---
target_import = "import 'package:sistema_exodo_novo/models/item_composicao.dart';"
replacement_import = """import 'package:sistema_exodo_novo/models/item_composicao.dart';
import 'package:sistema_exodo_novo/models/pergunta_selecao.dart';"""

content = content.replace(target_import, replacement_import)
print("IMPORT_PERGUNTA_SELECAO_ADICIONADO")


# --- 2. Adicionar o atributo perguntasSelecao ---
target_attribute = """  // Produto Composto
  final bool ehComposto;
  final List<ItemComposicao> composicao;"""

replacement_attribute = """  // Produto Composto
  final bool ehComposto;
  final List<ItemComposicao> composicao;
  
  // Perguntas de Seleção (Combos Customizáveis)
  final List<PerguntaSelecao> perguntasSelecao;"""

content = content.replace(target_attribute, replacement_attribute)
print("ATRIBUTO_PERGUNTAS_SELECAO_ADICIONADO")


# --- 3. Adicionar no Construtor (fim dos parametros nomeados opcionais) ---
target_constructor_end = """    Map<String, double>? estoquePorFornecedor,
  }) : codigosFornecedor = codigosFornecedor ?? [],"""

replacement_constructor_end = """    Map<String, double>? estoquePorFornecedor,
    List<PerguntaSelecao>? perguntasSelecao,
  }) : codigosFornecedor = codigosFornecedor ?? [],
       perguntasSelecao = perguntasSelecao ?? [],"""

content = content.replace(target_constructor_end, replacement_constructor_end)
print("CONSTRUTOR_PERGUNTAS_SELECAO_ADICIONADO")


# --- 4. Adicionar no toMap ---
target_tomap = """      'pedido_compra_gerado': pedidoCompraGerado,
      'data_ultimo_pedido': dataUltimoPedido?.toIso8601String(),
    };"""

replacement_tomap = """      'pedido_compra_gerado': pedidoCompraGerado,
      'data_ultimo_pedido': dataUltimoPedido?.toIso8601String(),
      'perguntas_selecao': perguntasSelecao.map((p) => p.toMap()).toList(),
    };"""

content = content.replace(target_tomap, replacement_tomap)
print("TOMAP_PERGUNTAS_SELECAO_ADICIONADO")


# --- 5. Adicionar no fromMap ---
target_frommap = """      pedidoCompraGerado: getBool('pedidoCompraGerado', 'pedido_compra_gerado') ?? false,
      dataUltimoPedido: getDate('dataUltimoPedido', 'data_ultimo_pedido'),
    );"""

replacement_frommap = """      pedidoCompraGerado: getBool('pedidoCompraGerado', 'pedido_compra_gerado') ?? false,
      dataUltimoPedido: getDate('dataUltimoPedido', 'data_ultimo_pedido'),
      perguntasSelecao: getList('perguntasSelecao', 'perguntas_selecao')?.map((p) => PerguntaSelecao.fromMap(Map<String, dynamic>.from(p))).toList() ?? [],
    );"""

content = content.replace(target_frommap, replacement_frommap)
print("FROMMAP_PERGUNTAS_SELECAO_ADICIONADO")


# --- 6. Adicionar no copyWith ---
target_copywith_params = """    bool? pedidoCompraGerado,
    DateTime? dataUltimoPedido,
    bool? enviaBalanca,
    bool? cobrarGarcom,
    String? perfilTributarioId,
  }) {"""

replacement_copywith_params = """    bool? pedidoCompraGerado,
    DateTime? dataUltimoPedido,
    bool? enviaBalanca,
    bool? cobrarGarcom,
    String? perfilTributarioId,
    List<PerguntaSelecao>? perguntasSelecao,
  }) {"""

content = content.replace(target_copywith_params, replacement_copywith_params)

target_copywith_return = """      pedidoCompraGerado: pedidoCompraGerado ?? this.pedidoCompraGerado,
      dataUltimoPedido: dataUltimoPedido ?? this.dataUltimoPedido,
      enviaBalanca: enviaBalanca ?? this.enviaBalanca,
      cobrarGarcom: cobrarGarcom ?? this.cobrarGarcom,
      perfilTributarioId: perfilTributarioId ?? this.perfilTributarioId,
    );"""

replacement_copywith_return = """      pedidoCompraGerado: pedidoCompraGerado ?? this.pedidoCompraGerado,
      dataUltimoPedido: dataUltimoPedido ?? this.dataUltimoPedido,
      enviaBalanca: enviaBalanca ?? this.enviaBalanca,
      cobrarGarcom: cobrarGarcom ?? this.cobrarGarcom,
      perfilTributarioId: perfilTributarioId ?? this.perfilTributarioId,
      perguntasSelecao: perguntasSelecao ?? this.perguntasSelecao,
    );"""

content = content.replace(target_copywith_return, replacement_copywith_return)
print("COPYWITH_PERGUNTAS_SELECAO_ADICIONADO")

with open(file_path, "w", encoding="utf-8") as f:
    f.write(content)
