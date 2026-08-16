import 'package:postgres/postgres.dart';

Future<void> main() async {
  final conn = await Connection.open(
    Endpoint(
      host: '127.0.0.1',
      port: 5432,
      database: 'exodo_db',
      username: 'exodo_user',
      password: 'senha123',
    ),
    settings: const ConnectionSettings(sslMode: SslMode.disable),
  );

  print('connected');
  final res = await conn.execute('SELECT current_database(), current_user');
  print(res.first.toColumnMap());

  try {
    await conn.runTx((session) async {
      await session.execute("SET LOCAL exodo.sync_mode = 'off';");
      print('set ok');
    });
  } catch (e, st) {
    print('SET LOCAL ERR: $e');
    print(st);
  }

  try {
    final cols = await conn.execute("SELECT table_name, column_name, data_type FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'produtos' LIMIT 3");
    print(cols);
  } catch (e, st) {
    print('COLS ERR: $e');
    print(st);
  }

  await conn.close();
}
