// Isolamento do Fluxo de Caixa por empresa.
//
// Regressão do bug em que a leitura do caixa NÃO montava o `WHERE empresa_id`
// quando o *schema cache* (information_schema) não trazia a coluna — típico de
// uma base criada por um schema antigo, em que as tabelas de caixa não tinham
// `empresa_id`. Sem o filtro, o `SELECT *` devolvia as linhas de TODAS as
// empresas e o Fluxo de Caixa aparecia misturado (sempre, sem trocar de
// empresa). Agora o filtro é decidido por uma lista canônica de tabelas por
// empresa, que não depende do cache.
//
// Os testes de leitura usam o PostgreSQL local real (como o
// `guardas_isolamento_empresa_test.dart`); os de decisão são puros.
//
// Rodar: flutter test test/isolamento_fluxo_caixa_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_exodo_novo/services/database_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('deveFiltrarPorEmpresa (decisão do filtro)', () {
    test('tabelas de caixa filtram MESMO sem schema cache', () {
      const tabelas = [
        'aberturas_caixa',
        'fechamentos_caixa',
        'sangrias_caixa',
        'suprimentos_caixa',
        'vendas_balcao',
        'pedidos',
        'clientes',
        'produtos',
      ];
      for (final tabela in tabelas) {
        expect(
          DatabaseService.deveFiltrarPorEmpresa(tabela, null),
          isTrue,
          reason: '$tabela precisa filtrar por empresa sem depender do cache',
        );
      }
    });

    test('tabelas globais NUNCA filtram (a lista de empresas não pode sumir)', () {
      expect(DatabaseService.deveFiltrarPorEmpresa('empresas', null), isFalse);
      expect(DatabaseService.deveFiltrarPorEmpresa('usuarios', null), isFalse);
      expect(
        DatabaseService.deveFiltrarPorEmpresa('empresas', {'empresa_id': 'TEXT'}),
        isFalse,
        reason: 'empresas tem a coluna, mas continua global',
      );
    });

    test('tabela fora da lista só filtra se o schema disser que tem a coluna', () {
      expect(DatabaseService.deveFiltrarPorEmpresa('tabela_nova', null), isFalse);
      expect(
        DatabaseService.deveFiltrarPorEmpresa('tabela_nova', {'empresa_id': 'TEXT'}),
        isTrue,
      );
    });
  });

  group('leitura real do caixa (PostgreSQL local)', () {
    const bmj = '22ae2c16-a730-43f3-a4f9-19f105eb0d13';
    const sintetica = 'EMPRESA-SINTETICA-CAIXA-ISOLAMENTO';
    const idCaixa = 'ABERTURA-ISOLAMENTO-TESTE-1';

    String? empresaDe(Map<String, dynamic> row) =>
        (row['empresaId'] ?? row['empresa_id'])?.toString();

    test('abertura de uma empresa nunca aparece na leitura da outra', () async {
      final db = DatabaseService();

      // 1. Cria uma abertura no caixa da empresa sintética.
      db.setEmpresaId(sintetica);
      await db.salvarLista('exodo_aberturas_caixa', [
        {
          'id': idCaixa,
          'numero': 'CAIXA-TESTE-ISOLAMENTO',
          'data_abertura': DateTime.now().toUtc().toIso8601String(),
          'valor_inicial': 1.0,
        }
      ], isSync: true);

      final daSintetica = await db.carregarLista('exodo_aberturas_caixa');
      expect(daSintetica.any((a) => a['id'] == idCaixa), isTrue,
          reason: 'a abertura deveria existir na empresa que a criou');

      // 2. Na BMJ ela NÃO pode aparecer no Fluxo de Caixa, e nenhuma linha de
      //    outra empresa pode vir junto.
      db.setEmpresaId(bmj);
      final daBmj = await db.carregarLista('exodo_aberturas_caixa');
      expect(daBmj.any((a) => a['id'] == idCaixa), isFalse,
          reason: 'a abertura de OUTRA empresa vazou para o Fluxo de Caixa');
      expect(
        daBmj.every((a) => empresaDe(a) == bmj),
        isTrue,
        reason: 'toda linha lida tem de ser da empresa aberta',
      );

      // 3. Limpeza.
      db.setEmpresaId(sintetica);
      await db.removerItemPostgres(
        'exodo_aberturas_caixa',
        idCaixa,
        sintetica,
        isSync: true,
      );
      db.setEmpresaId(bmj);
    });
  });
}
