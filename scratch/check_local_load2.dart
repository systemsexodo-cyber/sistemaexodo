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
    var result = await conn.execute("SELECT * FROM nfces WHERE empresa_id = '22ae2c16-a730-43f3-a4f9-19f105eb0d13'");
    print('NFCes: ' + result.length.toString());
    
    var resultAb = await conn.execute("SELECT * FROM aberturas_caixa WHERE empresa_id = '22ae2c16-a730-43f3-a4f9-19f105eb0d13'");
    print('Aberturas: ' + resultAb.length.toString());

  } catch (e) {
    print('Error: ' + e.toString());
  } finally {
    await conn.close();
  }
}
