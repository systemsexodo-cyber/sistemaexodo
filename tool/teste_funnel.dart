// Teste rapido do caminho da NUVEM (Tailscale Funnel) usando o driver
// `postgres` local com a opcao `directTls`.
//
// Rode na raiz do projeto:
//   dart run tool/teste_funnel.dart
//
// Le as credenciais de `assets/app.env` (bloco DB_CLOUD_*). Nao imprime a
// senha. Serve para confirmar que o celular vai conseguir conectar fora da
// loja antes de gerar o APK.
import 'dart:io';

import 'package:postgres/postgres.dart';

Future<void> main() async {
  final env = <String, String>{};
  for (final linha in File('assets/app.env').readAsLinesSync()) {
    final l = linha.trim();
    if (l.isEmpty || l.startsWith('#')) continue;
    final i = l.indexOf('=');
    if (i <= 0) continue;
    var v = l.substring(i + 1).trim();
    if (v.length >= 2 && v.startsWith('"') && v.endsWith('"')) {
      v = v.substring(1, v.length - 1);
    }
    env[l.substring(0, i).trim()] = v;
  }

  final host = env['DB_CLOUD_HOST'] ?? '';
  final porta = int.tryParse(env['DB_CLOUD_PORT'] ?? '') ?? 5434;
  final banco = env['DB_CLOUD_NAME'] ?? 'postgres';
  final usuario = env['DB_CLOUD_USER'] ?? '';
  final senha = env['DB_CLOUD_PASSWORD'] ?? '';

  if (host.isEmpty || usuario.isEmpty || senha.isEmpty) {
    stderr.writeln('DB_CLOUD_* incompleto em assets/app.env');
    exit(2);
  }

  stdout.writeln('Conectando em $host:$porta como "$usuario" (TLS direto)...');
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
      settings: const ConnectionSettings(
        sslMode: SslMode.require,
        directTls: true,
      ),
    ).timeout(const Duration(seconds: 25));
    cronometro.stop();

    final r = await conn.execute('select count(*) from produtos');
    final clientes = await conn.execute('select count(*) from clientes');
    await conn.close();
    stdout.writeln(
      'OK em ${cronometro.elapsedMilliseconds} ms | '
      'produtos=${r.first[0]} clientes=${clientes.first[0]}',
    );
    exit(0);
  } catch (e) {
    cronometro.stop();
    stderr.writeln('FALHOU depois de ${cronometro.elapsedMilliseconds} ms: $e');
    exit(1);
  }
}
