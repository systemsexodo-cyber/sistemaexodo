// A retomada offline é desativada para validar o bloqueio de sessão exclusiva.
//
// Rodar: flutter test test/sessao_offline_boot_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_exodo_novo/services/auth_service.dart';

void main() {
  group('deveRetomarSessaoOffline', () {
    test('sem internet + sessão salva -> exige validação do lease', () {
      expect(
        AuthService.deveRetomarSessaoOffline(
          temSessaoSalva: true,
          temInternet: false,
        ),
        isFalse,
      );
    });

    test('com internet + sessão salva -> exige novo login', () {
      expect(
        AuthService.deveRetomarSessaoOffline(
          temSessaoSalva: true,
          temInternet: true,
        ),
        isFalse,
      );
    });

    test('sem sessão salva -> NÃO retoma (vai ao login)', () {
      expect(
        AuthService.deveRetomarSessaoOffline(
          temSessaoSalva: false,
          temInternet: false,
        ),
        isFalse,
      );
    });

    test('na Web, não interfere na sessão (comportamento próprio)', () {
      expect(
        AuthService.deveRetomarSessaoOffline(
          temSessaoSalva: true,
          temInternet: false,
          isWeb: true,
        ),
        isFalse,
      );
    });
  });
}
