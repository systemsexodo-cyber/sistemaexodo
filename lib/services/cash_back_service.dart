/// Regras de negócio do cash back interno (modelo "saldo direto em R$").
///
/// Funciona como o PicPay/Nubank: a cada venda, um percentual vira saldo em R$
/// no cliente; o saldo pode pagar parte da próxima compra na hora.
///
/// Separei as regras aqui (e não dentro do PDV) para que, no futuro, trocar o
/// saldo interno por uma API externa de fidelidade signifique apenas trocar a
/// implementação de [CashBackProvider] — o PDV e o histórico não mudam.
library cash_back_rules;

import 'package:sistema_exodo_novo/models/cash_back_movimento.dart';
import 'package:sistema_exodo_novo/models/empresa.dart';

/// Percentual de cada venda que volta como cash back para o cliente.
///
/// 5%: valor padrão usado pelos programas de fidelidade mais comuns.
/// Pode ser sobrescrito por empresa via [taxaParaEmpresa].
const double taxaCashBackPorVenda = 0.05; // 5%

/// Limite padrão de uso do saldo por venda: quando ausente na empresa, o
/// cliente pode usar até 100% do total da venda com cash back (sem limite
/// percentual). Valores aceitáveis: 0.0 (sem uso) a 1.0 (100%).
const double limiteUsoPercentualPadrao = 1.0;

/// Regras puras do cash back. Não guarda estado — o saldo vive no
/// campo [Cliente.saldoCashback] (já sincronizado como os demais campos).
class CashBackService {
  /// Quanto o cliente ganha numa venda de [valorVenda].
  ///
  /// [taxa] é o percentual (ex: 0.05 = 5%). Quando omitido, usa a taxa padrão.
  static double ganhoPorVenda(double valorVenda, {double? taxa}) {
    if (valorVenda <= 0) return 0.0;
    final pct = taxa ?? taxaCashBackPorVenda;
    return arredondar2(valorVenda * pct);
  }

  /// Percentual de cash back configurado para a empresa, com fallback para o
  /// padrão de 5%. Lê de `empresa.configuracoes['cashback_taxa_percentual']`.
  static double taxaParaEmpresa(Empresa? empresa) {
    if (empresa == null || empresa.configuracoes == null) return taxaCashBackPorVenda;
    final raw = empresa.configuracoes!['cashback_taxa_percentual'] ??
        empresa.configuracoes!['cashbackTaxaPercentual'];
    if (raw == null) return taxaCashBackPorVenda;
    if (raw is num) return raw.toDouble() / 100;
    final parsed = double.tryParse(raw.toString());
    if (parsed == null) return taxaCashBackPorVenda;
    // Se o valor vier como "5" (percentual), converte; se vier como "0.05", usa direto.
    return parsed > 1 ? parsed / 100 : parsed;
  }

  /// Quanto do saldo o cliente pode usar nesta compra.
  ///
  /// Regra: nunca mais que o próprio saldo, nunca mais que o total da venda e
  /// nunca mais que [limiteUsoPercentual] do total (cash back não gera troco
  /// nem saldo negativo).
  static double maximoUsavel({
    required double saldo,
    required double totalVenda,
    double limiteUsoPercentual = limiteUsoPercentualPadrao,
  }) {
    if (saldo <= 0 || totalVenda <= 0) return 0.0;
    final limitePorSaldo = saldo < totalVenda ? saldo : totalVenda;
    // Limite percentual do total da venda (ex: no máximo 30% pode ser cash back)
    final limitePorPercentual = totalVenda * limiteUsoPercentual;
    final limite = limitePorSaldo < limitePorPercentual
        ? limitePorSaldo
        : limitePorPercentual;
    return arredondar2(limite);
  }

  /// Limite percentual de uso configurado para a empresa, com fallback para 1.0
  /// (sem limite percentual). Lê de `empresa.configuracoes['cashback_limite_uso_percentual']`.
  static double limiteUsoPercentualParaEmpresa(Empresa? empresa) {
    if (empresa == null || empresa.configuracoes == null) return limiteUsoPercentualPadrao;
    final raw = empresa.configuracoes!['cashback_limite_uso_percentual'] ??
        empresa.configuracoes!['cashbackLimiteUsoPercentual'];
    if (raw == null) return limiteUsoPercentualPadrao;
    if (raw is num) return raw.toDouble() / 100;
    final parsed = double.tryParse(raw.toString());
    if (parsed == null) return limiteUsoPercentualPadrao;
    return parsed > 1 ? parsed / 100 : parsed;
  }

  /// Novo saldo após usar [valorUsado] do saldo atual.
  static double novoSaldoAoUsar(double saldoAtual, double valorUsado) {
    final restante = saldoAtual - valorUsado;
    return restante < 0 ? 0.0 : arredondar2(restante);
  }

  /// Arredonda para 2 casas (centavos) sem acumular fração.
  static double arredondar2(double valor) =>
      (valor * 100).roundToDouble() / 100;

  // ============ VALIDADE DO SALDO ============

  /// Dias de validade do cash back configurado para a empresa.
  ///
  /// Lê `empresa.configuracoes['cashback_validade_dias']`. `0` (padrão) =
  /// saldo não expira. Valores negativos ou inválidos caem no padrão.
  static int validadeDiasParaEmpresa(Empresa? empresa) {
    if (empresa == null || empresa.configuracoes == null) return 0;
    final raw = empresa.configuracoes!['cashback_validade_dias'] ??
        empresa.configuracoes!['cashbackValidadeDias'];
    if (raw == null) return 0;
    final dias = raw is num ? raw.toInt() : int.tryParse(raw.toString());
    if (dias == null || dias < 0) return 0;
    return dias;
  }

  /// Data de expiração de um crédito feito em [dataCredito], conforme a
  /// validade da empresa. Retorna `null` quando não expira (0 dias).
  static DateTime? dataExpiracao(DateTime dataCredito, {required int validadeDias}) {
    if (validadeDias <= 0) return null;
    return dataCredito.add(Duration(days: validadeDias));
  }

  // ============ CONSUMO FIFO POR VENCIMENTO ============

  /// Ordena os créditos para consumo: os que vencem PRIMEIRO são consumidos
  /// primeiro; créditos sem validade vão por último (valem sempre). Empate
  /// por data (mais antigo primeiro).
  static List<CashBackMovimento> ordemDeConsumo(
    List<CashBackMovimento> creditos,
  ) {
    final lista = List<CashBackMovimento>.from(creditos);
    lista.sort((a, b) {
      final expA = a.expiraEm;
      final expB = b.expiraEm;
      if (expA == null && expB == null) return a.data.compareTo(b.data);
      if (expA == null) return 1; // sem validade: último
      if (expB == null) return -1;
      final porVencimento = expA.compareTo(expB);
      if (porVencimento != 0) return porVencimento;
      return a.data.compareTo(b.data);
    });
    return lista;
  }

  /// Consome [valorUsado] dos créditos seguindo a ordem de vencimento.
  ///
  /// Devolve os créditos com o campo `consumido` atualizado. Nunca deixa
  /// `consumido` maior que o próprio valor do crédito.
  static List<CashBackMovimento> consumirDosCreditos(
    List<CashBackMovimento> movimentos,
    double valorUsado,
  ) {
    var restante = arredondar2(valorUsado);
    if (restante <= 0) return movimentos;

    final creditos = ordemDeConsumo(
      movimentos.where((m) => m.tipo == CashBackMovimentoTipo.credito).toList(),
    );
    if (creditos.isEmpty) return movimentos;

    final consumidoPorId = <String, double>{};
    for (final credito in creditos) {
      if (restante <= 0) break;
      final disponivel = arredondar2(credito.restante);
      if (disponivel <= 0) continue;
      final consome = disponivel < restante ? disponivel : restante;
      consumidoPorId[credito.id] =
          arredondar2(credito.consumido + consome);
      restante = arredondar2(restante - consome);
    }
    if (consumidoPorId.isEmpty) return movimentos;

    return movimentos.map((m) {
      final novo = consumidoPorId[m.id];
      return novo == null ? m : m.copyWith(consumido: novo);
    }).toList();
  }

  // ============ SALDO VENCIDO ============

  /// Quanto do saldo dos créditos de [clienteId] já venceu (crédito com
  /// `expiraEm` no passado e ainda não totalmente consumido).
  static double saldoVencido(
    List<CashBackMovimento> movimentos, {
    required String clienteId,
    DateTime? agora,
  }) {
    final instante = agora ?? DateTime.now();
    double vencido = 0;
    for (final m in movimentos) {
      if (m.clienteId != clienteId) continue;
      if (m.tipo != CashBackMovimentoTipo.credito) continue;
      final expira = m.expiraEm;
      if (expira == null || expira.isAfter(instante)) continue;
      vencido += m.restante;
    }
    return arredondar2(vencido);
  }

  /// Quanto do saldo do cliente ainda está VÁLIDO (não venceu).
  static double saldoValido(
    List<CashBackMovimento> movimentos, {
    required String clienteId,
    DateTime? agora,
  }) {
    final instante = agora ?? DateTime.now();
    double valido = 0;
    for (final m in movimentos) {
      if (m.clienteId != clienteId) continue;
      if (m.tipo != CashBackMovimentoTipo.credito) continue;
      final expira = m.expiraEm;
      if (expira != null && expira.isBefore(instante)) continue; // vencido
      valido += m.restante;
    }
    return arredondar2(valido);
  }
}

/// Porta de troca para uma API externa de cash back/fidelidade no futuro.
///
/// Hoje só existe a implementação interna; quando você integrar um provedor
/// externo, implemente esta interface e troque onde o provider é criado —
/// sem mexer no fluxo de venda.
abstract class CashBackProvider {
  /// Crédito gerado por uma venda de [valorVenda].
  double ganhoPorVenda(double valorVenda);

  /// Quanto pode ser usado numa compra com total [totalVenda] e saldo [saldo].
  double maximoUsavel({required double saldo, required double totalVenda});
}

/// Implementação interna (saldo local no cadastro do cliente).
class CashBackProviderInterno implements CashBackProvider {
  const CashBackProviderInterno();

  @override
  double ganhoPorVenda(double valorVenda) =>
      CashBackService.ganhoPorVenda(valorVenda);

  @override
  double maximoUsavel({required double saldo, required double totalVenda}) =>
      CashBackService.maximoUsavel(saldo: saldo, totalVenda: totalVenda);
}

/// Fábrica: troque por um provider externo quando decidir integrar uma API.
const CashBackProvider cashBackProvider = CashBackProviderInterno();
