import '../models/funcionario.dart';
import '../models/pedido.dart';
import '../models/venda_balcao.dart';

/// Resultado agregado de um garçom em um período.
class GarcomResumo {
  final Funcionario funcionario;
  final double totalVendido;
  final double totalComissao;
  final int totalVendas;

  GarcomResumo({
    required this.funcionario,
    this.totalVendido = 0,
    this.totalComissao = 0,
    this.totalVendas = 0,
  });

  double get percentual => funcionario.porcentagemComissao;
}

/// Serviço de cálculo de VENDAS e COMISSÕES dos GARÇONS.
///
/// As vendas de mesas/comandas registram o operador (nome/email do garçom
/// logado). A comissão é calculada sobre o total vendido no período usando o
/// percentual do cadastro do funcionário (campo "Comissão %").
class GarcomService {
  /// Normaliza um identificador para comparação (email -> parte antes do @,
  /// tudo minúsculo e sem espaços).
  static String _normalizar(String? valor) {
    if (valor == null) return '';
    var v = valor.trim().toLowerCase();
    if (v.contains('@')) v = v.split('@').first;
    return v.replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  /// Verifica se a venda/pedido pertence ao garçom [funcionario], comparando
  /// o operador registrado com o nome e o email do funcionário.
  static bool vendaEdoGarcom(Funcionario f, String? operador) {
    final op = _normalizar(operador);
    if (op.isEmpty) return false;
    if (_normalizar(f.nome).isNotEmpty && op == _normalizar(f.nome)) return true;
    if (f.email != null && _normalizar(f.email).isNotEmpty && op == _normalizar(f.email)) return true;
    return false;
  }

  /// Comissão (em R$) de uma venda para o garçom, usando o percentual do
  /// cadastro (tipo 'Porcentagem'). Tipos 'Fixo' usam o valor fixo por venda.
  static double _comissaoDaVenda(Funcionario f, double valorVenda) {
    if (valorVenda <= 0) return 0;
    if (f.tipoComissao == 'Fixo') {
      return f.valorComissao > 0 ? f.valorComissao : 0;
    }
    if (f.porcentagemComissao <= 0) return 0;
    return valorVenda * (f.porcentagemComissao / 100);
  }

  /// Resumo de um garçom no período [inicio, fim].
  static GarcomResumo resumoDoGarcom({
    required Funcionario funcionario,
    required List<VendaBalcao> vendas,
    required List<Pedido> pedidos,
    required DateTime inicio,
    required DateTime fim,
  }) {
    double totalVendido = 0;
    int totalVendas = 0;

    for (final v in vendas) {
      if (v.cancelado) continue;
      if (v.dataVenda.isBefore(inicio) || v.dataVenda.isAfter(fim)) continue;
      if (!vendaEdoGarcom(funcionario, v.operador)) continue;
      totalVendido += v.valorTotal;
      totalVendas++;
    }
    for (final p in pedidos) {
      if (p.status == 'Cancelado') continue;
      if (p.dataPedido.isBefore(inicio) || p.dataPedido.isAfter(fim)) continue;
      if (!vendaEdoGarcom(funcionario, p.operador)) continue;
      totalVendido += p.total;
      totalVendas++;
    }

    return GarcomResumo(
      funcionario: funcionario,
      totalVendido: totalVendido,
      totalComissao: _comissaoDaVenda(funcionario, totalVendido),
      totalVendas: totalVendas,
    );
  }

  /// Ranking de TODOS os garçons (funcionários marcados como garçom) no
  /// período, ordenado por total vendido (decrescente).
  static List<GarcomResumo> rankingGarcons({
    required List<Funcionario> funcionarios,
    required List<VendaBalcao> vendas,
    required List<Pedido> pedidos,
    required DateTime inicio,
    required DateTime fim,
  }) {
    final resumos = funcionarios
        .where((f) => f.garcom && f.ativo)
        .map((f) => resumoDoGarcom(
              funcionario: f,
              vendas: vendas,
              pedidos: pedidos,
              inicio: inicio,
              fim: fim,
            ))
        .toList();
    resumos.sort((a, b) => b.totalVendido.compareTo(a.totalVendido));
    return resumos;
  }

  /// Início do período: 'hoje', 'semana', 'mês'.
  static DateTime inicioDoPeriodo(String periodo) {
    final agora = DateTime.now();
    final hoje = DateTime(agora.year, agora.month, agora.day);
    switch (periodo) {
      case 'hoje':
        return hoje;
      case 'semana':
        return hoje.subtract(Duration(days: agora.weekday - 1));
      case 'mês':
        return DateTime(agora.year, agora.month, 1);
      default:
        return hoje;
    }
  }

  /// Fim do período (inclusive): hoje, fim da semana (domingo) ou fim do mês.
  static DateTime fimDoPeriodo(String periodo) {
    final agora = DateTime.now();
    final hoje = DateTime(agora.year, agora.month, agora.day);
    switch (periodo) {
      case 'hoje':
        return hoje.add(const Duration(days: 1));
      case 'semana':
        return hoje.add(Duration(days: 8 - agora.weekday));
      case 'mês':
        final proximoMes = DateTime(agora.year, agora.month + 1, 1);
        return proximoMes;
      default:
        return hoje.add(const Duration(days: 1));
    }
  }
}
