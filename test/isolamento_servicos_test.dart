// Teste do ISOLAMENTO dos SERVIÇOS por empresa.
//
// O defeito: o `Servico` não carregava de QUEM ele era (não tinha o
// `empresa_id`), ao contrário do `Produto`. O banco local carimba toda gravação
// com a empresa ABERTA no app, então um serviço que entrasse na memória vindo
// de outra empresa (troca de empresa, cache antigo, snapshot) era adotado pela
// empresa aberta e, ao ser gravado, TROCAVA DE DONO — era assim que "os
// serviços apareciam em todas as empresas".
//
// Aqui ficam travadas as garantias:
//   1. o serviço leva o próprio `empresa_id` no mapa (`toMap`);
//   2. `fromMap` lê o carimbo (snake e camel);
//   3. no banco REAL, gravar o serviço de OUTRA empresa é RECUSADO e a linha
//      original fica intacta (não muda de dono).
//
// Rodar: flutter test test/isolamento_servicos_test.dart
// Nada é enviado para a nuvem: as escritas usam isSync: true e o registro de
// teste é apagado no fim.

import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_exodo_novo/models/servico.dart';
import 'package:sistema_exodo_novo/services/database_service.dart';
import 'package:sistema_exodo_novo/services/local_storage_service.dart';

Servico servico({
  required String id,
  String? empresaId,
  String nome = 'SERVIÇO DE TESTE',
  double preco = 10,
}) {
  final agora = DateTime(2026, 10, 16, 12);
  return Servico(
    id: id,
    empresaId: empresaId,
    nome: nome,
    preco: preco,
    createdAt: agora,
    updatedAt: agora,
  );
}

Object? campo(Map<String, dynamic> linha, String camel, String snake) =>
    linha[camel] ?? linha[snake];

void main() {
  group('o serviço carrega de quem ele é', () {
    test('toMap leva o empresa_id (mesmo nulo, a chave vai sempre)', () {
      final meu = servico(id: 'S1', empresaId: 'EMPRESA-A');
      expect(meu.toMap()['empresa_id'], 'EMPRESA-A');

      final novo = servico(id: 'S2');
      expect(novo.toMap().containsKey('empresa_id'), isTrue);
      expect(novo.toMap()['empresa_id'], isNull);
    });

    test('fromMap lê o empresa_id do banco (snake e camel)', () {
      expect(
          Servico.fromMap(servico(id: 'S1', empresaId: 'EMPRESA-A').toMap())
              .empresaId,
          'EMPRESA-A');
      expect(
          Servico.fromMap({
            'id': 'S1',
            'nome': 'X',
            'preco': 1,
            'empresaId': 'EMPRESA-B',
          }).empresaId,
          'EMPRESA-B');
    });

    test('copyWith preserva a empresa', () {
      final meu = servico(id: 'S1', empresaId: 'EMPRESA-A');
      expect(meu.copyWith(preco: 99).empresaId, 'EMPRESA-A');
      expect(meu.copyWith(preco: 99).id, 'S1');
    });
  });

  group('no banco REAL: serviço de outra empresa não troca de dono', () {
    final db = DatabaseService();
    const empresaA = 'EMPRESA-A-ISOLAMENTO-SERVICO';
    const empresaB = 'EMPRESA-B-ISOLAMENTO-SERVICO';
    const idServico = 'ISOLAMENTO-SERVICO-1';

    tearDown(() async {
      await db.removerItemPostgres(
          LocalStorageService.keyServicos, idServico, empresaA,
          isSync: true);
      await db.removerItemPostgres(
          LocalStorageService.keyServicos, idServico, empresaB,
          isSync: true);
      db.setEmpresaId('');
    });

    test('gravar o serviço da B com a empresa A aberta é recusado', () async {
      // 1. O serviço nasce na empresa B (é o dono dele).
      final original = servico(id: idServico, empresaId: empresaB, preco: 10);
      db.setEmpresaId(empresaB);
      await db.salvarLista(LocalStorageService.keyServicos,
          [original.toMap()], isSync: true);

      final naB = await db.carregarLista(LocalStorageService.keyServicos);
      final linhaB = naB.firstWhere((s) => s['id'] == idServico,
          orElse: () => <String, dynamic>{});
      expect(campo(linhaB, 'empresaId', 'empresa_id'), empresaB,
          reason: 'o serviço precisa nascer carimbado com a empresa dona');

      // 2. Com a empresa A aberta, o MESMO serviço (mesmo id) é regravado.
      //    Antes: era adotado pela A (a linha mudava de dono).
      db.setEmpresaId(empresaA);
      final bloqueiosAntes = db.gravacoesBloqueadasPorEmpresa;
      final alterado = original.copyWith(preco: 99);
      await db.salvarLista(LocalStorageService.keyServicos,
          [alterado.toMap()], isSync: true);

      expect(db.gravacoesBloqueadasPorEmpresa, greaterThan(bloqueiosAntes),
          reason: 'a trava do banco precisa ter recusado a gravação cruzada');

      // A linha da B continua intacta (preço e dono).
      db.setEmpresaId(empresaB);
      final depois = await db.carregarLista(LocalStorageService.keyServicos);
      final linhaDepois = depois.firstWhere((s) => s['id'] == idServico,
          orElse: () => <String, dynamic>{});
      expect(campo(linhaDepois, 'preco', 'preco'), 10,
          reason: 'o preço do serviço da B não pode ser mexido pela A');
      expect(campo(linhaDepois, 'empresaId', 'empresa_id'), empresaB,
          reason: 'o serviço não pode trocar de dono');
    });
  });
}
