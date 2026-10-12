// O login NÃO pode ser bloqueado quando a nuvem (Supabase) está fora ou com a
// cota estourada — nesses casos o acesso vale pelas credenciais do banco LOCAL.
//
// Este teste garante a REGRA que decide isso: o que conta como "nuvem
// indisponível" (libera o login local) e o que NÃO conta (deve negar).
//
// Rodar: flutter test test/login_offline_nuvem_test.dart

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_exodo_novo/services/auth_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  bool indisponivel(Object e) => AuthService.nuvemIndisponivelParaTeste(e);

  group('nuvem indisponível (libera o login local)', () {
    test('timeout de rede', () {
      expect(indisponivel(TimeoutException('x')), isTrue);
    });

    test('sem internet', () {
      expect(
        indisponivel(Exception('SocketException: Failed host lookup')),
        isTrue,
      );
      expect(
        indisponivel(Exception('ClientException: Failed to fetch')),
        isTrue,
      );
    });

    test('cota estourada do Supabase (402) — o caso que travava o login', () {
      final e = PostgrestException(
        message: 'Service for this project is restricted due to the '
            'following violations: exceed_egress_quota.',
        code: '402',
        details: 'Payment Required',
      );
      expect(indisponivel(e), isTrue);
    });

    test('servidor do Supabase fora (503/504/PGRST002)', () {
      expect(indisponivel(Exception('503 Service Unavailable')), isTrue);
      expect(indisponivel(Exception('504 Gateway Timeout')), isTrue);
      expect(
        indisponivel(Exception('PGRST002 schema cache')),
        isTrue,
      );
      expect(
        indisponivel(
          PostgrestException(
            message: 'Could not query the database for the schema cache',
            code: 'PGRST002',
          ),
        ),
        isTrue,
      );
    });
  });

  group('credenciais realmente recusadas (NÃO é indisponibilidade)', () {
    test('senha inválida', () {
      final e = AuthException('Invalid login credentials');
      expect(indisponivel(e), isFalse);
    });

    test('erro qualquer de validação', () {
      expect(indisponivel(Exception('Usuário ou senha inválidos')), isFalse);
    });
  });
}
