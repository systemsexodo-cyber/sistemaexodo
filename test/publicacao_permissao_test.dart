// Testes da mensagem de erro da publicação quando a nuvem recusa por permissão.
//
// Motivo: o usuário levou "Erro ao enviar o pacote: StorageException(... 403,
// Unauthorized)" na tela de "Atualizar todos os clientes" e o erro não dizia o
// que fazer — a causa era falta de política (RLS) no bucket e em
// bridge_config. Agora a mensagem reconhece esse caso e aponta a migração.

import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_exodo_novo/services/app_update_service.dart';

void main() {
  group('reconhecer recusa por permissão', () {
    test('o erro real do bucket é reconhecido', () {
      expect(
        AppUpdateService.recusaPorPermissao(
          'StorageException(message: new row violates row-level security policy, '
          'statusCode: 403, error: Unauthorized)',
        ),
        isTrue,
      );
    });

    test('outras formas de recusa também', () {
      for (final erro in [
        'PostgrestException(message: new row violates row-level security '
            'policy for table "bridge_config", code: 42501)',
        'StorageException(message: Unauthorized, statusCode: 403)',
        'permission denied for table bridge_config',
      ]) {
        expect(AppUpdateService.recusaPorPermissao(erro), isTrue,
            reason: 'não reconheci: $erro');
      }
    });

    test('erro que não é de permissão fica sem dica', () {
      for (final erro in [
        'SocketException: Failed host lookup',
        'TimeoutException after 0:00:20',
        'FileNotFoundException: C:\\x\\y.zip',
      ]) {
        expect(AppUpdateService.recusaPorPermissao(erro), isFalse);
        expect(AppUpdateService.dicaDePermissao(erro, 'o bucket'), isEmpty);
      }
    });
  });

  group('dica de permissão', () {
    test('diz o recurso e onde liberar', () {
      final dica = AppUpdateService.dicaDePermissao(
        'StorageException(message: new row violates row-level security policy, '
        'statusCode: 403, error: Unauthorized)',
        'o bucket "atualizacoes"',
      );
      expect(dica, contains('o bucket "atualizacoes"'));
      expect(dica, contains('anon'));
      expect(dica, contains('supabase/migrations'));
    });
  });
}
