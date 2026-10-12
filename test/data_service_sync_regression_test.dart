import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_exodo_novo/services/data_service.dart';
import 'package:sistema_exodo_novo/services/supabase_service.dart';

void main() {
  test('vendas_balcao conta como dado novo na sincronização', () {
    final data = {
      'vendas_balcao': [
        {'id': 'venda-1', 'empresa_id': 'empresa-1'},
      ],
    };

    expect(DataService.possuiDadosParaSincronizacao(data), isTrue);
  });

  test('lista vazia não deve ser considerada como dado novo', () {
    final data = {
      'vendas_balcao': <Map<String, dynamic>>[],
      'pedidos': <Map<String, dynamic>>[],
    };

    expect(DataService.possuiDadosParaSincronizacao(data), isFalse);
  });

  group('falhaTotalDoSupabase', () {
    test('servidor indisponível conta como falha total', () {
      expect(
        DataService.falhaTotalDoSupabase({
          'servidorIndisponivel': true,
          'falhas': 1,
          'totalTabelas': 30,
        }),
        isTrue,
      );
    });

    test('todas as tabelas falhando conta como falha total', () {
      expect(
        DataService.falhaTotalDoSupabase({'falhas': 30, 'totalTabelas': 30}),
        isTrue,
      );
    });

    test('algumas falhas isoladas não bloqueiam a sincronização', () {
      expect(
        DataService.falhaTotalDoSupabase({'falhas': 1, 'totalTabelas': 30}),
        isFalse,
      );
    });

    test('carga saudável (zero falhas) não é falha total', () {
      expect(
        DataService.falhaTotalDoSupabase({'falhas': 0, 'totalTabelas': 30}),
        isFalse,
      );
    });
  });

  group('SupabaseService.isErroInfraestrutura', () {
    test('reconhece PGRST002 (schema cache)', () {
      expect(
        SupabaseService.isErroInfraestrutura(
          'PostgrestException(message: Could not query the database for the '
          'schema cache. Retrying., code: PGRST002)',
        ),
        isTrue,
      );
    });

    test('reconhece 503/504 de gateway', () {
      expect(
        SupabaseService.isErroInfraestrutura(
          'PostgrestException(message: upstream request timeout, code: 504, '
          'details: Gateway Timeout)',
        ),
        isTrue,
      );
      expect(
        SupabaseService.isErroInfraestrutura('code: 503, Service Unavailable'),
        isTrue,
      );
    });

    test('não classifica erro de schema/dado como indisponibilidade', () {
      expect(
        SupabaseService.isErroInfraestrutura(
          "PostgrestException(message: column 'foo' does not exist, "
          'code: PGRST204)',
        ),
        isFalse,
      );
    });
  });
}
