// Teste das travas de isolamento por empresa no banco REAL (PostgreSQL local).
//
// Verifica, com o próprio código do app, que:
//  1. LER sem empresa definida devolve VAZIO (antes o WHERE empresa_id era
//     omitido e a consulta trazia os dados de TODAS as empresas);
//  2. GRAVAR sem empresa definida NÃO grava nada (antes gravava com o
//     empresa_id que tinha ficado no singleton — a empresa anterior);
//  3. Com a empresa definida, grava/ler normalmente e com o empresa_id certo.
//
// Rodar: flutter test test/guardas_isolamento_empresa_test.dart
// Nada é enviado para a nuvem: as escritas usam isSync: true (silencia o
// trigger de sincronização) e o registro é apagado no fim.

import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_exodo_novo/services/data_service.dart';
import 'package:sistema_exodo_novo/services/database_service.dart';

void main() {
  const bmj = '22ae2c16-a730-43f3-a4f9-19f105eb0d13';
  const empresaTestes = '6bb61873-768f-4162-8b36-e3ef41fbb34f';
  const idTeste = 'GUARDA-ISOLAMENTO-TESTE-1';

  String? empresaDe(Map<String, dynamic> row) =>
      (row['empresaId'] ?? row['empresa_id'])?.toString();

  test('ler sem empresa nao devolve dados de outras empresas', () async {
    final db = DatabaseService();

    // Quantas linhas existem no banco somando TODAS as empresas (prova de que
    // sem filtro viria dados misturados).
    final todas = await db.carregarListaCompleta('exodo_clientes');
    print('clientes no banco (todas as empresas): ${todas.length}');

    // 1. Sem empresa definida: tem que vir VAZIO.
    db.setEmpresaId('');
    final semEmpresa = await db.carregarLista('exodo_clientes');
    print('clientes devolvidos SEM empresa: ${semEmpresa.length}');
    expect(semEmpresa, isEmpty,
        reason: 'sem empresa a leitura deve voltar vazia, nunca o banco inteiro');

    // 2. Com empresa definida: devolve só as linhas dela.
    db.setEmpresaId(bmj);
    final daBmj = await db.carregarLista('exodo_clientes');
    print('clientes da BMJ: ${daBmj.length} | todas as empresas: ${todas.length}');
    expect(daBmj, isNotEmpty);
    expect(daBmj.every((c) => empresaDe(c) == bmj), isTrue,
        reason: 'nenhuma linha de outra empresa pode aparecer');

    // A base LOCAL hoje contém só a empresa ATIVA: o sincronizador da bandeja
    // removeu as outras (por decisão de projeto). Então a prova de isolamento é
    // "toda linha devolvida é da BMJ" (acima), não "há menos que o total".
    if (todas.length > daBmj.length) {
      print('o local tem ${todas.length} linhas, das quais '
          '${todas.length - daBmj.length} de OUTRAS empresas — o filtro cortou o resto');
    } else {
      print('o local já contém somente a empresa ativa (${daBmj.length} linhas)');
    }
  });

  test('gravar sem empresa nao grava nada', () async {
    final db = DatabaseService();

    // 1. Sem empresa: NÃO pode gravar.
    db.setEmpresaId('');
    await db.salvarLista(
        'exodo_clientes', [
          {'id': idTeste, 'nome': 'NAO DEVE GRAVAR'}
        ],
        isSync: true);
    var todas = await db.carregarListaCompleta('exodo_clientes');
    expect(todas.any((c) => c['id'] == idTeste), isFalse,
        reason: 'gravou mesmo sem empresa definida');

    // 2. Com empresa definida: grava com o empresa_id certo.
    db.setEmpresaId(empresaTestes);
    await db.salvarLista(
        'exodo_clientes', [
          {'id': idTeste, 'nome': 'GRAVACAO DE TESTE'}
        ],
        isSync: true);
    todas = await db.carregarListaCompleta('exodo_clientes');
    final gravado = todas.firstWhere((c) => c['id'] == idTeste,
        orElse: () => <String, dynamic>{});
    print('gravado com empresa_id = ${empresaDe(gravado)}');
    expect(empresaDe(gravado), empresaTestes,
        reason: 'o registro precisa ir para a empresa definida');

    // 3. Limpeza.
    await db.removerItemPostgres('exodo_clientes', idTeste, empresaTestes,
        isSync: true);
    todas = await db.carregarListaCompleta('exodo_clientes');
    expect(todas.any((c) => c['id'] == idTeste), isFalse,
        reason: 'a limpeza do registro de teste falhou');

    // Restaura a empresa "aberta" do app para não influenciar outras coisas.
    db.setEmpresaId(bmj);
  });

  test('gravar registro de OUTRA empresa e recusado', () async {
    final db = DatabaseService();
    const idCruzado = 'TRAVA-EMPRESA-CRUZADA-1';

    // Empresa aberta = BMJ. Tentamos gravar um cliente carimbado com a empresa
    // de testes: a trava tem que RECUSAR (antes gravava assim mesmo e o
    // registro "desaparecia" da empresa dona — foi assim que o catalogo de uma
    // empresa apareceu zerado na outra).
    db.setEmpresaId(bmj);
    final bloqueiosAntes = db.gravacoesBloqueadasPorEmpresa;

    await db.salvarLista('exodo_clientes', [
      {
        'id': idCruzado,
        'nome': 'CLIENTE DA OUTRA EMPRESA',
        'empresa_id': empresaTestes,
      }
    ], isSync: true);

    final todas = await db.carregarListaCompleta('exodo_clientes');
    expect(todas.any((c) => c['id'] == idCruzado), isFalse,
        reason: 'registro de outra empresa nao pode ser gravado');
    expect(db.gravacoesBloqueadasPorEmpresa, greaterThan(bloqueiosAntes),
        reason: 'a trava precisa contabilizar a recusa como alarme');

    // Nao sobrou nada na empresa de testes com esse id.
    db.setEmpresaId(empresaTestes);
    final naEmpresaDeTestes = await db.carregarLista('exodo_clientes');
    expect(naEmpresaDeTestes.any((c) => c['id'] == idCruzado), isFalse,
        reason: 'nao pode sobrar registro da empresa recusada');

    // Restaura a empresa "aberta" do app.
    db.setEmpresaId(bmj);
  });

  test('limpar a lista COMPLETA do botao apaga so a empresa alvo', () async {
    final db = DatabaseService();
    // Empresa sintetica: nao existe de verdade, entao nada real e apagado.
    const empresaSintetica = 'EMPRESA-SINTETICA-TESTE-ISOLAMENTO';
    const idLocal = 'LIMPEZA-COMPLETA-TESTE-1';

    final tabelas = DataService.tabelasLocaisDaEmpresa;
    print('tabelas que o botao "Limpar Local" percorre: ${tabelas.length}');

    // 1. Baseline da empresa que NAO pode ser tocada.
    db.setEmpresaId(bmj);
    final bmjAntes = (await db.carregarLista('exodo_clientes')).length;

    // 2. Baseline das OUTRAS empresas medido com a empresa alvo selecionada
    //    (por definicao, "outras" = todas menos a alvo).
    db.setEmpresaId(empresaSintetica);
    final outrasAntes = await db.contarLinhasDeOutrasEmpresas(tabelas);
    print('outras empresas antes: $outrasAntes linha(s)');
    expect(outrasAntes, greaterThan(0));

    // 3. Coloca uma linha na empresa alvo para provar que ELA e apagada.
    await db.salvarLista('exodo_clientes', [
      {'id': idLocal, 'nome': 'LINHA DA EMPRESA ALVO'}
    ], isSync: true);

    // 4. LIMPAR LOCAL com a lista completa de tabelas (o que o botao faz).
    final removidas = await db.limparTabelasDaEmpresa(tabelas);
    print('removidas por tabela: $removidas');
    expect(removidas['clientes'], 1,
        reason: 'a linha da empresa alvo deveria ter sido apagada');

    // 5. As OUTRAS empresas nao perderam NENHUMA linha.
    final outrasDepois = await db.contarLinhasDeOutrasEmpresas(tabelas);
    print('outras empresas depois: $outrasDepois linha(s)');
    expect(outrasDepois, outrasAntes,
        reason: 'a limpeza completo nao pode mexer em outra empresa');

    // 6. E a BMJ continua com o mesmo numero de clientes.
    db.setEmpresaId(bmj);
    final bmjDepois = (await db.carregarLista('exodo_clientes')).length;
    print('BMJ antes: $bmjAntes | BMJ depois: $bmjDepois');
    expect(bmjDepois, bmjAntes,
        reason: 'NENHUMA linha da BMJ pode ser afetada');
  });

  test('limparTabelasDaEmpresa apaga so a empresa alvo', () async {
    final db = DatabaseService();
    const idLocal = 'LIMPAR-LOCAL-TESTE-1';

    // 1. Baseline da empresa que NÃO pode ser tocada (medir com ela selecionada).
    db.setEmpresaId(bmj);
    final bmjAntes = (await db.carregarLista('exodo_clientes')).length;

    // 2. Cria um registro na empresa de testes (escrita silenciosa).
    db.setEmpresaId(empresaTestes);
    await db.salvarLista('exodo_clientes', [
      {'id': idLocal, 'nome': 'REGISTRO DE TESTE'}
    ], isSync: true);

    final testesComEmpresa = (await db.carregarListaCompleta('exodo_clientes'))
        .where((c) => empresaDe(c) == empresaTestes)
        .length;
    print('BMJ antes: $bmjAntes | empresa de testes antes: $testesComEmpresa');
    expect(testesComEmpresa, greaterThan(0));

    // 3. LIMPAR LOCAL da empresa de testes (é o que o botão chama).
    final removidas = await db.limparTabelasDaEmpresa(['exodo_clientes']);
    print('limparTabelasDaEmpresa -> $removidas');
    expect(removidas['clientes'], testesComEmpresa,
        reason: 'deveria ter apagado exatamente as linhas da empresa alvo');

    // 4. A empresa alvo ficou limpa...
    db.setEmpresaId(empresaTestes);
    expect(await db.carregarLista('exodo_clientes'), isEmpty,
        reason: 'a empresa alvo deveria estar vazia');

    // 5. ...e a BMJ não perdeu NENHUMA linha.
    db.setEmpresaId(bmj);
    final bmjDepois = (await db.carregarLista('exodo_clientes')).length;
    print('BMJ depois: $bmjDepois');
    expect(bmjDepois, bmjAntes,
        reason: 'NENHUMA linha de outra empresa pode ser afetada');
  });
}
