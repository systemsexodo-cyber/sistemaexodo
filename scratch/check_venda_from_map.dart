import 'dart:io';
import 'package:postgres/postgres.dart';
import 'dart:convert';
import 'package:sistema_exodo_novo/models/venda_balcao.dart';
import 'package:sistema_exodo_novo/utils/date_parser.dart';

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
    var result = await conn.execute("SELECT * FROM vendas_balcao");
    print('Total Vendas locally: ${result.length}');
    
    for (var row in result) {
      final map = row.toColumnMap();
      try {
        final venda = VendaBalcao.fromMap(map);
        // Print one successful parse
      } catch (e, st) {
        print('Parsing failed for row: ${map['id']}');
        print(e);
        print(st);
      }
    }
  } catch (e) {
    print('Database error: $e');
  } finally {
    await conn.close();
  }
}
