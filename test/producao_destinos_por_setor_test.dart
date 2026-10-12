// REGRESSÃO: impressão de produção por SETOR — uma via para cada setor.
//
// Pedido do balcão: no diálogo "Editar Produto", na seção IMPRESSÃO DE
// PRODUÇÃO, marcar os setores (Cozinha, Bar, Doce) "era para sair um em cada
// setor de produção em cada impressora".
//
// Antes o serviço resolvia as impressoras num `Set<String>` — o NOME da
// impressora. Com os 3 setores apontando para a mesma impressora (caso do
// teste com "Microsoft Print to PDF"), o conjunto colapsava em 1 item, então
// saía UMA via só. Além disso o rodapé do ticket mostrava o nome da impressora
// em vez do setor ("SETOR: Microsoft Print to PDF") e o teste de impressão
// seguia a mesma resolução.
//
// Agora a resolução devolve DESTINOS (setor + impressora): sai uma via por
// setor marcado, mesmo que dois setores usem a mesma impressora, e o rodapé diz
// o setor. O agrupamento vive em `agruparPorDestino` (puro) e a resolução em
// `resolverDestinos` (pura) — por isso podem ser verificados aqui, sem banco e
// sem impressora.
//
// Rodar: flutter test test/producao_destinos_por_setor_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_exodo_novo/models/departamento.dart';
import 'package:sistema_exodo_novo/services/producao_pdf_service.dart';

Departamento _dep(
  String id,
  String nome, {
  String? impressora,
  List<String> extras = const [],
}) {
  return Departamento(
    id: id,
    nome: nome,
    impressoraProducao: impressora,
    impressoraProducaoExtra: extras,
  );
}

ItemProducaoInput _item(String id, String nome) =>
    ItemProducaoInput(id: id, nome: nome, quantidade: 1);

void main() {
  group('resolverDestinos', () {
    test('3 setores marcados, TODOS na mesma impressora → 3 vias (uma por setor)', () {
      final deps = [
        _dep('dep_cozinha', 'Cozinha', impressora: 'Microsoft Print to PDF'),
        _dep('dep_bar', 'Bar', impressora: 'Microsoft Print to PDF'),
        _dep('dep_doce', 'Doce', impressora: 'Microsoft Print to PDF'),
      ];

      final destinos = ProducaoPdfService.resolverDestinos(
        departamentos: deps,
        departamentosAdicionais: ['dep_cozinha', 'dep_bar', 'dep_doce'],
      );

      expect(destinos.length, 3,
          reason: 'era para sair um em cada setor, e não uma via só');
      expect(destinos.map((d) => d.setor), ['Cozinha', 'Bar', 'Doce']);
      expect(destinos.map((d) => d.impressora).toSet(),
          {'Microsoft Print to PDF'});
    });

    test('cada setor imprime na impressora do seu departamento', () {
      final deps = [
        _dep('dep_cozinha', 'Cozinha', impressora: 'Impressora Cozinha'),
        _dep('dep_bar', 'Bar', impressora: 'Impressora Bar'),
        _dep('dep_doce', 'Doce', impressora: 'Impressora Doce'),
      ];

      final destinos = ProducaoPdfService.resolverDestinos(
        departamentos: deps,
        departamentoId: 'dep_cozinha',
        departamentosAdicionais: ['dep_bar', 'dep_doce'],
      );

      expect(destinos.length, 3);
      expect(
        {for (final d in destinos) d.setor: d.impressora},
        {
          'Cozinha': 'Impressora Cozinha',
          'Bar': 'Impressora Bar',
          'Doce': 'Impressora Doce',
        },
      );
    });

    test('departamento sem impressora cai na padrão do terminal (não some)', () {
      final deps = [_dep('dep_bar', 'Bar')];

      final destinos = ProducaoPdfService.resolverDestinos(
        departamentos: deps,
        departamentoId: 'dep_bar',
      );

      expect(destinos.length, 1);
      expect(destinos.single.setor, 'Bar');
      expect(destinos.single.impressora, '');
      expect(destinos.single.usaPadrao, isTrue);
      expect(destinos.single.descricao, 'Bar → Padrão do terminal');
    });

    test('setor com impressora principal + extras imprime em todas elas', () {
      final deps = [
        _dep('dep_cozinha', 'Cozinha',
            impressora: 'Cozinha', extras: ['Bar', 'Expedição']),
      ];

      final destinos = ProducaoPdfService.resolverDestinos(
        departamentos: deps,
        departamentoId: 'dep_cozinha',
      );

      expect(destinos.length, 3);
      expect(destinos.map((d) => d.setor).toSet(), {'Cozinha'},
          reason: 'é o mesmo setor, com 3 impressoras');
      expect(destinos.map((d) => d.impressora),
          ['Cozinha', 'Bar', 'Expedição']);
    });

    test('o mesmo setor (principal repetido nos extras) não duplica a via', () {
      final deps = [_dep('dep_cozinha', 'Cozinha', impressora: 'Cozinha')];

      final destinos = ProducaoPdfService.resolverDestinos(
        departamentos: deps,
        departamentoId: 'dep_cozinha',
        departamentosAdicionais: ['dep_cozinha', 'dep_cozinha'],
      );

      expect(destinos.length, 1);
    });

    test('produto sem departamento usa o legado (impressora gravada no produto)', () {
      final destinos = ProducaoPdfService.resolverDestinos(
        departamentos: const [],
        impressoraProducao: 'Microsoft Print to PDF',
        impressorasProducaoExtra: ['Impressora Bar'],
      );

      expect(destinos.map((d) => d.impressora),
          ['Microsoft Print to PDF', 'Impressora Bar']);
    });

    test('produto sem departamento e sem impressora não imprime nada', () {
      final destinos = ProducaoPdfService.resolverDestinos(
        departamentos: const [],
      );
      expect(destinos, isEmpty);
    });

    test('departamento inexistente é ignorado (não inventa destino)', () {
      final destinos = ProducaoPdfService.resolverDestinos(
        departamentos: [_dep('dep_bar', 'Bar', impressora: 'Bar')],
        departamentoId: 'dep_que_nao_existe',
      );
      expect(destinos, isEmpty);
    });

    test('descricaoImpressorasDoDepartamento mostra a impressora de cada setor', () {
      expect(
        ProducaoPdfService.descricaoImpressorasDoDepartamento(
            _dep('x', 'Cozinha', impressora: 'Cozinha')),
        'Cozinha',
      );
      expect(
        ProducaoPdfService.descricaoImpressorasDoDepartamento(_dep('x', 'Bar')),
        'Padrão do terminal',
      );
      expect(
        ProducaoPdfService.descricaoImpressorasDoDepartamento(
            _dep('x', 'Doce', impressora: 'Doce', extras: ['Bar'])),
        'Doce • Bar',
      );
    });
  });

  group('agruparPorDestino', () {
    test('um item que vai para 3 setores entra nos 3 tickets', () {
      final itens = [_item('p1', 'X-Burger')];
      final grupos = ProducaoPdfService.agruparPorDestino(
        itens: itens,
        destinosPorProdutoId: {
          'p1': const [
            DestinoProducao(setor: 'Cozinha', impressora: 'Impressora'),
            DestinoProducao(setor: 'Bar', impressora: 'Impressora'),
            DestinoProducao(setor: 'Doce', impressora: 'Impressora'),
          ],
        },
      );

      expect(grupos.length, 3, reason: 'uma via por setor, mesmo com 1 impressora');
      for (final entry in grupos.entries) {
        expect(entry.value.single.nome, 'X-Burger');
        expect(entry.value.single, same(itens.single));
      }
      expect(grupos.keys.map((d) => d.setor), ['Cozinha', 'Bar', 'Doce']);
    });

    test('item de 2 setores sai 2x; item de 1 setor sai 1x', () {
      final itens = [_item('p1', 'Pizza'), _item('p2', 'Coca')];
      final grupos = ProducaoPdfService.agruparPorDestino(
        itens: itens,
        destinosPorProdutoId: {
          'p1': const [
            DestinoProducao(setor: 'Cozinha', impressora: 'Imp'),
            DestinoProducao(setor: 'Bar', impressora: 'Imp'),
          ],
          'p2': const [DestinoProducao(setor: 'Bar', impressora: 'Imp')],
        },
      );

      expect(grupos[const DestinoProducao(setor: 'Cozinha', impressora: 'Imp')]!
          .map((i) => i.nome), ['Pizza']);
      expect(grupos[const DestinoProducao(setor: 'Bar', impressora: 'Imp')]!
          .map((i) => i.nome), ['Pizza', 'Coca']);
    });

    test('setor forçado igual ao setor do produto não duplica o item no ticket', () {
      final itens = [_item('p1', 'Pizza')];
      final grupos = ProducaoPdfService.agruparPorDestino(
        itens: itens,
        destinosPorProdutoId: {
          'p1': const [DestinoProducao(setor: 'Cozinha', impressora: 'Imp')],
        },
        destinosForcados: const [
          DestinoProducao(setor: 'Cozinha', impressora: 'Imp'),
        ],
      );

      expect(grupos.length, 1);
      expect(grupos.values.single.length, 1);
    });

    test('produto sem setor configurado não gera ticket', () {
      final grupos = ProducaoPdfService.agruparPorDestino(
        itens: [_item('p1', 'Pizza')],
        destinosPorProdutoId: {'p1': const []},
      );
      expect(grupos, isEmpty);
    });

    test('item cujo produto não foi resolvido não gera ticket', () {
      final grupos = ProducaoPdfService.agruparPorDestino(
        itens: [_item('p1', 'Pizza')],
        destinosPorProdutoId: {},
      );
      expect(grupos, isEmpty);
    });
  });
}
