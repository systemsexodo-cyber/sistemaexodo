/// Um ESTOQUE (local onde a mercadoria fica): Loja, Depósito, Caminhão…
///
/// Por que existe: o produto pode estar em mais de um lugar ao mesmo tempo, e a
/// venda acontece em UM lugar (o estoque principal, o "meu"). Sem separar os
/// saldos, o sistema só sabe o total — e não dá para saber o que precisa ser
/// trazido do depósito para a loja.
///
/// A lista de estoques mora na configuração da empresa
/// (`empresa.configuracoes['estoques']`), como os perfis tributários e os
/// departamentos: assim vale para todos os computadores sem mexer no banco.
/// O saldo de cada produto em cada estoque fica no próprio produto
/// (`estoquePorEstoque`), e a soma deles é o `estoque` total do produto.
class Estoque {
  final String id;
  final String nome;

  /// O estoque PRINCIPAL é "o meu": é onde a venda acontece e para onde a
  /// mercadoria é trazida quando sai de outro estoque. Só um é principal.
  final bool principal;

  /// Ordem de exibição nas listas e nos seletores.
  final int ordem;

  Estoque({
    required this.id,
    required this.nome,
    this.principal = false,
    this.ordem = 0,
  });

  factory Estoque.fromMap(Map<String, dynamic> map) {
    return Estoque(
      id: map['id']?.toString() ?? '',
      nome: map['nome']?.toString() ?? '',
      principal: map['principal'] == true,
      ordem: (map['ordem'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'nome': nome,
        'principal': principal,
        'ordem': ordem,
      };

  Estoque copyWith({String? id, String? nome, bool? principal, int? ordem}) {
    return Estoque(
      id: id ?? this.id,
      nome: nome ?? this.nome,
      principal: principal ?? this.principal,
      ordem: ordem ?? this.ordem,
    );
  }

  /// Estoque principal padrão do sistema (usado quando a empresa ainda não
  /// configurou nada): é a loja, o lugar onde a venda acontece.
  static Estoque loja() =>
      Estoque(id: 'estoque_loja', nome: 'Loja', principal: true, ordem: 0);

  /// Depósito padrão (o segundo estoque que já vem criado).
  static Estoque deposito() =>
      Estoque(id: 'estoque_deposito', nome: 'Depósito', principal: false, ordem: 1);

  /// Os dois estoques que já vêm criados para a empresa não começar vazia.
  static List<Estoque> padrao() => [loja(), deposito()];
}

/// Acha o estoque pelo id (tolerante a id nulo/vazio).
Estoque? estoquePorId(List<Estoque> estoques, String? id) {
  if (id == null || id.isEmpty) return null;
  for (final e in estoques) {
    if (e.id == id) return e;
  }
  return null;
}

/// O estoque principal ("o meu"). Se nenhum estiver marcado, o primeiro da
/// lista serve — o sistema nunca fica sem um destino para a transferência.
Estoque? estoquePrincipal(List<Estoque> estoques) {
  if (estoques.isEmpty) return null;
  for (final e in estoques) {
    if (e.principal) return e;
  }
  return estoques.first;
}

/// Nome do estoque para mostrar na tela (nunca vazio).
String nomeDoEstoque(List<Estoque> estoques, String? id) {
  final e = estoquePorId(estoques, id);
  if (e != null && e.nome.trim().isNotEmpty) return e.nome;
  return 'Estoque principal';
}
