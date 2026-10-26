import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_exodo_novo/models/cash_back_movimento.dart';
import 'package:sistema_exodo_novo/models/empresa.dart';
import 'package:sistema_exodo_novo/services/cash_back_service.dart';

void main() {
  group('CashBackService — modelo saldo direto em R\$', () {
    test('ganhoPorVenda aplica o percentual padrão (5%)', () {
      expect(CashBackService.ganhoPorVenda(100.0), 5.0);
      expect(CashBackService.ganhoPorVenda(37.50), 1.88); // 1.875 arredonda
      expect(CashBackService.ganhoPorVenda(0), 0.0);
      expect(CashBackService.ganhoPorVenda(-10), 0.0);
    });

    test('ganhoPorVenda nunca gera fração de centavo', () {
      final ganho = CashBackService.ganhoPorVenda(19.99);
      expect((ganho * 100) % 1, 0.0); // sempre 2 casas
    });

    test('maximoUsavel limita pelo saldo quando o saldo é menor', () {
      expect(
        CashBackService.maximoUsavel(saldo: 30.0, totalVenda: 100.0),
        30.0,
      );
    });

    test('maximoUsavel limita pelo total da venda quando o saldo é maior', () {
      expect(
        CashBackService.maximoUsavel(saldo: 500.0, totalVenda: 80.0),
        80.0,
      );
    });

    test('maximoUsavel devolve 0 sem saldo ou sem venda', () {
      expect(CashBackService.maximoUsavel(saldo: 0, totalVenda: 50.0), 0.0);
      expect(CashBackService.maximoUsavel(saldo: 50.0, totalVenda: 0), 0.0);
      expect(CashBackService.maximoUsavel(saldo: -5, totalVenda: 50.0), 0.0);
    });

    test('novoSaldoAoUsar nunca deixa saldo negativo', () {
      expect(CashBackService.novoSaldoAoUsar(100.0, 40.0), 60.0);
      expect(CashBackService.novoSaldoAoUsar(100.0, 150.0), 0.0);
    });

    test('fluxo completo: ganha numa venda, gasta na seguinte', () {
      // Cliente compra R\$ 200 → ganha 5% = R\$ 10
      final ganho = CashBackService.ganhoPorVenda(200.0);
      expect(ganho, 10.0);

      // Próxima compra de R\$ 50 usando todo o saldo
      final usado = CashBackService.maximoUsavel(
        saldo: ganho,
        totalVenda: 50.0,
      );
      expect(usado, 10.0);

      // Saldo zerado após o uso
      expect(CashBackService.novoSaldoAoUsar(ganho, usado), 0.0);

      // Ganho considera só o valor pago SEM cash back (R\$ 50 - R\$ 10 = R\$ 40)
      final ganho2 = CashBackService.ganhoPorVenda(50.0 - usado);
      expect(ganho2, 2.0);
    });

    test('provider interno segue as mesmas regras do serviço', () {
      expect(cashBackProvider.ganhoPorVenda(100.0), 5.0);
      expect(
        cashBackProvider.maximoUsavel(saldo: 7.0, totalVenda: 100.0),
        7.0,
      );
    });
  });

  group('CashBackService — configuração por empresa', () {
    Empresa empresaCom(Map<String, dynamic> config) => Empresa(
      id: 'e1',
      razaoSocial: 'Teste',
      slug: 'teste',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      configuracoes: config,
    );

    test('taxaParaEmpresa converte percentual em fração', () {
      expect(CashBackService.taxaParaEmpresa(null), 0.05);
      expect(
        CashBackService.taxaParaEmpresa(
          empresaCom({'cashback_taxa_percentual': 8}),
        ),
        0.08,
      );
      expect(
        CashBackService.taxaParaEmpresa(
          empresaCom({'cashback_taxa_percentual': '3.5'}),
        ),
        0.035,
      );
    });

    test('limiteUsoPercentualParaEmpresa limita o uso por venda', () {
      expect(CashBackService.limiteUsoPercentualParaEmpresa(null), 1.0);
      final empresa = empresaCom({'cashback_limite_uso_percentual': 30});
      expect(CashBackService.limiteUsoPercentualParaEmpresa(empresa), 0.3);
      expect(
        CashBackService.maximoUsavel(
          saldo: 100.0,
          totalVenda: 100.0,
          limiteUsoPercentual:
              CashBackService.limiteUsoPercentualParaEmpresa(empresa),
        ),
        30.0,
      );
    });

    test('validadeDiasParaEmpresa e dataExpiracao', () {
      expect(CashBackService.validadeDiasParaEmpresa(null), 0);
      final empresa = empresaCom({'cashback_validade_dias': 90});
      expect(CashBackService.validadeDiasParaEmpresa(empresa), 90);
      final credito = DateTime(2026, 1, 1);
      expect(
        CashBackService.dataExpiracao(credito, validadeDias: 90),
        DateTime(2026, 4, 1),
      );
      expect(CashBackService.dataExpiracao(credito, validadeDias: 0), isNull);
    });
  });

  group('CashBackService — consumo FIFO por vencimento', () {
    CashBackMovimento credito({
      required String id,
      required double valor,
      required DateTime data,
      DateTime? expiraEm,
    }) =>
        CashBackMovimento(
          id: id,
          clienteId: 'c1',
          tipo: CashBackMovimentoTipo.credito,
          valor: valor,
          saldoApos: valor,
          data: data,
          expiraEm: expiraEm,
        );

    test('ordemDeConsumo: vence primeiro consome primeiro; sem validade por último', () {
      final semValidade = credito(id: 'a', valor: 5, data: DateTime(2026, 1, 1));
      final venceDepois = credito(
        id: 'b',
        valor: 5,
        data: DateTime(2026, 1, 2),
        expiraEm: DateTime(2026, 6, 1),
      );
      final venceAntes = credito(
        id: 'c',
        valor: 5,
        data: DateTime(2026, 1, 3),
        expiraEm: DateTime(2026, 3, 1),
      );
      final ordem = CashBackService.ordemDeConsumo([
        semValidade,
        venceDepois,
        venceAntes,
      ]);
      expect(ordem.map((m) => m.id).toList(), ['c', 'b', 'a']);
    });

    test('consumirDosCreditos atualiza consumido na ordem FIFO', () {
      final c1 = credito(
        id: 'c1',
        valor: 10,
        data: DateTime(2026, 1, 1),
        expiraEm: DateTime(2026, 3, 1),
      );
      final c2 = credito(
        id: 'c2',
        valor: 10,
        data: DateTime(2026, 1, 2),
        expiraEm: DateTime(2026, 9, 1),
      );
      final result = CashBackService.consumirDosCreditos([c1, c2], 12.0);
      final r1 = result.firstWhere((m) => m.id == 'c1');
      final r2 = result.firstWhere((m) => m.id == 'c2');
      expect(r1.consumido, 10.0); // vence primeiro: consumido por completo
      expect(r2.consumido, 2.0); // resto vai para o segundo
      expect(r1.restante, 0.0);
      expect(r2.restante, 8.0);
    });

    test('consumirDosCreditos nunca passa do saldo dos créditos', () {
      final c1 = credito(id: 'c1', valor: 5, data: DateTime(2026, 1, 1));
      final result = CashBackService.consumirDosCreditos([c1], 50.0);
      expect(result.first.consumido, 5.0);
      expect(result.first.restante, 0.0);
    });

    test('saldoVencido e saldoValido separam o que venceu do que vale', () {
      final agora = DateTime(2026, 5, 1);
      final vencido = credito(
        id: 'v',
        valor: 10,
        data: DateTime(2026, 1, 1),
        expiraEm: DateTime(2026, 4, 1),
      );
      final vigente = credito(
        id: 'g',
        valor: 7,
        data: DateTime(2026, 4, 15),
        expiraEm: DateTime(2026, 8, 1),
      );
      final movimentos = [vencido, vigente];
      expect(
        CashBackService.saldoVencido(movimentos, clienteId: 'c1', agora: agora),
        10.0,
      );
      expect(
        CashBackService.saldoValido(movimentos, clienteId: 'c1', agora: agora),
        7.0,
      );
      // Outro cliente não entra na conta
      expect(
        CashBackService.saldoVencido(movimentos, clienteId: 'outro', agora: agora),
        0.0,
      );
    });

    test('crédito parcialmente consumido: vencido conta só o restante', () {
      final agora = DateTime(2026, 5, 1);
      final c = credito(
        id: 'x',
        valor: 10,
        data: DateTime(2026, 1, 1),
        expiraEm: DateTime(2026, 4, 1),
      ).copyWith(consumido: 4.0);
      expect(
        CashBackService.saldoVencido([c], clienteId: 'c1', agora: agora),
        6.0,
      );
    });
  });
}
