import os

file_path = r"c:\Users\charles\.antigravity\sistema_exodo_15-04-2026\lib\pages\venda_direta_page.dart"

with open(file_path, "r", encoding="utf-8") as f:
    content = f.read()

# Ocorrência 1: Linha 5373
target_1 = """      final itensVenda = itensVendaCapturados
          .map(
            (item) => ItemVendaBalcao(
              id: item.id,
              nome: item.nome,
              precoUnitario: item.isBrinde ? 0.0 : item.preco,
              quantidade: item.quantidade,
              isServico: item.isServico,
              fornecedorNome: item.fornecedorNome,
              observacao: item.isBrinde 
                  ? (item.observacao != null && item.observacao!.isNotEmpty 
                      ? '[BRINDE] ${item.observacao}' 
                      : '[BRINDE]') 
                  : item.observacao,
            ),
          )
          .toList();"""

replacement_1 = """      final itensVenda = itensVendaCapturados
          .map(
            (item) => ItemVendaBalcao(
              id: item.id,
              nome: item.nome,
              precoUnitario: item.isBrinde ? 0.0 : item.preco,
              quantidade: item.quantidade,
              isServico: item.isServico,
              fornecedorNome: item.fornecedorNome,
              observacao: item.isBrinde 
                  ? (item.observacao != null && item.observacao!.isNotEmpty 
                      ? '[BRINDE] ${item.observacao}' 
                      : '[BRINDE]') 
                  : item.observacao,
              adicionais: item.adicionais,
              opcoesCombo: item.opcoesCombo,
            ),
          )
          .toList();"""

content = content.replace(target_1, replacement_1)


# Ocorrência 2: Linha 5811
target_2 = """    // Criar itens da venda balcão
    final itensVenda = _carrinho
        .map(
          (item) => ItemVendaBalcao(
            id: item.id,
            nome: item.nome,
            precoUnitario: item.preco,
            quantidade: item.quantidade,
            isServico: item.isServico,
            fornecedorNome: item.fornecedorNome,
            observacao: item.observacao,
            adicionais: item.adicionais,
          ),
        )
        .toList();"""

replacement_2 = """    // Criar itens da venda balcão
    final itensVenda = _carrinho
        .map(
          (item) => ItemVendaBalcao(
            id: item.id,
            nome: item.nome,
            precoUnitario: item.preco,
            quantidade: item.quantidade,
            isServico: item.isServico,
            fornecedorNome: item.fornecedorNome,
            observacao: item.observacao,
            adicionais: item.adicionais,
            opcoesCombo: item.opcoesCombo,
          ),
        )
        .toList();"""

content = content.replace(target_2, replacement_2)


# Ocorrência 3: Linha 6615
target_3 = """      final itensVenda = itensVendaCapturados
          .map(
            (item) => ItemVendaBalcao(
              id: item.id,
              nome: item.nome,
              precoUnitario: item.preco,
              quantidade: item.quantidade,
              isServico: item.isServico,
              fornecedorNome: item.fornecedorNome,
              observacao: item.observacao,
            ),
          )
          .toList();"""

replacement_3 = """      final itensVenda = itensVendaCapturados
          .map(
            (item) => ItemVendaBalcao(
              id: item.id,
              nome: item.nome,
              precoUnitario: item.preco,
              quantidade: item.quantidade,
              isServico: item.isServico,
              fornecedorNome: item.fornecedorNome,
              observacao: item.observacao,
              adicionais: item.adicionais,
              opcoesCombo: item.opcoesCombo,
            ),
          )
          .toList();"""

content = content.replace(target_3, replacement_3)


# Ocorrência 4: Linha 8018
target_4 = """      final itensVenda = _carrinho.map((item) => ItemVendaBalcao(
        id: item.id,
        nome: item.nome,
        precoUnitario: item.preco,
        quantidade: item.quantidade,
        isServico: item.isServico,
        fornecedorNome: item.fornecedorNome,
        observacao: item.observacao,
        adicionais: item.adicionais,
      )).toList();"""

replacement_4 = """      final itensVenda = _carrinho.map((item) => ItemVendaBalcao(
        id: item.id,
        nome: item.nome,
        precoUnitario: item.preco,
        quantidade: item.quantidade,
        isServico: item.isServico,
        fornecedorNome: item.fornecedorNome,
        observacao: item.observacao,
        adicionais: item.adicionais,
        opcoesCombo: item.opcoesCombo,
      )).toList();"""

content = content.replace(target_4, replacement_4)
print("MAPEAMENTO_VENDA_DIRETA_ATUALIZADO")

with open(file_path, "w", encoding="utf-8") as f:
    f.write(content)
