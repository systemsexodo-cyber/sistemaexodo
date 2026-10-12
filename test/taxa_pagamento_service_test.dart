import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_exodo_novo/models/empresa.dart';
import 'package:sistema_exodo_novo/models/forma_pagamento.dart';
import 'package:sistema_exodo_novo/models/forma_pagamento_custom.dart';
import 'package:sistema_exodo_novo/services/taxa_pagamento_service.dart';

Empresa _empresaComConfig(Map<String, dynamic> configuracoes) {
  return Empresa(
    id: 'empresa-teste',
    razaoSocial: 'Empresa Teste',
    slug: 'empresa-teste',
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
    configuracoes: configuracoes,
  );
}

void main() {
  group('FormaPagamentoCustom', () {
    test('calcula taxa fixa + percentual', () {
      const forma = FormaPagamentoCustom(
        id: '1',
        nome: 'Crédito 3x',
        taxaFixa: 2.0,
        taxaPercentual: 5.0,
      );

      // 100 * 5% = 5 + 2 fixa = 7
      expect(forma.calcularTaxa(100), closeTo(7.0, 0.001));
      expect(forma.calcularTaxa(0), 0);
    });

    test('empresa sem formas devolve lista mutável (regressão do add)', () {
      final empresa = _empresaComConfig({});
      final formas = empresa.formasPagamentoCustom;

      expect(formas, isEmpty);
      // Não pode ser uma lista imutável: a tela de Editar Empresa faz add().
      expect(
        () => formas.add(
          const FormaPagamentoCustom(id: '1', nome: 'VR'),
        ),
        returnsNormally,
      );
      expect(formas.length, 1);
    });

    test('round-trip de serialização', () {
      const forma = FormaPagamentoCustom(
        id: '1',
        nome: 'Caju',
        taxaFixa: 1.5,
        taxaPercentual: 0,
        ativo: false,
      );
      final copia = FormaPagamentoCustom.fromMap(forma.toMap());
      expect(copia.nome, 'Caju');
      expect(copia.taxaFixa, 1.5);
      expect(copia.ativo, false);
    });
  });

  group('TaxaPagamentoService', () {
    test('resolve taxa de forma fixa do sistema', () {
      final empresa = _empresaComConfig({
        'pagamentos': {
          'cartaoDebito': {'ativo': true, 'taxaFixa': 1.5},
        },
      });

      expect(
        TaxaPagamentoService.calcularTaxaTipo(
          empresa,
          TipoPagamento.cartaoDebito,
          200,
        ),
        closeTo(1.5, 0.001),
      );
      // Dinheiro não tem taxa configurada.
      expect(
        TaxaPagamentoService.calcularTaxaTipo(
          empresa,
          TipoPagamento.dinheiro,
          200,
        ),
        0,
      );
    });

    test('resolve taxa de forma personalizada pelo nome', () {
      final empresa = _empresaComConfig({
        'formas_pagamento_custom': [
          {
            'id': 'c1',
            'nome': 'Caju',
            'taxaFixa': 2.0,
            'taxaPercentual': 0,
            'ativo': true,
          },
        ],
      });

      final pagamento = PagamentoPedido(
        id: 'p1',
        tipo: TipoPagamento.outro,
        nomeForma: 'Caju',
        valor: 50,
        recebido: true,
      );

      expect(TaxaPagamentoService.calcularTaxa(empresa, pagamento), 2.0);
      expect(pagamento.nomeExibicao, 'Caju');
    });

    test('resume taxas por forma', () {
      final empresa = _empresaComConfig({
        'pagamentos': {
          'cartaoCredito': {'taxaFixa': 2.0},
          'cartaoDebito': {'taxaPercentual': 1.0},
        },
      });

      final resumo = TaxaPagamentoService.resumir(empresa, [
        PagamentoPedido(
          id: '1',
          tipo: TipoPagamento.cartaoCredito,
          valor: 100,
          recebido: true,
        ),
        PagamentoPedido(
          id: '2',
          tipo: TipoPagamento.cartaoDebito,
          valor: 100,
          recebido: true,
        ),
        PagamentoPedido(
          id: '3',
          tipo: TipoPagamento.dinheiro,
          valor: 50,
          recebido: true,
        ),
      ]);

      expect(resumo.totalTaxas, closeTo(3.0, 0.001));
      expect(resumo.quantidade, 2);
      expect(resumo.totalTransacionado, closeTo(200.0, 0.001));
      expect(resumo.porForma['Cartão de Crédito'], closeTo(2.0, 0.001));
      expect(resumo.porForma['Cartão de Débito'], closeTo(1.0, 0.001));
    });
  });
}
