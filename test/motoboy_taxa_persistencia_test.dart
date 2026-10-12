// REGRESSÃO: a taxa cadastrada no motoboy tem de ser PERSISTIDA e LIDA de volta.
//
// Defeito real relatado: "a taxa cadastrada no motoboy não está contabilizando".
//
// Causa: a tabela `motoristas` nasceu sem as colunas da comissão
// (`tipo_comissao`, `valor_comissao`, `taxa_padrao`). A gravação do app DESCARTA
// silenciosamente coluna que não existe no schema (`_upsertRows`), então o valor
// digitado na tela do motoboy era jogado fora ao salvar e lido de volta como
// R$ 0,00 — a comissão do entregador nunca entrava na conta.
//
// Aqui ficam travadas as duas pontas:
//   1. o round-trip do modelo (toMap -> fromMap) preserva o valor;
//   2. o BANCO local tem as colunas — o contrato que o modelo exige.
//
// A parte 2 lê o PostgreSQL local (o mesmo caminho do app). Se o banco não
// responder, o teste é PULADO em vez de falhar (o ambiente pode não ter
// PostgreSQL num runner de CI).
//
// Rodar: flutter test test/motoboy_taxa_persistencia_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:postgres/postgres.dart';
import 'package:sistema_exodo_novo/models/motorista.dart';

/// Colunas que o modelo grava e que o banco PRECISA ter.
const colunasDaComissao = <String>[
  'tipo_comissao',
  'valor_comissao',
  'valor_diaria',
  'taxa_padrao',
];

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

void main() {
  test('round-trip do modelo preserva a taxa do motoboy', () {
    final original = Motorista(
      id: 'teste-motoboy-taxa',
      nome: 'Entregador Teste',
      tipoComissao: 'Fixo por Entrega',
      valorComissao: 7.50,
      taxaPadrao: 7.50,
    );

    final lido = Motorista.fromMap(original.toMap());

    expect(lido.tipoComissao, 'Fixo por Entrega');
    expect(lido.valorComissao, 7.50,
        reason: 'A taxa cadastrada não pode virar R\$ 0,00 ao reler.');
    expect(lido.taxaPadrao, 7.50);
  });

  test('round-trip também aceita os nomes snake_case do banco', () {
    // É assim que a linha volta do PostgreSQL local.
    final lido = Motorista.fromMap(<String, dynamic>{
      'id': 'x',
      'nome': 'Entregador',
      'ativo': true,
      'tipo_comissao': 'Porcentagem',
      'valor_comissao': 10,
      'taxa_padrao': 5,
    });

    expect(lido.tipoComissao, 'Porcentagem');
    expect(lido.valorComissao, 10.0);
    expect(lido.taxaPadrao, 5.0);
  });

  test('round-trip preserva a DIÁRIA separada do valor por entrega', () {
    final original = Motorista(
      id: 'teste-motoboy-diaria',
      nome: 'Entregador Diarista',
      tipoComissao: 'Fixo por Entrega',
      valorComissao: 7.50,
      valorDiaria: 50.0,
    );

    final lido = Motorista.fromMap(original.toMap());

    expect(lido.valorDiaria, 50.0,
        reason: 'A diária cadastrada não pode virar R\$ 0,00 ao reler.');
    expect(lido.valorComissao, 7.50);
  });

  test('diária e valor por entrega SOMAM no cálculo da comissão', () {
    // O pedido do balcão: "valor fixo de diário mais valor fixo na entrega
    // para somar e calcular a comissão".
    final m = Motorista(
      id: 'm',
      nome: 'Entregador',
      tipoComissao: 'Fixo por Entrega',
      valorComissao: 7.50,
      valorDiaria: 50.0,
    );

    // 2 dias × R\$ 50,00 de diária (100,00) + 3 entregas × R\$ 7,50 (22,50).
    expect(
      m.calcularComissao(
        entregas: 3,
        somaTaxasEntregas: 30.0,
        diasTrabalhados: 2,
      ),
      122.50,
      reason: 'A comissão tem de SOMAR a diária com o valor por entrega.',
    );
  });

  test('só diária: não paga por entrega, e a diária conta por dia', () {
    final m = Motorista(
      id: 'm',
      nome: 'Entregador',
      tipoComissao: 'Diária',
      valorComissao: 0.0,
      valorDiaria: 60.0,
    );

    expect(m.comissaoPorEntregas(entregas: 5, somaTaxasEntregas: 100), 0.0);
    expect(m.valorDiariaEfetiva, 60.0);
    expect(
      m.calcularComissao(
        entregas: 5,
        somaTaxasEntregas: 100,
        diasTrabalhados: 3,
      ),
      180.0,
    );
  });

  test('cadastro antigo tipo "Diária" guardava o valor em valor_comissao', () {
    // Compatibilidade: antes não existia campo próprio de diária.
    final m = Motorista(
      id: 'm',
      nome: 'Entregador',
      tipoComissao: 'Diária',
      valorComissao: 45.0,
      valorDiaria: 0.0,
    );

    expect(m.valorDiariaEfetiva, 45.0,
        reason: 'Sem isso, a diária de cadastros antigos viraria R\$ 0,00.');
  });

  test('o banco local tem as colunas da comissão do motoboy', () async {
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
        "WHERE table_schema = 'public' AND table_name = 'motoristas'",
      );
      final colunas = res
          .map((row) => row.toColumnMap()['column_name']?.toString() ?? '')
          .toSet();

      expect(colunas, isNotEmpty,
          reason: 'A tabela motoristas precisa existir no banco local.');

      for (final coluna in colunasDaComissao) {
        expect(colunas, contains(coluna),
            reason: 'Sem a coluna "$coluna" a taxa do motoboy é DESCARTADA '
                'na gravação (o app ignora coluna que não existe no schema) e '
                'a comissão nunca contabiliza.');
      }
    } finally {
      await conn.close();
    }
  });

  test('a DIÁRIA grava e volta do banco (round-trip real, com ROLLBACK)', () async {
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

    final id = 'teste-motoboy-diaria-${DateTime.now().microsecondsSinceEpoch}';
    try {
      // Tudo dentro de uma transação que sempre volta atrás: nenhuma linha
      // fica no banco de verdade.
      await conn.execute('BEGIN');
      await conn.execute(
        Sql.named(
          'INSERT INTO motoristas (id, nome, tipo_comissao, valor_comissao, '
          'valor_diaria, taxa_padrao) '
          'VALUES (@id, @nome, @tipo, @valor, @diaria, @taxa)',
        ),
        parameters: {
          'id': id,
          'nome': 'Entregador Teste',
          'tipo': 'Fixo por Entrega',
          'valor': 7.5,
          'diaria': 50.25,
          'taxa': 7.5,
        },
      );

      final res = await conn.execute(
        Sql.named(
          'SELECT valor_diaria, valor_comissao, tipo_comissao FROM motoristas '
          'WHERE id = @id',
        ),
        parameters: {'id': id},
      );

      expect(res, hasLength(1));
      final doBanco = res.first.toColumnMap();

      // O driver devolve NUMERIC como texto; é o app que converte na leitura
      // (coluna NUMERIC → num, em `carregarListaCompleta`). Espelhamos isso
      // aqui para o teste percorrer o MESMO caminho do app.
      Object? comoNumero(Object? v) =>
          v is String ? (num.tryParse(v) ?? v) : v;

      final linha = Motorista.fromMap(<String, dynamic>{
        'id': id,
        'nome': 'Entregador Teste',
        'tipo_comissao': doBanco['tipo_comissao'],
        'valor_comissao': comoNumero(doBanco['valor_comissao']),
        'valor_diaria': comoNumero(doBanco['valor_diaria']),
      });
      expect(linha.valorDiaria, 50.25,
          reason: 'Sem isso a diária é descartada e não contabiliza.');
      expect(linha.valorDiariaEfetiva, 50.25);
    } finally {
      try {
        await conn.execute('ROLLBACK');
      } catch (_) {
        // Transação já encerrada: nada a desfazer.
      }
      final restou = await conn.execute(
        Sql.named('SELECT COUNT(*) AS total FROM motoristas WHERE id = @id'),
        parameters: {'id': id},
      );
      expect(restou.first.toColumnMap()['total'], 0,
          reason: 'O ROLLBACK tem de deixar o banco limpo.');
      await conn.close();
    }
  });
}
