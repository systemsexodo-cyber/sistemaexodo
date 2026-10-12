import '../models/empresa.dart';
import '../models/forma_pagamento.dart';
import '../models/forma_pagamento_custom.dart';

/// Resolve e calcula as taxas cobradas pelas maquininhas/adquirentes em cada
/// transação.
///
/// As taxas ficam na configuração da empresa:
///  - formas fixas do sistema: `configuracoes['pagamentos'][tipo].taxaFixa` e
///    `.taxaPercentual`;
///  - formas personalizadas: `configuracoes['formas_pagamento_custom']`.
class TaxaPagamentoService {
  static const String chaveFormasPersonalizadas = 'formas_pagamento_custom';

  /// Todas as formas personalizadas cadastradas pela empresa.
  static List<FormaPagamentoCustom> formasPersonalizadas(Empresa? empresa) {
    final raw = empresa?.configuracoes?[chaveFormasPersonalizadas];
    if (raw is! List) return <FormaPagamentoCustom>[];
    return raw
        .whereType<Map>()
        .map((m) => FormaPagamentoCustom.fromMap(Map<String, dynamic>.from(m)))
        .where((f) => f.nome.trim().isNotEmpty)
        .toList();
  }

  /// Apenas as formas personalizadas ativas (mostradas no PDV).
  static List<FormaPagamentoCustom> formasPersonalizadasAtivas(Empresa? empresa) =>
      formasPersonalizadas(empresa).where((f) => f.ativo).toList();

  /// Configuração de taxa de uma forma fixa do sistema.
  static Map<String, dynamic>? _configTipo(Empresa? empresa, TipoPagamento tipo) {
    final pagamentos = empresa?.configuracoes?['pagamentos'];
    if (pagamentos is! Map) return null;
    final cfg = pagamentos[tipo.name];
    return cfg is Map ? Map<String, dynamic>.from(cfg) : null;
  }

  static double _toDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString().replaceAll(',', '.')) ?? 0.0;
  }

  /// Taxa cobrada por uma forma fixa sobre um valor de transação.
  static double calcularTaxaTipo(Empresa? empresa, TipoPagamento tipo, double valor) {
    if (valor <= 0) return 0.0;
    final cfg = _configTipo(empresa, tipo);
    if (cfg == null) return 0.0;
    final fixa = _toDouble(cfg['taxaFixa']);
    final perc = _toDouble(cfg['taxaPercentual']);
    if (fixa == 0 && perc == 0) return 0.0;
    return (valor * perc / 100.0) + fixa;
  }

  /// Taxa cobrada por um pagamento já registrado (fixa ou personalizada).
  static double calcularTaxa(Empresa? empresa, PagamentoPedido pagamento) {
    if (pagamento.valor <= 0) return 0.0;

    final nome = pagamento.nomeForma?.trim();
    if (nome != null && nome.isNotEmpty) {
      final formas = formasPersonalizadas(empresa);
      for (final f in formas) {
        if (f.nome.toLowerCase() == nome.toLowerCase()) {
          return f.calcularTaxa(pagamento.valor);
        }
      }
    }

    return calcularTaxaTipo(empresa, pagamento.tipo, pagamento.valor);
  }

  /// Soma as taxas de uma coleção de pagamentos e agrupa por forma.
  static ResumoTaxas resumir(
    Empresa? empresa,
    Iterable<PagamentoPedido> pagamentos,
  ) {
    double total = 0.0;
    double totalTransacionado = 0.0;
    int quantidade = 0;
    final porForma = <String, double>{};

    for (final p in pagamentos) {
      final taxa = calcularTaxa(empresa, p);
      if (taxa <= 0) continue;
      total += taxa;
      totalTransacionado += p.valor;
      quantidade++;
      porForma[p.nomeExibicao] = (porForma[p.nomeExibicao] ?? 0.0) + taxa;
    }

    return ResumoTaxas(
      totalTaxas: total,
      totalTransacionado: totalTransacionado,
      quantidade: quantidade,
      porForma: porForma,
    );
  }
}

/// Resumo das taxas de maquininha em um conjunto de pagamentos.
class ResumoTaxas {
  final double totalTaxas;
  final double totalTransacionado;
  final int quantidade;
  final Map<String, double> porForma;

  const ResumoTaxas({
    required this.totalTaxas,
    required this.totalTransacionado,
    required this.quantidade,
    required this.porForma,
  });

  /// Percentual do valor transacionado consumido por taxas.
  double get percentualSobreTransacionado =>
      totalTransacionado > 0 ? (totalTaxas / totalTransacionado) * 100.0 : 0.0;

  bool get temTaxas => totalTaxas > 0;
}
