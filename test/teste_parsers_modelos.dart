import 'dart:io';
import 'package:postgres/postgres.dart';
import 'package:sistema_exodo_novo/models/produto.dart';
import 'package:sistema_exodo_novo/models/cliente.dart';
import 'package:sistema_exodo_novo/models/caixa.dart';
import 'package:sistema_exodo_novo/models/mesa_comanda.dart';

void main() async {
  print("=== TESTE DE PARSERS DE MODELOS DART COM POSTGRES ===");
  
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

    print("Conectado com sucesso!");

    // 1. Testar Produtos
    print("\n--- Testando PRODUTOS ---");
    try {
      final res = await conn.execute("SELECT * FROM produtos LIMIT 10");
      print("Query retornou ${res.length} produtos.");
      int count = 0;
      for (final row in res) {
        final map = row.toColumnMap();
        try {
          final p = Produto.fromMap(map);
          count++;
        } catch (err, st) {
          print("Erro ao converter Produto (ID: ${map['id']}): $err");
          print(st);
        }
      }
      print("Produtos convertidos com sucesso: $count/${res.length}");
    } catch (e) {
      print("Erro na query de produtos: $e");
    }

    // 2. Testar Clientes
    print("\n--- Testando CLIENTES ---");
    try {
      final res = await conn.execute("SELECT * FROM clientes LIMIT 10");
      print("Query retornou ${res.length} clientes.");
      int count = 0;
      for (final row in res) {
        final map = row.toColumnMap();
        try {
          final c = Cliente.fromMap(map);
          count++;
        } catch (err, st) {
          print("Erro ao converter Cliente (ID: ${map['id']}): $err");
          print(st);
        }
      }
      print("Clientes convertidos com sucesso: $count/${res.length}");
    } catch (e) {
      print("Erro na query de clientes: $e");
    }

    // 3. Testar Mesas/Comandas
    print("\n--- Testando MESAS/COMANDAS ---");
    try {
      final res = await conn.execute("SELECT * FROM mesas_comandas LIMIT 10");
      print("Query retornou ${res.length} mesas_comandas.");
      int count = 0;
      for (final row in res) {
        final map = row.toColumnMap();
        try {
          final m = MesaComanda.fromMap(map);
          count++;
        } catch (err, st) {
          print("Erro ao converter MesaComanda (ID: ${map['id']}): $err");
          print(st);
        }
      }
      print("Mesas/Comandas convertidas com sucesso: $count/${res.length}");
    } catch (e) {
      print("Erro na query de mesas_comandas: $e");
    }

    // 4. Testar Aberturas de Caixa
    print("\n--- Testando ABERTURAS DE CAIXA ---");
    try {
      final res = await conn.execute("SELECT * FROM aberturas_caixa LIMIT 10");
      print("Query retornou ${res.length} aberturas_caixa.");
      int count = 0;
      for (final row in res) {
        final map = row.toColumnMap();
        try {
          final a = AberturaCaixa.fromMap(map);
          count++;
        } catch (err, st) {
          print("Erro ao converter AberturaCaixa (ID: ${map['id']}): $err");
          print(st);
        }
      }
      print("Aberturas convertidas com sucesso: $count/${res.length}");
    } catch (e) {
      print("Erro na query de aberturas_caixa: $e");
    }

    await conn.close();
  } catch (e) {
    print("Erro de conexão: $e");
  }
  
  exit(0);
}
