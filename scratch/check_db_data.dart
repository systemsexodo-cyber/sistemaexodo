import 'dart:io';
import 'package:postgres/postgres.dart';

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
    var result = await conn.execute('SELECT empresa_id, COUNT(*) FROM nfces GROUP BY empresa_id');
    print('NFC-es by empresa_id:');
    for (var row in result) {
      print(row[0].toString() + ' -> ' + row[1].toString());
    }

    result = await conn.execute('SELECT empresa_id, COUNT(*) FROM aberturas_caixa GROUP BY empresa_id');
    print('Aberturas Caixa by empresa_id:');
    for (var row in result) {
      print(row[0].toString() + ' -> ' + row[1].toString());
    }

  } catch (e) {
    print('Error: ' + e.toString());
  } finally {
    await conn.close();
  }
}
