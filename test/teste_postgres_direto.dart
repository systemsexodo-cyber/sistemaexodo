import 'dart:io';
import 'package:postgres/postgres.dart';

void main() async {
  print("Conectando ao PostgreSQL diretamente no Dart...");
  
  // Ler arquivo .env manualmente
  final env = <String, String>{};
  try {
    final file = File('.env');
    if (file.existsSync()) {
      for (var line in file.readAsLinesSync()) {
        line = line.trim();
        if (line.isEmpty || line.startsWith('#')) continue;
        final idx = line.indexOf('=');
        if (idx == -1) continue;
        final key = line.substring(0, idx).trim();
        var val = line.substring(idx + 1).trim();
        if (val.startsWith('"') && val.endsWith('"')) val = val.substring(1, val.length - 1);
        if (val.startsWith("'") && val.endsWith("'")) val = val.substring(1, val.length - 1);
        env[key] = val;
      }
    }
  } catch (e) {
    print("Erro ao ler .env: $e");
  }

  final host = env['DB_HOST'] ?? '127.0.0.1';
  final port = int.tryParse(env['DB_PORT'] ?? '') ?? 5432;
  final dbName = env['DB_NAME'] ?? 'exodo_db';
  final dbUser = env['DB_USER'] ?? 'exodo_user';
  final dbPass = env['DB_PASSWORD'] ?? 'senha123';

  print("Config: Host=$host, Port=$port, DB=$dbName, User=$dbUser");

  try {
    final conn = await Connection.open(
      Endpoint(
        host: host == 'localhost' ? '127.0.0.1' : host,
        port: port,
        database: dbName,
        username: dbUser,
        password: dbPass,
      ),
      settings: const ConnectionSettings(sslMode: SslMode.disable),
    );

    print("Conectado!");
    
    final result = await conn.execute(
      Sql.named("SELECT id, nome, preco, preco_custo, estoque, estoque_minimo FROM produtos WHERE empresa_id = @empresaId LIMIT 5"),
      parameters: {'empresaId': '22ae2c16-a730-43f3-a4f9-19f105eb0d13'}
    );

    print("Colunas retornadas pelo execute:");
    for (final row in result) {
      final map = row.toColumnMap();
      print("Produto: ${map['nome']}");
      print("  id: ${map['id']} (${map['id'].runtimeType})");
      print("  preco: ${map['preco']} (${map['preco'].runtimeType})");
      print("  preco_custo: ${map['preco_custo']} (${map['preco_custo'].runtimeType})");
      print("  estoque: ${map['estoque']} (${map['estoque'].runtimeType})");
      print("  estoque_minimo: ${map['estoque_minimo']} (${map['estoque_minimo'].runtimeType})");
    }

    await conn.close();
  } catch (e, st) {
    print("Erro no teste: $e");
    print(st);
  }
}
