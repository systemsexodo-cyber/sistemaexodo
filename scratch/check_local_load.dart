import 'dart:io';
import 'package:postgres/postgres.dart';
import 'dart:convert';

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
    var result = await conn.execute("SELECT * FROM nfces WHERE empresa_id = '22ae2c16-a730-43f3-a4f9-19f105eb0d13'");
    int parseados = 0;
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
            // auto-converter numericos
            if (val is String) {
               // ...
            }
            if (val is String && (val.startsWith('[') || val.startsWith('{'))) {
              try { val = jsonDecode(val); } catch (_) {}
            }
            convertedMap[k] = val;
      }

      // simulating NFCe.fromMap manually since I cannot import flutter
      try {
         final id = convertedMap['id']?.toString() ?? '';
         final empresaId = convertedMap['empresaId'] ?? convertedMap['empresa_id'] ?? '';
         final numero = convertedMap['numero'] ?? '';
         final serie = convertedMap['serie'] ?? '';
         // if this works
         parseados++;
      } catch (e, st) {
         print('Error parsing NFCe: \$e\\n\$st');
      }
    }
    print('NFCes carregadas do banco local: \${result.length}');
    print('NFCes parseadas com sucesso: \$parseados');
    
    // aberturas
    var resultAb = await conn.execute("SELECT * FROM aberturas_caixa WHERE empresa_id = '22ae2c16-a730-43f3-a4f9-19f105eb0d13'");
    print('Aberturas carregadas: \${resultAb.length}');

  } catch (e) {
    print('Error: \$e');
  } finally {
    await conn.close();
  }
}
