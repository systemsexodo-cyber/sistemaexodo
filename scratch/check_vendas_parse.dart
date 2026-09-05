import 'dart:io';
import 'package:postgres/postgres.dart';
import 'dart:convert';
import 'package:uuid/uuid.dart';

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
    var result = await conn.execute("SELECT * FROM vendas_balcao WHERE empresa_id = '22ae2c16-a730-43f3-a4f9-19f105eb0d13'");
    print('Total Vendas Postgres: ' + result.length.toString());
    
    int failed = 0;
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
          // just checking if produtos list is valid and has 'produto'
          var list = convertedMap['produtos'] as List?;
          if (list != null) {
              for (var item in list) {
                  if (item is Map) {
                      var p = item['produto'];
                      if (p == null) {
                          print('Venda ' + convertedMap['id'].toString() + ' tem produto NULL na lista!');
                      }
                  }
              }
          }
      } catch (e) {
          failed++;
      }
    }
    print('Vendas que falharam: ' + failed.toString());
  } catch (e) {
    print('Error: ' + e.toString());
  } finally {
    await conn.close();
  }
}
