// Conflito entre dois bancos locais (duas máquinas, uma sem internet).
//
// Quando a MESMA linha é alterada nas duas pontas, o sincronizador guarda as
// duas versões em `exodo_sync_conflitos` e para de mexer na linha até o usuário
// decidir. Estes testes travam o que a tela de conflitos mostra para decidir:
// quais campos realmente divergem (carimbo de data não conta) e o que identifica
// o registro.
//
// Rodar: flutter test test/conflito_sync_test.dart

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_exodo_novo/models/conflito_sync.dart';

void main() {
  test('lê o conflito quando o jsonb vem como mapa (driver postgres)', () {
    final conflito = ConflitoSync.fromMap({
      'id': 'c1',
      'tabela': 'produtos',
      'registro_id': 'P1',
      'dados_locais': <String, dynamic>{'id': 'P1', 'nome': 'coca cola', 'estoque': 33},
      'dados_nuvem': <String, dynamic>{'id': 'P1', 'nome': 'coca cola', 'estoque': 30},
      'criado_em': '2026-09-28T12:00:00Z',
    });

    expect(conflito.tabela, 'produtos');
    expect(conflito.registroId, 'P1');
    expect(conflito.rotuloTabela, 'Produto');
    expect(conflito.nomeDoRegistro, 'coca cola');
    expect(conflito.dadosLocais['estoque'], 33);
    expect(conflito.criadoEm, isNotNull);
  });

  test('lê o conflito quando o jsonb vem serializado como texto', () {
    final conflito = ConflitoSync.fromMap({
      'id': 'c2',
      'tabela': 'clientes',
      'registro_id': 'C9',
      'dados_locais': jsonEncode({'id': 'C9', 'nome': 'Maria', 'telefone': '11 9'},
      ),
      'dados_nuvem': jsonEncode({'id': 'C9', 'nome': 'Maria', 'telefone': '11 8'}),
    });

    expect(conflito.dadosLocais['nome'], 'Maria');
    expect(conflito.dadosNuvem['telefone'], '11 8');
    expect(conflito.camposDivergentes, ['telefone']);
  });

  test('campos divergentes ignoram carimbos de sincronização', () {
    final divergentes = ConflitoSync.diferencas(
      {
        'id': 'P1',
        'nome': 'coca cola',
        'preco': 24.0,
        'updated_at': '2026-09-28T10:00:00Z',
        'criado_em': '2026-09-01T10:00:00Z',
        '_sincronizado_nuvem': false,
      },
      {
        'id': 'P1',
        'nome': 'coca cola',
        'preco': 24.0,
        'updated_at': '2026-09-29T10:00:00Z',
        'criado_em': '2026-09-01T10:00:00Z',
        '_sincronizado_nuvem': true,
      },
    );

    expect(divergentes, isEmpty,
        reason: 'só a data mudou: não é conflito de dado, é carimbo');
  });

  test('campos divergentes pegam o que mudou de verdade (e só isso)', () {
    final divergentes = ConflitoSync.diferencas(
      {'id': 'P1', 'nome': 'coca cola', 'estoque': 33, 'preco': 24.0, 'grupo': 'Bebida'},
      {'id': 'P1', 'nome': 'coca cola', 'estoque': 30, 'preco': 24.0, 'grupo': 'Bebida'},
    );

    expect(divergentes, ['estoque']);
  });

  test('número salvo como texto e como numérico não vira conflito', () {
    // Mesma informação, tipos diferentes (a nuvem devolve 24.0, o banco local
    // pode devolver "24") — não é uma disputa, é o mesmo valor.
    expect(ConflitoSync.diferencas({'estoque': 24.0}, {'estoque': 24}), isEmpty);
    expect(ConflitoSync.diferencas({'estoque': 24.0}, {'estoque': '24.0'}), isEmpty);
    expect(ConflitoSync.diferencas({'estoque': 24}, {'estoque': 25}), ['estoque']);
  });

  test('campos aninhados iguais em ordem diferente não viram conflito', () {
    final divergentes = ConflitoSync.diferencas(
      {
        'configuracoes': {'b': 2, 'a': 1},
      },
      {
        'configuracoes': jsonEncode({'a': 1, 'b': 2}),
      },
    );
    // O lado da nuvem chega como texto JSON: os valores são os mesmos, então o
    // usuário não deve ser incomodado com isso.
    expect(divergentes, isEmpty);
  });

  test('sem nome conhecido, o registro é identificado pelo id', () {
    final conflito = ConflitoSync.fromMap({
      'id': 'c3',
      'tabela': 'sangrias',
      'registro_id': 'S-77',
      'dados_locais': {'id': 'S-77', 'valor': 100},
      'dados_nuvem': {'id': 'S-77', 'valor': 120},
    });

    expect(conflito.nomeDoRegistro, 'S-77');
    expect(conflito.rotuloTabela, 'sangrias');
    expect(conflito.camposDivergentes, ['valor']);
  });
}
