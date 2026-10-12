// Filtro por horário das movimentações do caixa (Fluxo de Caixa e modal de um
// caixa encerrado).
//
// O gestor precisa responder "o que entrou de PIX entre 18h e 20h?" — a janela
// de horário é aplicada sobre a data/hora de cada movimentação, e pode
// atravessar a meia-noite (bar/restaurante).
//
// Rodar: flutter test test/caixa_mov_filtro_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_exodo_novo/services/caixa_mov_filtro_service.dart';

void main() {
  Map<String, dynamic> mov(DateTime data, {double valor = 10}) => {
        'data': data,
        'descricao': 'Venda PDV 1',
        'valor': valor,
        'tipo': 'Venda',
      };

  group('minutosDoDia / formatarMinutos', () {
    test('converte DateTime em minutos desde a meia-noite', () {
      expect(CaixaMovFiltroService.minutosDoDia(DateTime(2026, 10, 11, 8, 30)), 510);
      expect(CaixaMovFiltroService.minutosDoDia(DateTime(2026, 10, 11, 0, 0)), 0);
      expect(CaixaMovFiltroService.minutosDoDia(DateTime(2026, 10, 11, 23, 59)), 1439);
    });

    test('formata minutos como HH:mm', () {
      expect(CaixaMovFiltroService.formatarMinutos(510), '08:30');
      expect(CaixaMovFiltroService.formatarMinutos(0), '00:00');
      expect(CaixaMovFiltroService.formatarMinutos(1439), '23:59');
    });
  });

  group('janelaAtiva', () {
    test('exige os dois extremos', () {
      expect(CaixaMovFiltroService.janelaAtiva(null, null), isFalse);
      expect(CaixaMovFiltroService.janelaAtiva(480, null), isFalse);
      expect(CaixaMovFiltroService.janelaAtiva(null, 720), isFalse);
      expect(CaixaMovFiltroService.janelaAtiva(480, 720), isTrue);
    });

    test('rotulo devolve null quando a janela está inativa', () {
      expect(CaixaMovFiltroService.rotulo(480, null), isNull);
      expect(CaixaMovFiltroService.rotulo(480, 720), '08:00 → 12:00');
    });
  });

  group('dentroDaJanela', () {
    test('inclui as duas pontas da janela', () {
      expect(CaixaMovFiltroService.dentroDaJanela(480, 480, 720), isTrue); // 08:00
      expect(CaixaMovFiltroService.dentroDaJanela(720, 480, 720), isTrue); // 12:00
      expect(CaixaMovFiltroService.dentroDaJanela(600, 480, 720), isTrue); // 10:00
      expect(CaixaMovFiltroService.dentroDaJanela(479, 480, 720), isFalse);
      expect(CaixaMovFiltroService.dentroDaJanela(721, 480, 720), isFalse);
    });

    test('janela invertida atravessa a meia-noite', () {
      // 22:00 → 02:00
      expect(CaixaMovFiltroService.dentroDaJanela(22 * 60, 22 * 60, 120), isTrue);
      expect(CaixaMovFiltroService.dentroDaJanela(23 * 60 + 30, 22 * 60, 120), isTrue);
      expect(CaixaMovFiltroService.dentroDaJanela(60, 22 * 60, 120), isTrue);
      expect(CaixaMovFiltroService.dentroDaJanela(2 * 60, 22 * 60, 120), isTrue);
      expect(CaixaMovFiltroService.dentroDaJanela(3 * 60, 22 * 60, 120), isFalse);
      expect(CaixaMovFiltroService.dentroDaJanela(12 * 60, 22 * 60, 120), isFalse);
    });
  });

  group('porHorario', () {
    final movs = [
      mov(DateTime(2026, 10, 11, 8, 0), valor: 10),
      mov(DateTime(2026, 10, 11, 13, 45), valor: 20),
      mov(DateTime(2026, 10, 11, 19, 30), valor: 30),
    ];

    test('sem a janela completa devolve a lista intacta', () {
      expect(CaixaMovFiltroService.porHorario(movs).length, 3);
      expect(CaixaMovFiltroService.porHorario(movs, inicioMin: 480).length, 3);
      expect(CaixaMovFiltroService.porHorario(movs, fimMin: 1200).length, 3);
    });

    test('mantém só as movimentações da janela escolhida', () {
      // 12:00 → 20:00 pega 13:45 e 19:30, mas não a venda das 08:00.
      final tarde = CaixaMovFiltroService.porHorario(movs, inicioMin: 720, fimMin: 1200);
      expect(tarde.length, 2);
      expect(tarde.map((m) => m['valor']), [20, 30]);

      // 12:00 → 18:00 deixa a venda das 19:30 de fora.
      final ateAs18 = CaixaMovFiltroService.porHorario(movs, inicioMin: 720, fimMin: 1080);
      expect(ateAs18.length, 1);
      expect(ateAs18.single['valor'], 20);

      final manha = CaixaMovFiltroService.porHorario(movs, inicioMin: 480, fimMin: 600);
      expect(manha.length, 1);
      expect(manha.single['valor'], 10);
    });

    test('janela sem movimento devolve lista vazia', () {
      final madrugada = CaixaMovFiltroService.porHorario(movs, inicioMin: 0, fimMin: 300);
      expect(madrugada, isEmpty);
    });

    test('movimentação sem data válida fica de fora', () {
      final comLixo = [
        mov(DateTime(2026, 10, 11, 10, 0)),
        {'data': null, 'valor': 5.0},
      ];
      final dentro = CaixaMovFiltroService.porHorario(comLixo, inicioMin: 480, fimMin: 720);
      expect(dentro.length, 1);
    });
  });
}
