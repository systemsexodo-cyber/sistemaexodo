import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_exodo_novo/services/app_update_service.dart';

void main() {
  test('forced cloud version downgrades an installation', () {
    expect(AppUpdateService.deveAtualizar('1.0.56', '!1.0.52'), isTrue);
  });

  test('forced cloud version is not reapplied when already installed', () {
    expect(AppUpdateService.deveAtualizar('1.0.52', '!1.0.52'), isFalse);
  });

  test('normal cloud updates only install a newer version', () {
    expect(AppUpdateService.deveAtualizar('1.0.52', '1.0.56'), isTrue);
    expect(AppUpdateService.deveAtualizar('1.0.56', '1.0.52'), isFalse);
  });

  group('forcada vencida (trava do "abre e fica atualizando")', () {
    final instalada = DateTime.utc(2026, 11, 9, 23, 45);

    test('downgrade forcado publicado antes da instalacao e ignorado', () {
      expect(
        AppUpdateService.downgradeForcadoVencido(
          forcada: true,
          versaoRemota: '!1.0.62',
          publicadaEm: DateTime.utc(2026, 11, 7, 12, 9),
          instaladaEm: instalada,
          versaoInstalada: '1.0.69',
        ),
        isTrue,
      );
    });

    test('downgrade forcado publicado depois da instalacao continua valendo', () {
      expect(
        AppUpdateService.downgradeForcadoVencido(
          forcada: true,
          versaoRemota: '!1.0.62',
          publicadaEm: DateTime.utc(2026, 11, 10),
          instaladaEm: instalada,
          versaoInstalada: '1.0.69',
        ),
        isFalse,
      );
    });

    test('subir de versao nunca e tratado como vencido', () {
      expect(
        AppUpdateService.downgradeForcadoVencido(
          forcada: true,
          versaoRemota: '!1.0.70',
          publicadaEm: DateTime.utc(2026, 11, 1),
          instaladaEm: instalada,
          versaoInstalada: '1.0.69',
        ),
        isFalse,
      );
    });

    test('publicacao normal nao usa a regra da forcada', () {
      expect(
        AppUpdateService.downgradeForcadoVencido(
          forcada: false,
          versaoRemota: '1.0.62',
          publicadaEm: DateTime.utc(2026, 11, 7),
          instaladaEm: instalada,
          versaoInstalada: '1.0.69',
        ),
        isFalse,
      );
    });
  });
}
