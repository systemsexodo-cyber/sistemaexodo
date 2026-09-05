import '../models/venda_balcao.dart';
import 'data_service.dart';

/// Cálculos compartilhados de Lucro / DRE.
///
/// Usado pelo Dashboard (seção "Lucro / DRE") e pelo Relatório de Lucro
/// completo, garantindo que os números sejam idênticos nas duas telas.
///
/// O custo é o preço de custo ATUAL cadastrado no produto (os itens de venda
/// não persistem o custo histórico). Serviços e produtos sem custo cadastrado
/// entram com custo zero.
class LucroCalculator {
  LucroCalculator._();

  /// Vendas válidas dentro do intervalo [inicio, fim) — fim EXCLUSIVO,
  /// mesmo padrão usado no Dashboard (evita contar vendas fora do período).
  static List<VendaBalcao> vendasDoPeriodo(
      DataService dataService, DateTime inicio, DateTime fim) {
    return dataService.vendasBalcao
        .where((v) =>
            !v.isCancelada &&
            !v.dataVenda.isBefore(inicio) &&
            v.dataVenda.isBefore(fim))
        .toList();
  }

  /// Custo unitário atual do item. [cache] é um mapa opcional id -> custo
  /// para evitar consultas repetidas ao mesmo produto dentro de uma tela.
  static double custoUnitario(DataService dataService, ItemVendaBalcao item,
      [Map<String, double>? cache]) {
    if (item.isServico) return 0.0; // Serviços não têm custo cadastrado
    final cached = cache?[item.id];
    if (cached != null) return cached;
    final custo = dataService.getProdutoById(item.id)?.precoCusto ?? 0.0;
    final custoFinal = custo > 0 ? custo : 0.0;
    cache?[item.id] = custoFinal;
    return custoFinal;
  }

  /// Receita e custo efetivos de um item (desconta devoluções/trocas).
  static ({double receita, double custo, double quantidade}) somaItem(
      DataService dataService, ItemVendaBalcao item,
      [Map<String, double>? cache]) {
    final qtd = item.quantidadeEfetiva;
    if (qtd <= 0) return (receita: 0, custo: 0, quantidade: 0);
    final receita = item.subtotalEfetivo;
    final custo = custoUnitario(dataService, item, cache) * qtd;
    return (receita: receita, custo: custo, quantidade: qtd);
  }

  /// Grupo/categoria do produto (Serviços para itens de serviço).
  static String grupoDoProduto(DataService dataService, ItemVendaBalcao item) {
    if (item.isServico) return 'Serviços';
    final produto = dataService.getProdutoById(item.id);
    final grupo = produto?.grupo;
    if (grupo != null && grupo.trim().isNotEmpty) return grupo;
    return 'Sem Grupo';
  }

  /// Totais gerais do período: receita, custo (CMV), lucro, margem,
  /// ticket médio e quantidade de vendas.
  static Map<String, double> totais(
      DataService dataService, List<VendaBalcao> vendas,
      [Map<String, double>? cache]) {
    double receita = 0, custo = 0;
    int qtdVendas = 0;
    for (final venda in vendas) {
      qtdVendas++;
      receita += venda.valorTotal;
      for (final item in venda.itens) {
        custo += somaItem(dataService, item, cache).custo;
      }
    }
    final lucro = receita - custo;
    final margem = receita > 0 ? (lucro / receita) * 100 : 0.0;
    final ticketMedio = qtdVendas > 0 ? receita / qtdVendas : 0.0;
    return {
      'receita': receita,
      'custo': custo,
      'lucro': lucro,
      'margem': margem,
      'ticket': ticketMedio,
      'qtdVendas': qtdVendas.toDouble(),
    };
  }

  /// Ranking por produto (ordenado por lucro).
  static List<Map<String, dynamic>> porProduto(
      DataService dataService, List<VendaBalcao> vendas,
      [Map<String, double>? cache]) {
    final mapa = <String, Map<String, dynamic>>{};
    for (final venda in vendas) {
      for (final item in venda.itens) {
        final soma = somaItem(dataService, item, cache);
        if (soma.quantidade <= 0) continue;
        final nome = item.nome.isEmpty ? 'Item removido' : item.nome;
        final grupo = grupoDoProduto(dataService, item);
        final entrada = mapa.putIfAbsent(item.id, () => {
              'id': item.id,
              'nome': nome,
              'grupo': grupo,
              'quantidade': 0.0,
              'receita': 0.0,
              'custo': 0.0,
            });
        entrada['quantidade'] = (entrada['quantidade'] as double) + soma.quantidade;
        entrada['receita'] = (entrada['receita'] as double) + soma.receita;
        entrada['custo'] = (entrada['custo'] as double) + soma.custo;
      }
    }
    final lista = mapa.values.toList();
    for (final p in lista) {
      p['lucro'] = (p['receita'] as double) - (p['custo'] as double);
      p['margem'] = (p['receita'] as double) > 0
          ? ((p['lucro'] as double) / (p['receita'] as double)) * 100
          : 0.0;
    }
    lista.sort((a, b) => (b['lucro'] as double).compareTo(a['lucro'] as double));
    return lista;
  }

  /// Ranking por vendedor (ordenado por receita).
  static List<Map<String, dynamic>> porVendedor(
      DataService dataService, List<VendaBalcao> vendas,
      [Map<String, double>? cache]) {
    final mapa = <String, Map<String, dynamic>>{};
    for (final venda in vendas) {
      final nome = venda.vendedorNome != null && venda.vendedorNome!.trim().isNotEmpty
          ? venda.vendedorNome!
          : 'Sem vendedor';
      final entrada = mapa.putIfAbsent(nome, () => {
            'nome': nome,
            'quantidade': 0.0,
            'receita': 0.0,
            'custo': 0.0,
          });
      entrada['quantidade'] = (entrada['quantidade'] as double) + 1;
      entrada['receita'] = (entrada['receita'] as double) + venda.valorTotal;
      for (final item in venda.itens) {
        entrada['custo'] =
            (entrada['custo'] as double) + somaItem(dataService, item, cache).custo;
      }
    }
    final lista = mapa.values.toList();
    for (final p in lista) {
      p['lucro'] = (p['receita'] as double) - (p['custo'] as double);
      p['margem'] = (p['receita'] as double) > 0
          ? ((p['lucro'] as double) / (p['receita'] as double)) * 100
          : 0.0;
    }
    lista.sort((a, b) => (b['receita'] as double).compareTo(a['receita'] as double));
    return lista;
  }

  /// Ranking por grupo/categoria (ordenado por receita).
  static List<Map<String, dynamic>> porCategoria(
      DataService dataService, List<VendaBalcao> vendas,
      [Map<String, double>? cache]) {
    final mapa = <String, Map<String, dynamic>>{};
    for (final venda in vendas) {
      for (final item in venda.itens) {
        final soma = somaItem(dataService, item, cache);
        if (soma.quantidade <= 0) continue;
        final grupo = grupoDoProduto(dataService, item);
        final entrada = mapa.putIfAbsent(grupo, () => {
              'nome': grupo,
              'quantidade': 0.0,
              'receita': 0.0,
              'custo': 0.0,
            });
        entrada['quantidade'] = (entrada['quantidade'] as double) + soma.quantidade;
        entrada['receita'] = (entrada['receita'] as double) + soma.receita;
        entrada['custo'] = (entrada['custo'] as double) + soma.custo;
      }
    }
    final lista = mapa.values.toList();
    for (final p in lista) {
      p['lucro'] = (p['receita'] as double) - (p['custo'] as double);
      p['margem'] = (p['receita'] as double) > 0
          ? ((p['lucro'] as double) / (p['receita'] as double)) * 100
          : 0.0;
    }
    lista.sort((a, b) => (b['receita'] as double).compareTo(a['receita'] as double));
    return lista;
  }
}
