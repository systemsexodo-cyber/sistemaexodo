// Teste de tela da conferência Local × Nuvem, com um resultado FALSO injetado
// (não toca banco nenhum). Verifica o que o usuário vê: resumo, filtros de
// diferenças/telemetria e o detalhe de cada linha.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_exodo_novo/pages/conferencia_local_nuvem_page.dart';
import 'package:sistema_exodo_novo/services/conferencia_nuvem_service.dart';

Future<ResultadoConferencia> _resultadoFalso() async {
  return const ResultadoConferencia(
    linhas: [
      DiferencaConferencia(
        tabela: 'produtos',
        empresaId: 'empresa-a',
        local: 10,
        nuvem: 10,
      ),
      DiferencaConferencia(
        tabela: 'estoque_historico',
        empresaId: 'empresa-a',
        local: 300,
        nuvem: 536,
      ),
      DiferencaConferencia(
        tabela: 'vendas_balcao',
        empresaId: 'empresa-b',
        local: 0,
        nuvem: 14,
      ),
      DiferencaConferencia(
        tabela: 'sync_logs',
        empresaId: 'empresa-a',
        local: 6492,
        nuvem: 7028,
        telemetria: true,
      ),
    ],
    somenteNoLocal: ['exodo_sync_conflitos'],
    somenteNaNuvem: ['usuarios'],
    nomesDeEmpresas: {
      'empresa-a': 'BMJ PETSHOP',
      'empresa-b': 'EXODO SYSTEMS',
    },
  );
}

Widget _app(Future<ResultadoConferencia> Function() carregar) {
  return MaterialApp(
    home: ConferenciaLocalNuvemPage(
      carregar: carregar,
      empresaAberta: 'BMJ PETSHOP',
      // A empresa aberta é a "empresa-a": o que for da "empresa-b" fica no
      // relatório marcado como esperado (a base local guarda só a aberta).
      empresaAbertaId: 'empresa-a',
    ),
  );
}

Future<void> _abrir(WidgetTester tester) async {
  await tester.pumpWidget(_app(_resultadoFalso));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('mostra o resumo e so as diferencas por padrao', (tester) async {
    await _abrir(tester);

    expect(find.text('Conferir: Local × Nuvem'), findsOneWidget);
    expect(find.text('Empresa aberta agora: BMJ PETSHOP'), findsOneWidget);

    // 2 diferenças de dados (estoque_historico e vendas_balcao). A de
    // telemetria (sync_logs) fica escondida por padrão.
    expect(find.text('2 diferença(s) encontrada(s)'), findsOneWidget);

    // Produtos iguais (10 x 10) NÃO aparecem com o filtro ligado.
    expect(find.text('produtos'), findsNothing);
    // Diferenças aparecem, com o nome da empresa e o delta.
    expect(find.text('estoque_historico'), findsOneWidget);
    expect(find.textContaining('local 300  ·  nuvem 536'), findsOneWidget);
    expect(find.text('+236'), findsOneWidget);
    expect(find.text('vendas_balcao'), findsOneWidget);
    expect(find.textContaining('BMJ PETSHOP'), findsWidgets);
    // Telemetria escondida.
    expect(find.text('sync_logs'), findsNothing);
    // Tabelas fora da comparação são informadas.
    expect(find.textContaining('exodo_sync_conflitos'), findsOneWidget);
    expect(find.textContaining('usuarios'), findsOneWidget);
  });

  testWidgets('desligando os filtros mostra tudo, inclusive telemetria',
      (tester) async {
    await _abrir(tester);

    await tester.tap(find.text('Mostrar somente as diferenças'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.text('Esconder logs e views (sync_logs, sync_status...)'),
    );
    await tester.pumpAndSettle();

    expect(find.text('produtos'), findsOneWidget); // 10 x 10 -> "igual"
    // A lista é longa: a telemetria é a última linha, então rola até ela
    // (item fora da tela nem chega a ser construído).
    await tester.scrollUntilVisible(find.text('sync_logs'), 200);
    expect(find.text('sync_logs'), findsOneWidget);
    expect(find.text('igual'), findsWidgets);
  });

  testWidgets('divergencia de outra empresa vem marcada como esperada',
      (tester) async {
    await _abrir(tester);

    // "vendas_balcao" é da empresa-b (a aberta é a empresa-a).
    expect(
      find.textContaining('Esperado: a base local guarda só a empresa aberta'),
      findsOneWidget,
    );
    expect(
      find.textContaining('só ela é corrigida ao sincronizar'),
      findsOneWidget,
      reason: 'o resumo precisa explicar por que a divergência não é corrigida',
    );
  });

  testWidgets('erro de conexao aparece como aviso, sem derrubar a tela',
      (tester) async {
    await tester.pumpWidget(
      _app(() async => throw StateError('sem conexão')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Não foi possível conferir'), findsOneWidget);
    expect(find.textContaining('sem conexão'), findsOneWidget);
    expect(find.byIcon(Icons.refresh), findsOneWidget);
  });
}
