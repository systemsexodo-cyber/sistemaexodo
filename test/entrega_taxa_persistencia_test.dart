// REGRESSÃO: a taxa da ENTREGA tem de ser PERSISTIDA e LIDA de volta.
//
// Defeito real: a comissão do motoboy (tela de Comissões) é calculada sobre a
// taxa da entrega — `entrega.taxaEntrega`. Só que o modelo gravava a coluna
// `taxaEntrega`, que NÃO existe na tabela local `entregas` (as colunas
// numéricas lá são `valorFrete`/`valor_frete`) e a gravação descarta coluna
// inexistente. Resultado: a taxa nunca saía do app, ficava NULL no banco,
// `Entrega.fromMap` devolvia null e a comissão por entrega saía R$ 0,00 — era
// por isso que marcar/desmarcar "entregue" não mudava a comissão.
//
// Aqui ficam travadas as duas pontas:
//   1. o round-trip do modelo (toMap -> fromMap) preserva a taxa, inclusive
//      quando a linha volta com o nome de coluna do banco;
//   2. o banco local TEM uma coluna que o modelo grava — o contrato que a
//      comissão exige. Se o PostgreSQL não responder, o teste é pulado.
//
// Rodar: flutter test test/entrega_taxa_persistencia_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:postgres/postgres.dart';
import 'package:sistema_exodo_novo/models/entrega.dart';

Map<String, String> _lerEnv() {
  final env = <String, String>{};
  final arquivo = File('.env');
  if (!arquivo.existsSync()) return env;
  for (var linha in arquivo.readAsLinesSync()) {
    linha = linha.trim();
    if (linha.isEmpty || linha.startsWith('#')) continue;
    final idx = linha.indexOf('=');
    if (idx == -1) continue;
    var valor = linha.substring(idx + 1).trim();
    if (valor.length >= 2 &&
        ((valor.startsWith('"') && valor.endsWith('"')) ||
            (valor.startsWith("'") && valor.endsWith("'")))) {
      valor = valor.substring(1, valor.length - 1);
    }
    env[linha.substring(0, idx).trim()] = valor;
  }
  return env;
}

Entrega _entrega({double? taxa}) => Entrega(
      id: 'teste-entrega-taxa',
      pedidoId: 'pedido-1',
      pedidoNumero: 'PED-9999',
      clienteNome: 'Cliente Teste',
      enderecoEntrega: 'Rua Teste, 10',
      status: StatusEntrega.entregue,
      dataCriacao: DateTime(2026, 1, 1, 10),
      dataEntrega: DateTime(2026, 1, 1, 11),
      motoristaId: 'm1',
      motoristaNome: 'volneizão',
      taxaEntrega: taxa,
    );

void main() {
  test('round-trip do modelo preserva a taxa da entrega', () {
    final lido = Entrega.fromMap(_entrega(taxa: 8.0).toMap());

    expect(lido.taxaEntrega, 8.0,
        reason: 'A taxa não pode virar NULL ao reler: é ela que paga a '
            'comissão por entrega.');
  });

  test('leitura aceita a taxa com o nome das colunas do banco', () {
    // É assim que a linha volta do PostgreSQL local (`valorFrete`) e da nuvem
    // (`taxa_entrega`).
    final doBancoLocal = Entrega.fromMap(<String, dynamic>{
      ..._entrega().toMap(),
      'taxaEntrega': null,
      'valorFrete': 12.5,
    });
    expect(doBancoLocal.taxaEntrega, 12.5);

    final daNuvem = Entrega.fromMap(<String, dynamic>{
      ..._entrega().toMap(),
      'taxaEntrega': null,
      'taxa_entrega': '7,25',
    });
    expect(daNuvem.taxaEntrega, 7.25);
  });

  test('a gravação manda a taxa em coluna que existe no banco local', () async {
    final env = _lerEnv();
    Connection? conn;
    try {
      conn = await Connection.open(
        Endpoint(
          host: env['DB_HOST'] ?? '127.0.0.1',
          port: int.tryParse(env['DB_PORT'] ?? '') ?? 5432,
          database: env['DB_NAME'] ?? 'exodo_db',
          username: env['DB_USER'] ?? 'exodo_user',
          password: env['DB_PASSWORD'] ?? '',
        ),
        settings: const ConnectionSettings(
          sslMode: SslMode.disable,
          connectTimeout: Duration(seconds: 5),
        ),
      );
    } catch (e) {
      markTestSkipped('PostgreSQL local indisponível: $e');
      return;
    }

    try {
      final res = await conn.execute(
        "SELECT column_name FROM information_schema.columns "
        "WHERE table_schema = 'public' AND table_name = 'entregas'",
      );
      final colunas = res
          .map((row) => row.toColumnMap()['column_name']?.toString() ?? '')
          .toSet();
      expect(colunas, isNotEmpty,
          reason: 'A tabela entregas precisa existir no banco local.');

      final chavesDaGravacao = _entrega(taxa: 8.0).toMap().keys.toSet();
      final taxasQueChegam = {
        'taxaEntrega',
        'valorFrete',
        'valor_frete',
        'taxa_entrega',
      }.intersection(chavesDaGravacao).intersection(colunas);

      expect(taxasQueChegam, isNotEmpty,
          reason: 'Nenhuma das chaves de taxa que o modelo grava existe na '
              'tabela entregas — a taxa é DESCARTADA na gravação e a comissão '
              'por entrega nunca contabiliza.');

      // Round-trip real, sempre dentro de um ROLLBACK: nenhuma linha fica.
      final id = 'teste-entrega-taxa-${DateTime.now().microsecondsSinceEpoch}';
      await conn.execute('BEGIN');
      await conn.execute(
        Sql.named(
          'INSERT INTO entregas (id, "pedidoId", "pedidoNumero", status, '
          'motorista_id, motorista_nome, "valorFrete") '
          'VALUES (@id, @pedido, @numero, @status, @mid, @mnome, @taxa)',
        ),
        parameters: {
          'id': id,
          'pedido': 'pedido-teste',
          'numero': 'PED-9999',
          'status': 'entregue',
          'mid': 'm1',
          'mnome': 'volneizão',
          'taxa': 8.0,
        },
      );

      final linha = await conn.execute(
        Sql.named(
          'SELECT * FROM entregas WHERE id = @id',
        ),
        parameters: {'id': id},
      );
      expect(linha, hasLength(1));

      final mapa = Map<String, dynamic>.from(linha.first.toColumnMap());
      Object? comoNumero(Object? v) =>
          v is String ? (num.tryParse(v) ?? v) : v;
      mapa['valorFrete'] = comoNumero(mapa['valorFrete']);

      final doBanco = Entrega.fromMap(mapa);
      expect(doBanco.taxaEntrega, 8.0,
          reason: 'A taxa da entrega tem de voltar do banco — é ela que a '
              'tela de Comissões usa para pagar o motoboy.');
    } finally {
      try {
        await conn.execute('ROLLBACK');
      } catch (_) {
        // Transação já encerrada.
      }
      await conn.close();
    }
  });
}
