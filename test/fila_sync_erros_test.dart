// FILA DE SINCRONIZAÇÃO — classificação de erros.
//
// A antiga lista de erros "irrecuperáveis" era tão ampla que incluía
// 'column', 'constraint', 'foreign key', 'not find' e 'is not a subtype'. Isso
// DESCARTava operações que só precisavam de mais tempo (ex.: um fechamento que
// depende da abertura ainda não sincronizada) — o dado ficava só no local para
// sempre. Agora só erros reais de ESQUEMA/PERMISSÃO descartam; o resto é
// reagendado com backoff.
//
// Rodar: flutter test test/fila_sync_erros_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_exodo_novo/services/sync_queue_service.dart';

void main() {
  group('erroIrrecuperavel — permanente (descartar)', () {
    test('coluna inexistente no schema cache (PGRST204)', () {
      expect(
        SyncQueueService.erroIrrecuperavel(
            'PGRST204: Could not find the \'x\' column of \'t\' in the schema cache'),
        isTrue,
      );
    });

    test('tabela inexistente (PGRST205)', () {
      expect(
        SyncQueueService.erroIrrecuperavel(
            'PGRST205: Could not find the table \'public.y\' in the schema cache'),
        isTrue,
      );
    });

    test('undefined_column do Postgres (42703)', () {
      expect(
        SyncQueueService.erroIrrecuperavel(
            'Severity.unknown 42703: não existe a coluna "data_agendamento"'),
        isTrue,
      );
    });

    test('RLS / permissão (42501)', () {
      expect(
        SyncQueueService.erroIrrecuperavel(
            'new row violates row-level security policy for table vendas'),
        isTrue,
      );
    });
  });

  group('erroIrrecuperavel — temporário (reagendar, NÃO descartar)', () {
    test('violação de chave estrangeira (pode depender de outro registro)', () {
      expect(
        SyncQueueService.erroIrrecuperavel(
            'insert or update on table "fechamentos_caixa" violates foreign key constraint'),
        isFalse,
      );
    });

    test('erro de tipo no payload', () {
      expect(
        SyncQueueService.erroIrrecuperavel(
            "type 'Null' is not a subtype of type 'List<dynamic>?'"),
        isFalse,
      );
    });

    test('registro ainda não encontrado', () {
      expect(
        SyncQueueService.erroIrrecuperavel(
            'record not found: no rows returned for id 123'),
        isFalse,
      );
    });
  });

  test('fila pausada preserva pendências e retoma ao reativar', () async {
    final queue = SyncQueueService(persistQueue: false);
    var executou = false;

    queue.setPaused(true);
    queue.enqueue(
      SyncOperation(
        type: 'upsert',
        dataId: 'produto-1',
        execute: () async {
          executou = true;
        },
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(executou, isFalse);
    expect(queue.getQueueInfo()['pendingCount'], 1);

    queue.setPaused(false);
    await Future<void>.delayed(const Duration(milliseconds: 250));

    expect(executou, isTrue);
    expect(queue.getQueueInfo()['pendingCount'], 0);
    queue.dispose();
  });

  test('fila não envia operação de outra empresa', () async {
    final queue = SyncQueueService(persistQueue: false);
    final executadas = <String>[];
    queue.setOperationGate((empresaId) => empresaId == 'empresa-ativa');

    queue.enqueue(
      SyncOperation(
        type: 'upsert',
        dataId: 'A1',
        empresaId: 'empresa-pausada',
        execute: () async {
          executadas.add('pausada');
        },
      ),
    );
    queue.enqueue(
      SyncOperation(
        type: 'upsert',
        dataId: 'B1',
        empresaId: 'empresa-ativa',
        execute: () async {
          executadas.add('ativa');
        },
      ),
    );
    for (var tentativa = 0;
        tentativa < 100 && !executadas.contains('ativa');
        tentativa++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }

    expect(executadas, ['ativa']);
    expect(queue.getQueueInfo()['pendingCount'], 1);

    queue.setOperationGate((empresaId) => empresaId == 'empresa-pausada');
    for (var tentativa = 0;
        tentativa < 100 && queue.getQueueInfo()['pendingCount'] != 0;
        tentativa++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }

    expect(executadas, ['ativa', 'pausada']);
    expect(queue.getQueueInfo()['pendingCount'], 0);
    queue.dispose();
  });

  group('temPendencia — alteração local ainda não enviada', () {
    test('reconhece pendência do mesmo registro (tipo case-insensitive)', () {
      final queue = SyncQueueService(persistQueue: false);
      queue.setPaused(true);
      queue.enqueue(
        SyncOperation(
          type: 'UPSERT',
          dataId: 'produto-1',
          execute: () async {},
        ),
      );

      expect(queue.temPendencia('UPSERT', 'produto-1'), isTrue);
      expect(queue.temPendencia('upsert', 'produto-1'), isTrue);
      expect(queue.temPendencia('UPSERT', 'produto-2'), isFalse);
      queue.dispose();
    });

    test('deixa de reconhecer depois que a operação é removida/enviada', () async {
      final queue = SyncQueueService(persistQueue: false);
      queue.setPaused(true);
      queue.enqueue(
        SyncOperation(
          type: 'UPSERT',
          dataId: 'produto-1',
          execute: () async {},
        ),
      );
      expect(queue.temPendencia('UPSERT', 'produto-1'), isTrue);

      queue.removeOperation('UPSERT', 'produto-1');
      expect(queue.temPendencia('UPSERT', 'produto-1'), isFalse);
      queue.dispose();
    });

    test('DELETE pendente também bloqueia sobrescrita da nuvem', () {
      final queue = SyncQueueService(persistQueue: false);
      queue.setPaused(true);
      queue.enqueue(
        SyncOperation(type: 'DELETE', dataId: 'venda-9', execute: () async {}),
      );

      expect(queue.temPendencia('DELETE', 'venda-9'), isTrue);
      expect(queue.temPendencia('UPSERT', 'venda-9'), isFalse);
      queue.dispose();
    });
  });
}
