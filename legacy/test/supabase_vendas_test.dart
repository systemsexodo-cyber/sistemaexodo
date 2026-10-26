import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_exodo_novo/services/supabase_service.dart';
import 'package:sistema_exodo_novo/models/venda_balcao.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sistema_exodo_novo/supabase_config.dart';

void main() {
  test('test loading and parsing of all sales from Supabase', () async {
    final url = SupabaseConfig.url;
    final anonKey = SupabaseConfig.anonKey;

    print('>>> Initializing Supabase...');
    await Supabase.initialize(
      url: url,
      anonKey: anonKey,
      authOptions: const FlutterAuthClientOptions(
        localStorage: EmptyLocalStorage(),
      ),
    );

    final client = Supabase.instance.client;
    print('>>> Fetching sales from Supabase...');
    final response = await client
        .from('vendas_balcao')
        .select()
        .eq('empresa_id', '22ae2c16-a730-43f3-a4f9-19f105eb0d13')
        .limit(200);

    print('>>> Loaded Supabase records count: ${response.length}');

    int parsedCount = 0;
    int failedCount = 0;

    for (final map in response) {
      try {
        final venda = VendaBalcao.fromMap(map as Map<String, dynamic>);
        parsedCount++;
      } catch (e, st) {
        failedCount++;
        print('>>> ❌ FAILED TO PARSE SUPABASE SALE ID: ${map['id']}');
        print('Error: $e');
        print('Stack trace: $st');
        print('Map content: $map');
        print('-----------------------------------------');
      }
    }

    print('>>> Total parsed successfully: $parsedCount');
    print('>>> Total failed to parse: $failedCount');

    expect(failedCount, equals(0));
  });
}
