// Exportação do Fluxo de Caixa em CSV.
//
// O gestor precisa levar as movimentações do dia/filtro para planilha. O CSV
// segue o padrão do resto do sistema (separador ';', decimal com vírgula) e só
// contabiliza entradas/saídas de verdade — mesas/comandas "a receber" saem como
// linha, mas fora dos totais.
//
// Rodar: flutter test test/caixa_fluxo_export_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_exodo_novo/services/caixa_fluxo_export_service.dart';

void main() {
  LinhaFluxoExport linha({
    required double valor,
    String tipo = 'Venda',
    String descricao = 'Venda PDV 1',
    String forma = 'Dinheiro',
    bool contabilizado = true,
    DateTime? data,
  }) =>
      LinhaFluxoExport(
        data: data ?? DateTime(2026, 10, 11, 9, 30),
        tipo: tipo,
        descricao: descricao,
        forma: forma,
        valor: valor,
        contabilizado: contabilizado,
      );

  test('monta o CSV com cabeçalho, linhas e totais', () {
    final csv = CaixaFluxoExportService.construirCSV(
      [
        linha(valor: 100, descricao: 'Venda PDV 1'),
        linha(
          valor: -40,
          tipo: 'Pagamento',
          descricao: 'Sangria - banco',
          forma: 'Dinheiro',
        ),
        linha(valor: 25.5, forma: 'PIX', descricao: 'Venda PDV 2'),
      ],
      caixa: 'CX1-0001',
      abertura: DateTime(2026, 10, 11, 8),
    );

    expect(csv, contains('FLUXO DE CAIXA - CX1-0001'));
    // Data e hora de ABERTURA do caixa: é o que identifica a sessão exportada.
    expect(csv, contains('Abertura do caixa;11/10/2026 08:00'));
    expect(csv, contains('Gerado em;'));
    expect(csv, contains('Data;Hora;Tipo;Descricao;Forma;Valor;Contabilizado'));
    expect(csv, contains('11/10/2026;09:30;Venda;Venda PDV 1;Dinheiro;100,00;Sim'));
    expect(csv, contains('Pagamento;Sangria - banco;Dinheiro;-40,00;Sim'));
    expect(csv, contains('PIX;25,50;Sim'));

    // Totais: 100 + 25,50 de entradas; 40 de saída; saldo 85,50.
    expect(csv, contains('Movimentacoes;3'));
    expect(csv, contains('Entradas;125,50'));
    expect(csv, contains('Saidas;40,00'));
    expect(csv, contains('Saldo;85,50'));
  });

  test('mesa/comanda a receber aparece como linha mas fora dos totais', () {
    final csv = CaixaFluxoExportService.construirCSV([
      linha(valor: 50),
      linha(
        valor: 80,
        tipo: 'Mesa',
        descricao: 'Mesa 5',
        forma: 'A receber · não contabilizado',
        contabilizado: false,
      ),
    ]);

    expect(csv, contains('Mesa 5'));
    expect(csv, contains('80,00;Nao'));

    // O total não pode incluir os 80 "a receber".
    expect(csv, contains('Movimentacoes;1'));
    expect(csv, contains('Entradas;50,00'));
    expect(csv, contains('Saldo;50,00'));
    expect(csv, contains('A receber (nao contabilizadas);1'));
  });

  test('escapa quebras de linha e ponto-e-vírgula da descrição', () {
    final csv = CaixaFluxoExportService.construirCSV([
      linha(valor: 10, descricao: 'Venda; teste\nlinha 2'),
    ]);
    expect(csv, contains('Venda, teste linha 2'));
    // O ';' da descrição não pode virar um separador extra de coluna.
    expect(
      csv
          .split('\n')
          .any((l) => l.contains('Venda, teste linha 2;Dinheiro;10,00;Sim')),
      isTrue,
    );
    expect(csv, isNot(contains('Venda; teste')));
  });

  test('sem abertura informada não imprime a linha de abertura', () {
    final csv = CaixaFluxoExportService.construirCSV([linha(valor: 10)]);
    expect(csv, isNot(contains('Abertura do caixa')));
  });

  test('lista vazia ainda gera cabeçalho com totais zerados', () {
    final csv = CaixaFluxoExportService.construirCSV([]);
    expect(csv, contains('Data;Hora;Tipo;Descricao;Forma;Valor;Contabilizado'));
    expect(csv, contains('Entradas;0,00'));
    expect(csv, contains('Saldo;0,00'));
    expect(csv, isNot(contains('A receber')));
  });
}
