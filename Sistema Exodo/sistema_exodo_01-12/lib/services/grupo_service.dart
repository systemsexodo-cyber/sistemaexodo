import '../models/produto.dart';

class GrupoService {
  /// Retorna lista de grupos únicos dos produtos
  static List<String> obterGrupos(List<Produto> produtos) {
    final grupos = <String>{};
    for (var p in produtos) {
      if (p.grupo.isNotEmpty) {
        grupos.add(p.grupo);
      }
    }
    return grupos.toList()..sort();
  }

  /// Retorna produtos filtrados por grupo
  static List<Produto> obterProdutosPorGrupo(
    List<Produto> produtos,
    String grupo,
  ) {
    return produtos.where((p) => p.grupo == grupo).toList();
  }

  /// Atualiza preço de todos os produtos de um grupo
  static List<Produto> atualizarPrecoPorGrupo(
    List<Produto> produtos,
    String grupo,
    double novoPreco, {
    bool multiplicar = false,
  }) {
    return produtos.map((p) {
      if (p.grupo == grupo) {
        return Produto(
          id: p.id,
          codigo: p.codigo,
          codigoBarras: p.codigoBarras,
          nome: p.nome,
          descricao: p.descricao,
          unidade: p.unidade,
          grupo: p.grupo,
          preco: multiplicar ? p.preco * novoPreco : novoPreco,
          estoque: p.estoque,
          createdAt: p.createdAt,
          updatedAt: DateTime.now(),
        );
      }
      return p;
    }).toList();
  }

  /// Atualiza estoque de todos os produtos de um grupo
  static List<Produto> atualizarEstoquePorGrupo(
    List<Produto> produtos,
    String grupo,
    int novoEstoque, {
    bool adicionar = false,
  }) {
    return produtos.map((p) {
      if (p.grupo == grupo) {
        return Produto(
          id: p.id,
          codigo: p.codigo,
          codigoBarras: p.codigoBarras,
          nome: p.nome,
          descricao: p.descricao,
          unidade: p.unidade,
          grupo: p.grupo,
          preco: p.preco,
          estoque: adicionar ? p.estoque + novoEstoque : novoEstoque,
          createdAt: p.createdAt,
          updatedAt: DateTime.now(),
        );
      }
      return p;
    }).toList();
  }

  /// Muda todos os produtos de um grupo para outro grupo
  static List<Produto> renomearGrupo(
    List<Produto> produtos,
    String grupoAnterior,
    String novoGrupo,
  ) {
    return produtos.map((p) {
      if (p.grupo == grupoAnterior) {
        return Produto(
          id: p.id,
          codigo: p.codigo,
          codigoBarras: p.codigoBarras,
          nome: p.nome,
          descricao: p.descricao,
          unidade: p.unidade,
          grupo: novoGrupo,
          preco: p.preco,
          estoque: p.estoque,
          createdAt: p.createdAt,
          updatedAt: DateTime.now(),
        );
      }
      return p;
    }).toList();
  }

  /// Conta produtos por grupo
  static Map<String, int> contarProdutosPorGrupo(List<Produto> produtos) {
    final contagem = <String, int>{};
    for (var p in produtos) {
      contagem[p.grupo] = (contagem[p.grupo] ?? 0) + 1;
    }
    return contagem;
  }

  /// Calcula valor total do estoque por grupo
  static Map<String, double> calcularValorEstoquePorGrupo(
    List<Produto> produtos,
  ) {
    final valores = <String, double>{};
    for (var p in produtos) {
      final valor = p.preco * p.estoque;
      valores[p.grupo] = (valores[p.grupo] ?? 0) + valor;
    }
    return valores;
  }
}
