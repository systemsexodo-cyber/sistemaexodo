import 'dart:io';

import 'package:postgres/postgres.dart';

Map<String, String> _lerEnv(String caminho) {
  final mapa = <String, String>{};
  for (var linha in File(caminho).readAsLinesSync()) {
    linha = linha.trim();
    if (linha.isEmpty || linha.startsWith('#')) continue;
    final i = linha.indexOf('=');
    if (i == -1) continue;
    var v = linha.substring(i + 1).trim();
    if (v.length >= 2 && v.startsWith('"') && v.endsWith('"')) {
      v = v.substring(1, v.length - 1);
    }
    mapa[linha.substring(0, i).trim()] = v;
  }
  return mapa;
}

Future<void> main() async {
  final env = _lerEnv('assets/app.env');
  final host = env['DB_CLOUD_HOST'] ?? '';
  final porta = int.tryParse(env['DB_CLOUD_PORT'] ?? '') ?? 5432;
  final banco = env['DB_CLOUD_NAME'] ?? '';
  final usuario = env['DB_CLOUD_USER'] ?? '';
  final senha = env['DB_CLOUD_PASSWORD'] ?? '';
  final ssl = (env['DB_CLOUD_SSL'] ?? 'true').toLowerCase() != 'false';

  print('host=$host porta=$porta banco=$banco usuario=$usuario ssl=$ssl');
  final cronometro = Stopwatch()..start();
  try {
    final conn = await Connection.open(
      Endpoint(
        host: host,
        port: porta,
        database: banco,
        username: usuario,
        password: senha,
      ),
      settings: ConnectionSettings(
        sslMode: ssl ? SslMode.require : SslMode.disable,
        directTls: ssl,
      ),
    ).timeout(const Duration(seconds: 20));
    print('conectado em ${cronometro.elapsedMilliseconds}ms');
    final r = await conn.execute('select count(*) from empresas');
    print('empresas=${r.first.first}');
    await conn.close();
  } catch (e) {
    print('FALHOU em ${cronometro.elapsedMilliseconds}ms: $e');
    exitCode = 1;
  }
}
