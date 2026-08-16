import 'dart:io';
import 'package:postgres/postgres.dart';
import 'dart:convert';
import 'package:uuid/uuid.dart';

class DateParser {
  static DateTime parse(dynamic value) {
    if (value == null) return DateTime.now();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value) ?? DateTime.now();
    return DateTime.now();
  }
}
double? parseDouble(dynamic value) {
  if (value == null) return null;
  if (value is double) return value;
  if (value is int) return value.toDouble();
  if (value is String) return double.tryParse(value.replaceAll(',', '.'));
  return null;
}

void main() async {
  final conn = await Connection.open(
    Endpoint(
      host: 'localhost',
      port: 5432,
      database: 'exodo_db',
      username: 'postgres',
      password: 'postgrespassword',
    ),
    settings: const ConnectionSettings(sslMode: SslMode.disable),
  );

  try {
    for (String tabela in ['sangrias_caixa', 'suprimentos_caixa', 'fechamentos_caixa', 'vendas_balcao']) {
        var result = await conn.execute("SELECT * FROM \$tabela WHERE empresa_id = '22ae2c16-a730-43f3-a4f9-19f105eb0d13'");
        int cont = 0;
        for (var row in result) {
            final map = row.toColumnMap();
            final convertedMap = <String, dynamic>{};
            for (final entry in map.entries) {
                    var k = entry.key;
                    if (k.contains('_')) {
                    final parts = k.split('_');
                    k = parts[0] + parts.skip(1).map((p) => p.isEmpty ? '' : p[0].toUpperCase() + p.substring(1)).join();
                    }
                    var val = entry.value;
                    if (val is String && (val.startsWith('[') || val.startsWith('{'))) {
                    try { val = jsonDecode(val); } catch (_) {}
                    }
                    convertedMap[k] = val;
            }
            
            try {
                String id = convertedMap['id']?.toString() ?? '';
                // Just touching basic fields that might crash
                if (tabela == 'sangrias_caixa') {
                    String ab = convertedMap['abertura_caixa_id']?.toString() ?? convertedMap['aberturaCaixaId']?.toString() ?? '';
                }
                cont++;
            } catch (e, st) {
                print('FAIL \$tabela: \$e\\n\$st');
            }
        }
        print('\$tabela OK: \$cont/\${result.length}');
    }
  } catch (e) {
    print('Error: \$e');
  } finally {
    await conn.close();
  }
}
