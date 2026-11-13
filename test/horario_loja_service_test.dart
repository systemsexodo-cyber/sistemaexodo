import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_exodo_novo/services/horario_loja_service.dart';

void main() {
  // É o mapa de `configuracoes['ecommerce']`, como a loja recebe.
  Map<String, dynamic> configCom(Map<String, HorarioDiaLoja> horarios) => {
        'horariosFuncionamento': HorarioLojaService.paraConfig(horarios),
      };

  // 2026-11-09 é uma segunda-feira.
  DateTime segunda(int hora, [int minuto = 0]) =>
      DateTime(2026, 11, 9, hora, minuto);

  test('sem configuração a loja continua aberta', () {
    final status = HorarioLojaService.status(ecommerce: {}, agora: segunda(3));
    expect(status.aberta, isTrue);
    expect(status.configurado, isFalse);
  });

  test('dentro do horário do dia fica aberta e informa a hora de fechar', () {
    final horarios = HorarioLojaService.padrao();
    final status = HorarioLojaService.status(
      ecommerce: configCom(horarios),
      agora: segunda(10),
    );
    expect(status.aberta, isTrue);
    expect(status.fechaAs, '18:00');
    expect(status.detalhe, 'Aberta até 18:00');
  });

  test('antes de abrir fica fechada e aponta a abertura do mesmo dia', () {
    final status = HorarioLojaService.status(
      ecommerce: configCom(HorarioLojaService.padrao()),
      agora: segunda(6, 30),
    );
    expect(status.aberta, isFalse);
    expect(status.proximaAbertura, 'Abre hoje às 08:00');
  });

  test('depois de fechar aponta a abertura do dia seguinte', () {
    final status = HorarioLojaService.status(
      ecommerce: configCom(HorarioLojaService.padrao()),
      agora: segunda(20),
    );
    expect(status.aberta, isFalse);
    expect(status.proximaAbertura, 'Abre amanhã às 08:00');
  });

  test('domingo fechado aponta a abertura de amanhã (segunda)', () {
    final status = HorarioLojaService.status(
      ecommerce: configCom(HorarioLojaService.padrao()),
      agora: DateTime(2026, 11, 8, 10), // domingo
    );
    expect(status.aberta, isFalse);
    expect(status.proximaAbertura, 'Abre amanhã às 08:00');
  });

  test('dia desligado no meio da semana é respeitado', () {
    final horarios = HorarioLojaService.padrao()
      ..['qua'] = const HorarioDiaLoja(aberto: false);
    final status = HorarioLojaService.status(
      ecommerce: configCom(horarios),
      agora: DateTime(2026, 11, 11, 10), // quarta
    );
    expect(status.aberta, isFalse);
    expect(status.proximaAbertura, 'Abre amanhã às 08:00');
  });

  test('janela que atravessa a meia-noite continua aberta depois dela', () {
    final horarios = HorarioLojaService.padrao()
      ..['seg'] = const HorarioDiaLoja(abre: '18:00', fecha: '02:00');
    // Terça 01:00 ainda é a janela de segunda.
    final status = HorarioLojaService.status(
      ecommerce: configCom(horarios),
      agora: DateTime(2026, 11, 10, 1),
    );
    expect(status.aberta, isTrue);
    expect(status.fechaAs, '02:00');
  });

  test('cada dia aceita um horário próprio', () {
    final horarios = HorarioLojaService.padrao()
      ..['sab'] = const HorarioDiaLoja(abre: '09:00', fecha: '13:00');
    final sabadoDeManha = HorarioLojaService.status(
      ecommerce: configCom(horarios),
      agora: DateTime(2026, 11, 14, 12), // sábado
    );
    final sabadoATarde = HorarioLojaService.status(
      ecommerce: configCom(horarios),
      agora: DateTime(2026, 11, 14, 15),
    );
    expect(sabadoDeManha.aberta, isTrue);
    expect(sabadoATarde.aberta, isFalse);
  });

  test('minutosDe aceita hora com e sem zero à esquerda', () {
    expect(HorarioLojaService.minutosDe('8:00'), 480);
    expect(HorarioLojaService.minutosDe('18:30'), 1110);
    expect(HorarioLojaService.minutosDe('25:00'), isNull);
    expect(HorarioLojaService.minutosDe('abc'), isNull);
  });
}
