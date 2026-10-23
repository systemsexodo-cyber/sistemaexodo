import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_exodo_novo/services/supabase_service.dart';

/// O delta sync descobre o que mudou pelo `updated_at`. Uma escrita PARCIAL
/// (só o estoque, por exemplo) não trazia essa coluna: a linha mudava na nuvem
/// mas continuava com a data antiga e o PC nunca a baixava — "alterei no site e
/// o app local não mudou". Estes testes travam o carimbo em toda escrita.
void main() {
  group('updated_at nas escritas da nuvem', () {
    test('payload parcial ganha uma versão nova', () {
      final payload = <String, dynamic>{'id': 'P1', 'estoque': 3.0};

      SupabaseService.carimbarUpdatedAtParaTeste('produtos', payload);

      expect(payload['updated_at'], isNotNull);
      expect(DateTime.tryParse(payload['updated_at'].toString()), isNotNull);
    });

    test('updated_at que já veio do registro é preservado', () {
      const original = '2026-10-20T10:56:37.719507+00:00';
      final payload = <String, dynamic>{'id': 'P1', 'updated_at': original};

      SupabaseService.carimbarUpdatedAtParaTeste('produtos', payload);

      expect(payload['updated_at'], original);
    });

    test('updated_at nulo/vazio é tratado como ausente', () {
      final payload = <String, dynamic>{'id': 'P1', 'updated_at': '  '};

      SupabaseService.carimbarUpdatedAtParaTeste('produtos', payload);

      expect(payload['updated_at'], isNot('  '));
      expect(DateTime.tryParse(payload['updated_at'].toString()), isNotNull);
    });

    test('tabela sem a coluna não recebe o campo (evita PGRST204)', () {
      final payload = <String, dynamic>{'id': 'I1', 'url': 'x.png'};

      SupabaseService.carimbarUpdatedAtParaTeste('imagens', payload);

      expect(payload.containsKey('updated_at'), isFalse);
    });

    test('colunas reais da nuvem mandam quando foram detectadas', () {
      final payload = <String, dynamic>{'id': 'P1'};

      SupabaseService.carimbarUpdatedAtParaTeste(
        'produtos',
        payload,
        colunasReais: const {'id', 'nome'},
      );

      expect(payload.containsKey('updated_at'), isFalse);
    });
  });
}
