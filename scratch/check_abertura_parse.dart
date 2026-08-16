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
    var resultAb = await conn.execute("SELECT * FROM aberturas_caixa WHERE empresa_id = '22ae2c16-a730-43f3-a4f9-19f105eb0d13'");
    
    for (var row in resultAb) {
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
      
      // try to parse AberturaCaixa
      try {
          String id = convertedMap['id']?.toString() ?? '';
          String numero = convertedMap['numero'] ?? '';
          DateTime data = DateParser.parse(convertedMap['data_abertura'] ?? convertedMap['dataAbertura'] ?? convertedMap['created_at'] ?? convertedMap['createdAt']);
          double valor = parseDouble(convertedMap['valor_inicial'] ?? convertedMap['valorInicial']) ?? 0.0;
          print('OK Abertura \$id - \$numero - \$data - \$valor');
      } catch (e, st) {
          print('FAIL Abertura: \$e\\n\$st');
      }
    }
  } catch (e) {
    print('Error: \$e');
  } finally {
    await conn.close();
  }
}
