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
}
