// Teste do ISOLAMENTO do catálogo por empresa — o defeito que misturava itens
// quando o regime tributário da empresa era trocado.
//
// O que acontecia: o produto não guardava de QUEM ele era. O banco local
// carimba toda gravação com a empresa ABERTA no app, então um produto que
// entrasse na memória vindo de outro lugar (cache antigo, backup, nuvem) era
// adotado pela empresa errada em silêncio. A troca de REGIME TRIBUTÁRIO, que
// reescreve o código fiscal dos produtos em laço, era quando isso aparecia:
// "misturou todos os itens e mudou os códigos de imposto".
//
// Aqui ficam travadas as três garantias:
//   1. o produto carrega a própria empresa (e o mapa leva o `empresa_id`);
//   2. produto de OUTRA empresa não entra na memória nem é gravado;
//   3. a troca de regime só planeja (e só grava) produtos DA EMPRESA editada.
//
// A última prova é contra o banco REAL (PostgreSQL local), com empresas
// sintéticas: nada de empresa de verdade é alterado, e tudo é apagado no fim.
//
// Rodar: flutter test test/isolamento_regime_produtos_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_exodo_novo/models/perfil_tributario.dart';
import 'package:sistema_exodo_novo/models/produto.dart';
import 'package:sistema_exodo_novo/services/data_service.dart';
import 'package:sistema_exodo_novo/services/database_service.dart';
import 'package:sistema_exodo_novo/services/local_storage_service.dart';

/// Produto de teste com o carimbo de empresa que quisermos.
Produto produto({
  required String id,
  String? empresaId,
  String? csosn,
  String? icmsCst,
  String? perfilTributarioId,
  String? cfop,
}) {
  final agora = DateTime(2026, 9, 23, 12);
  return Produto(
    id: id,
    empresaId: empresaId,
    nome: 'PRODUTO $id',
    unidade: 'un',
    grupo: 'Teste',
    preco: 10,
    estoque: 5,
    createdAt: agora,
    updatedAt: agora,
    csosn: csosn,
    icmsCst: icmsCst,
    perfilTributarioId: perfilTributarioId,
    cfop: cfop,
  );
}

/// A leitura do banco devolve camelCase (`icmsCst`), a gravação usa snake
/// (`icms_cst`): o teste lê os dois para não depender da conversão.
Object? campo(Map<String, dynamic> linha, String camel, String snake) =>
    linha[camel] ?? linha[snake];

void main() {
  const empresaA = 'EMPRESA-A-ISOLAMENTO-REGIME';
  const empresaB = 'EMPRESA-B-ISOLAMENTO-REGIME';

  group('o produto carrega de quem ele é', () {
    test('toMap leva o empresa_id (é o que faz o banco recusar a troca de dono)',
        () {
      final p = produto(id: 'P1', empresaId: empresaA, csosn: '102');
      expect(p.toMap()['empresa_id'], empresaA);

      // A chave vai SEMPRE (mesmo nula): sem ela o banco não tem como saber que
      // o registro é de outra empresa e carimba a empresa aberta.
      final novo = produto(id: 'P2');
      expect(novo.toMap().containsKey('empresa_id'), isTrue);
      expect(novo.toMap()['empresa_id'], isNull);
    });

    test('fromMap lê o empresa_id que veio do banco (snake e camel)', () {
      expect(Produto.fromMap(produto(id: 'P1', empresaId: empresaA).toMap()).empresaId,
          empresaA);
      expect(
          Produto.fromMap({
            'id': 'P1',
            'nome': 'X',
            'unidade': 'un',
            'empresaId': empresaB,
          }).empresaId,
          empresaB);
    });

    test('copyWith preserva a empresa', () {
      final p = produto(id: 'P1', empresaId: empresaA, csosn: '102');
      final migrado = p.copyWith(csosn: '102', icmsCst: null);
      expect(migrado.empresaId, empresaA);
      expect(migrado.id, 'P1');
    });
  });

  group('a regra de "outra empresa"', () {
    test('empresa do produto diferente da aberta = de outra empresa', () {
      expect(DataService.produtoDeEmpresaDiferente(empresaB, empresaA), isTrue);
      expect(DataService.produtoDeEmpresaDiferente(empresaA, empresaA), isFalse);
      // Sem carimbo (produto novo ou registro antigo) não é "de outra empresa":
      // aqui a empresa aberta é a resposta certa.
      expect(DataService.produtoDeEmpresaDiferente(null, empresaA), isFalse);
      expect(DataService.produtoDeEmpresaDiferente('', empresaA), isFalse);
      // Sem empresa aberta quem barra é o banco.
      expect(DataService.produtoDeEmpresaDiferente(empresaB, null), isFalse);
      expect(DataService.produtoDeEmpresaDiferente(empresaB, ''), isFalse);
    });

    test('o filtro devolve só os produtos da empresa alvo', () {
      final lista = [
        produto(id: 'A1', empresaId: empresaA),
        produto(id: 'B1', empresaId: empresaB),
        produto(id: 'SEM-DONO'),
        produto(id: 'A2', empresaId: empresaA),
      ];
      final daA = DataService.filtrarProdutosDaEmpresa(lista, empresaAlvo: empresaA);
      expect(daA.map((p) => p.id).toList(), ['A1', 'SEM-DONO', 'A2'],
          reason: 'produto de outra empresa não pode entrar na memória da A');
    });
  });

  group('a troca de regime só planeja produtos DA EMPRESA editada', () {
    // Catálogo misturado de propósito: 2 da empresa A, 1 da B, 1 sem carimbo.
    final misturado = [
      produto(id: 'A-COM-CST', empresaId: empresaA, icmsCst: '00'),
      produto(id: 'A-SEM-CODIGO', empresaId: empresaA),
      produto(id: 'B-COM-CSOSN', empresaId: empresaB, csosn: '102', icmsCst: '60'),
      produto(id: 'SEM-DONO-COM-CSOSN', csosn: '102'),
    ];

    test('produto de outra empresa NÃO entra no plano (nem é tocado)', () {
      final plano = DataService.planejarMigracaoDeImpostos(
        misturado,
        paraSimples: true, // Regime Normal -> Simples
        empresaId: empresaA,
      );

      // Entram no plano os produtos da A que MUDAM: o que tem CST (vira CSOSN)
      // e o que não tinha código (ganha o padrão). O produto que já estava no
      // padrão do Simples não é reescrito à toa.
      expect(plano.paraGravar.map((p) => p.id).toList(),
          ['A-COM-CST', 'A-SEM-CODIGO']);
      expect(plano.deOutraEmpresa.map((p) => p.id).toList(), ['B-COM-CSOSN']);
      expect(plano.semMudanca, 1,
          reason: 'SEM-DONO-COM-CSOSN já está no padrão do Simples');

      // O produto da B continua exatamente como estava (objeto intacto).
      final daB = misturado.firstWhere((p) => p.id == 'B-COM-CSOSN');
      expect(daB.csosn, '102');
      expect(daB.icmsCst, '60');
      expect(plano.paraGravar.any((p) => p.id == 'B-COM-CSOSN'), isFalse);
    });

    test('converte CST->CSOSN e preenche quem não tinha nada', () {
      final plano = DataService.planejarMigracaoDeImpostos(
        misturado,
        paraSimples: true,
        empresaId: empresaA,
      );

      final comCst = plano.paraGravar.firstWhere((p) => p.id == 'A-COM-CST');
      expect(comCst.csosn, '102', reason: 'CST 00 vira CSOSN 102 no Simples');
      expect(comCst.icmsCst, isNull, reason: 'o CST do regime antigo sai');

      final semCodigo =
          plano.paraGravar.firstWhere((p) => p.id == 'A-SEM-CODIGO');
      expect(semCodigo.csosn, '102');

      // 1 já tinha código (convertido) + 1 ganhou o padrão (preenchido).
      expect(plano.convertidos, 1);
      expect(plano.preenchidos, 1);
      expect(plano.semCarimbo.map((p) => p.id).toList(),
          ['SEM-DONO-COM-CSOSN']);
    });

    test('de volta para o Regime Normal: CSOSN->CST, e quem já está certo não muda',
        () {
      final catalogo = [
        produto(id: 'A-SIMPLES', empresaId: empresaA, csosn: '102'),
        produto(id: 'A-NORMAL', empresaId: empresaA, icmsCst: '00'),
        produto(id: 'B-SIMPLES', empresaId: empresaB, csosn: '102'),
      ];
      final plano = DataService.planejarMigracaoDeImpostos(
        catalogo,
        paraSimples: false, // -> Regime Normal
        empresaId: empresaA,
      );

      expect(plano.paraGravar.map((p) => p.id).toList(), ['A-SIMPLES']);
      expect(plano.paraGravar.single.icmsCst, '00');
      expect(plano.paraGravar.single.csosn, isNull);
      expect(plano.semMudanca, 1, reason: 'A-NORMAL já está no CST');
      expect(plano.deOutraEmpresa.map((p) => p.id).toList(), ['B-SIMPLES']);
    });

    test('perfil padrão do outro regime acompanha a troca', () {
      final catalogo = [
        produto(
          id: 'A-PERFIL',
          empresaId: empresaA,
          icmsCst: '00',
          perfilTributarioId: 'padrao_tributado_normal',
        ),
      ];
      final plano = DataService.planejarMigracaoDeImpostos(
        catalogo,
        paraSimples: true,
        empresaId: empresaA,
      );
      expect(plano.paraGravar.single.perfilTributarioId,
          'padrao_tributado_simples');
    });

    test('perfil PERSONALIZADO do produto permanece vinculado (não é desvinculado)',
        () {
      // Era isto que "não respeitava o cadastro": o produto tinha um perfil
      // configurado pelo usuário e a troca de regime o deixava SEM perfil.
      final catalogo = [
        produto(
          id: 'A-CUSTOM',
          empresaId: empresaA,
          icmsCst: '00',
          perfilTributarioId: 'meu_perfil_normal',
          cfop: '5405',
        ),
      ];
      final plano = DataService.planejarMigracaoDeImpostos(
        catalogo,
        paraSimples: true,
        empresaId: empresaA,
      );

      final migrado = plano.paraGravar.single;
      expect(migrado.perfilTributarioId, 'meu_perfil_normal',
          reason: 'perfil personalizado NUNCA pode ser desvinculado do produto');
      expect(migrado.csosn, '102',
          reason: 'o CST 00 do cadastro vira CSOSN 102 (o código do outro '
              'regime não existe no Simples)');
      expect(migrado.icmsCst, isNull);
      expect(migrado.cfop, '5405', reason: 'o CFOP do cadastro é preservado');
    });

    test('produto com perfil e SEM código: completa o código a partir do perfil',
        () {
      final perfis = [
        PerfilTributario(
          id: 'meu_nao_tributado',
          nome: 'Não Tributado (meu)',
          cfop: '5102',
          csosn: '400',
        ),
      ];
      final catalogo = [
        produto(
          id: 'A-PERFIL-SEM-CODIGO',
          empresaId: empresaA,
          perfilTributarioId: 'meu_nao_tributado',
        ),
      ];
      final plano = DataService.planejarMigracaoDeImpostos(
        catalogo,
        paraSimples: false, // -> Regime Normal
        empresaId: empresaA,
        perfis: perfis,
      );

      final migrado = plano.paraGravar.single;
      expect(migrado.perfilTributarioId, 'meu_nao_tributado',
          reason: 'o perfil é do cadastro: continua vinculado');
      expect(migrado.icmsCst, '41',
          reason: 'o CSOSN 400 do perfil vira CST 41 no Regime Normal');
      expect(migrado.csosn, isNull);
      expect(plano.convertidos, 1,
          reason: 'tinha imposto (o perfil), então não é "sem imposto nenhum"');
      expect(plano.preenchidos, 0);
    });

    test('produto SEM nenhum imposto ganha o PERFIL PADRÃO do regime novo', () {
      // O padrão do Simples que a empresa tem (é o que aparece com o selo
      // PADRÃO na tela de Perfis Tributários). O produto tem que sair com o
      // VÍNCULO do perfil + o CFOP + o CSOSN dele — antes ele saía com um
      // código solto e sem perfil nenhum ("o perfil padrão não está mudando").
      final padrao = PerfilTributario(
        id: 'padrao_tributado_simples',
        nome: 'Tributado (Simples Nacional)',
        cfop: '5102',
        csosn: '102',
        isDefault: true,
      );
      final plano = DataService.planejarMigracaoDeImpostos(
        [produto(id: 'A-NU', empresaId: empresaA)],
        paraSimples: true,
        empresaId: empresaA,
        perfis: [padrao],
      );

      final migrado = plano.paraGravar.single;
      expect(migrado.perfilTributarioId, 'padrao_tributado_simples');
      expect(migrado.csosn, '102');
      expect(migrado.cfop, '5102');
      expect(plano.preenchidos, 1);
      expect(plano.convertidos, 0);
      expect(plano.perfilPadraoDoRegimeNovo.id, 'padrao_tributado_simples');
    });

    test('produto com código próprio e SEM perfil passa a usar o perfil PADRÃO '
        'do próprio código', () {
      final perfis = [
        PerfilTributario(
            id: 'padrao_tributado_simples',
            nome: 'Tributado (Simples Nacional)',
            cfop: '5102',
            csosn: '102',
            isDefault: true),
        PerfilTributario(
            id: 'padrao_nao_tributado_simples',
            nome: 'Não Tributado (Simples Nacional)',
            cfop: '5102',
            csosn: '400'),
        PerfilTributario(
            id: 'padrao_substituicao_simples',
            nome: 'Substituição Tributária (Simples Nacional)',
            cfop: '5405',
            csosn: '500'),
      ];
      final catalogo = [
        produto(id: 'A-TRIBUTADO', empresaId: empresaA, csosn: '102'),
        produto(id: 'A-NAO-TRIBUTADO', empresaId: empresaA, csosn: '400'),
        produto(id: 'A-ST', empresaId: empresaA, csosn: '500', cfop: '5405'),
      ];
      final plano = DataService.planejarMigracaoDeImpostos(
        catalogo,
        paraSimples: true,
        empresaId: empresaA,
        perfis: perfis,
      );

      final porId = {for (final p in plano.paraGravar) p.id: p};
      expect(porId['A-TRIBUTADO']!.perfilTributarioId,
          'padrao_tributado_simples');
      expect(porId['A-TRIBUTADO']!.csosn, '102',
          reason: 'o código do cadastro não pode mudar');
      expect(porId['A-NAO-TRIBUTADO']!.perfilTributarioId,
          'padrao_nao_tributado_simples',
          reason: 'não tributado NUNCA pode receber o padrão tributado '
              '(a emissão passaria a usar CSOSN 102 e mudaria o imposto)');
      expect(porId['A-NAO-TRIBUTADO']!.csosn, '400');
      expect(porId['A-ST']!.perfilTributarioId, 'padrao_substituicao_simples');
      expect(porId['A-ST']!.cfop, '5405',
          reason: 'o CFOP do cadastro é preservado');
      expect(plano.vinculadosAoPadrao, 3);
      expect(plano.preenchidos, 0,
          reason: 'tinham imposto: não são "sem imposto nenhum"');
    });

    test('código SEM perfil padrão equivalente continua sem perfil (cadastro '
        'preservado)', () {
      final perfis = [
        PerfilTributario(
            id: 'padrao_tributado_simples',
            nome: 'Tributado (Simples Nacional)',
            cfop: '5102',
            csosn: '102',
            isDefault: true),
      ];
      final plano = DataService.planejarMigracaoDeImpostos(
        [produto(id: 'A-900', empresaId: empresaA, csosn: '900')],
        paraSimples: true,
        empresaId: empresaA,
        perfis: perfis,
      );

      expect(plano.paraGravar, isEmpty);
      expect(plano.semMudanca, 1,
          reason: 'CSOSN 900 não tem perfil padrão: melhor não tocar');
      expect(plano.vinculadosAoPadrao, 0);
    });

    test('perfil PADRÃO customizado pelo usuário também é considerado', () {
      final perfis = [
        PerfilTributario(
            id: 'padrao_tributado_simples',
            nome: 'Tributado (meu)',
            cfop: '5102',
            csosn: '103',
            isDefault: true),
      ];

      expect(
          DataService.perfilPadraoParaCodigo(perfis,
                  paraSimples: true, csosn: '103')
              ?.id,
          'padrao_tributado_simples');
      expect(
          DataService.perfilPadraoParaCodigo(perfis,
              paraSimples: true, csosn: '400'),
          isNull,
          reason: 'a empresa não tem padrão de não tributado: não vincula um '
              'perfil que mudaria o código do produto');
    });

    test('o perfil padrão escolhido é o do REGIME novo (o que tem selo PADRÃO)',
        () {
      final perfis = [
        PerfilTributario(
            id: 'outro_simples',
            nome: 'Outro (Simples)',
            cfop: '5102',
            csosn: '400',
            isDefault: true),
        PerfilTributario(
            id: 'padrao_tributado_normal',
            nome: 'Tributado (Regime Normal)',
            cfop: '5102',
            icmsCst: '00',
            isDefault: true),
      ];

      expect(DataService.perfilPadraoDoRegime(perfis, paraSimples: false)?.id,
          'padrao_tributado_normal',
          reason: 'no Regime Normal o padrão precisa ter CST');
      expect(DataService.perfilPadraoDoRegime(perfis, paraSimples: true)?.id,
          'outro_simples');
      expect(DataService.perfilPadraoDoRegime(const [], paraSimples: true),
          isNull,
          reason: 'sem perfil padrão, o plano usa o padrão de fábrica');
    });
  });

  group('o selo PADRÃO é escolha do usuário (e não volta sozinho)', () {
    // O defeito: a rotina que garante os perfis do sistema forçava
    // isDefault=true no "Tributado" a cada carregamento. Quem marcava outro
    // perfil como padrão via o selo PADRÃO voltar para o Tributado ao reabrir a
    // tela ("não muda aqui") — e o regime ficava com dois padrões, então o
    // perfil aplicado aos produtos dependia da ordem da lista.
    test('copyWith troca o selo PADRÃO e preserva o resto do perfil', () {
      final original = PerfilTributario(
        id: 'meu_perfil',
        nome: 'Meu Perfil',
        cfop: '5405',
        csosn: '500',
        aliquotaIcms: 18,
        ncm: '12345678',
        isDefault: true,
      );

      final semSelo = original.copyWith(isDefault: false);

      expect(semSelo.isDefault, isFalse);
      expect(semSelo.id, 'meu_perfil');
      expect(semSelo.cfop, '5405');
      expect(semSelo.csosn, '500');
      expect(semSelo.aliquotaIcms, 18);
      expect(semSelo.ncm, '12345678');
      expect(original.isDefault, isTrue,
          reason: 'o perfil original não é alterado');
    });

    test('copyWith consegue LIMPAR o código do regime oposto', () {
      final misturado = PerfilTributario(
          id: 'padrao_substituicao_simples',
          nome: 'Substituição Tributária (Simples Nacional)',
          cfop: '5405',
          csosn: '500',
          icmsCst: '60'),
          limpo = misturado.copyWith(limparIcmsCst: true);

      expect(limpo.csosn, '500');
      expect(limpo.icmsCst, isNull,
          reason: 'perfil do Simples não pode ficar com CSOSN e CST juntos');
      expect(misturado.icmsCst, '60', reason: 'o original fica intacto');
    });

    test('dado legado com dois padrões no Simples fica com a ESCOLHA do usuário',
        () {
      final perfis = [
        PerfilTributario(
            id: 'padrao_tributado_simples',
            nome: 'Tributado (Simples Nacional)',
            cfop: '5102',
            csosn: '102',
            isDefault: true),
        PerfilTributario(
            id: 'padrao_nao_tributado_simples',
            nome: 'Não Tributado (Simples Nacional)',
            cfop: '5102',
            csosn: '400',
            isDefault: true),
        PerfilTributario(
            id: 'padrao_tributado_normal',
            nome: 'Tributado (Regime Normal)',
            cfop: '5102',
            icmsCst: '00',
            isDefault: true),
      ];

      final corrigidos = DataService.padroesUnicosPorRegime(perfis);

      expect(
          corrigidos
              .where((p) => p.isDefault && (p.csosn?.isNotEmpty ?? false))
              .map((p) => p.id),
          ['padrao_nao_tributado_simples'],
          reason: 'o Tributado do sistema não pode roubar o selo de quem o '
              'usuário escolheu');
      expect(
          corrigidos
              .firstWhere((p) => p.id == 'padrao_tributado_normal')
              .isDefault,
          isTrue,
          reason: 'o padrão do OUTRO regime é preservado (é um por regime)');
      expect(DataService.perfilPadraoDoRegime(corrigidos, paraSimples: true)?.id,
          'padrao_nao_tributado_simples',
          reason: 'é esse perfil que os produtos sem imposto recebem');
    });

    test('empresa já correta: um padrão por regime e nada muda', () {
      final perfis = [
        PerfilTributario(
            id: 'padrao_tributado_simples',
            nome: 'Tributado (Simples Nacional)',
            cfop: '5102',
            csosn: '102',
            isDefault: true),
        PerfilTributario(
            id: 'padrao_nao_tributado_simples',
            nome: 'Não Tributado (Simples Nacional)',
            cfop: '5102',
            csosn: '400'),
        PerfilTributario(
            id: 'meu_perfil',
            nome: 'Meu Perfil',
            cfop: '5102',
            csosn: '900'),
        PerfilTributario(
            id: 'padrao_tributado_normal',
            nome: 'Tributado (Regime Normal)',
            cfop: '5102',
            icmsCst: '00',
            isDefault: true),
      ];

      final corrigidos = DataService.padroesUnicosPorRegime(perfis);

      expect(corrigidos.map((p) => p.id).toList(),
          perfis.map((p) => p.id).toList(),
          reason: 'a ordem da lista é preservada');
      expect(
          corrigidos.where((p) => p.isDefault).map((p) => p.id),
          ['padrao_tributado_simples', 'padrao_tributado_normal']);
      expect(DataService.perfilPadraoDoRegime(corrigidos, paraSimples: true)?.id,
          'padrao_tributado_simples');
    });
  });

  group('no banco REAL: produto de outra empresa não pode ser regravado', () {
    final db = DatabaseService();
    const idProduto = 'ISOLAMENTO-REGIME-PRODUTO-1';

    tearDown(() async {
      // Limpeza: tira a linha sintética das duas empresas.
      await db.removerItemPostgres(
          LocalStorageService.keyProdutos, idProduto, empresaA,
          isSync: true);
      await db.removerItemPostgres(
          LocalStorageService.keyProdutos, idProduto, empresaB,
          isSync: true);
      db.setEmpresaId('');
    });

    test('gravar o produto da B com a empresa A aberta é recusado', () async {
      // 1. O produto nasce na empresa B (é o dono dele).
      final original =
          produto(id: idProduto, empresaId: empresaB, csosn: '102', cfop: '5102');
      db.setEmpresaId(empresaB);
      await db.salvarLista(LocalStorageService.keyProdutos,
          [original.toMap()], isSync: true);

      final naB = await db.carregarLista(LocalStorageService.keyProdutos);
      final linhaB = naB.firstWhere((p) => p['id'] == idProduto,
          orElse: () => <String, dynamic>{});
      print('linha gravada na B: $linhaB');
      expect(campo(linhaB, 'csosn', 'csosn'), '102',
          reason: 'o produto deveria ter sido gravado na empresa B');
      expect(campo(linhaB, 'empresaId', 'empresa_id'), empresaB,
          reason: 'o produto precisa nascer carimbado com a empresa dona');

      // 2. Com a empresa A aberta, a troca de regime TENTA regravar o produto.
      //    Antes: a linha era atualizada e ADOTADA pela A (o item "mudava de
      //    empresa" e os impostos eram reescritos junto).
      db.setEmpresaId(empresaA);
      final bloqueiosAntes = db.gravacoesBloqueadasPorEmpresa;
      final migrado = original.copyWith(csosn: null, icmsCst: '00', cfop: '5102');
      await db.salvarLista(
          LocalStorageService.keyProdutos, [migrado.toMap()],
          isSync: true);

      // A linha da B continua intacta.
      db.setEmpresaId(empresaB);
      final depois = await db.carregarLista(LocalStorageService.keyProdutos);
      final linhaDepois = depois.firstWhere((p) => p['id'] == idProduto,
          orElse: () => <String, dynamic>{});
      print('linha da B depois da tentativa da A: $linhaDepois');
      expect(campo(linhaDepois, 'csosn', 'csosn'), '102',
          reason: 'o CSOSN da empresa B não pode ser mexido pela empresa A');
      expect(campo(linhaDepois, 'icmsCst', 'icms_cst') ?? '', isEmpty,
          reason: 'a A não pode escrever CST no produto da B');
      expect(campo(linhaDepois, 'empresaId', 'empresa_id'), empresaB,
          reason: 'o produto não pode trocar de dono');

      expect(db.gravacoesBloqueadasPorEmpresa, greaterThan(bloqueiosAntes),
          reason: 'a trava do banco precisa ter recusado e contado');
    });

    test('o mesmo produto grava normalmente na empresa DONA', () async {
      final dono =
          produto(id: idProduto, empresaId: empresaB, csosn: '102');
      db.setEmpresaId(empresaB);
      await db.salvarLista(LocalStorageService.keyProdutos,
          [dono.toMap()], isSync: true);

      final alterado = dono.copyWith(csosn: null, icmsCst: '00');
      await db.salvarLista(LocalStorageService.keyProdutos,
          [alterado.toMap()], isSync: true);

      final naB = await db.carregarLista(LocalStorageService.keyProdutos);
      final linha = naB.firstWhere((p) => p['id'] == idProduto,
          orElse: () => <String, dynamic>{});
      print('linha da B depois da gravação legítima: $linha');
      expect(campo(linha, 'icmsCst', 'icms_cst'), '00',
          reason: 'na empresa dona a gravação precisa funcionar');
      expect(campo(linha, 'empresaId', 'empresa_id'), empresaB);
    });

    test('o LOTE da migração grava o perfil tributário no banco', () async {
      // A migração passou a gravar em bloco (adicionarProdutosLote) em vez de
      // um updateProduto por item. Se o perfil não atravessasse esse caminho,
      // o produto continuaria aparecendo SEM perfil na tela.
      final migrado = produto(
        id: idProduto,
        empresaId: empresaB,
        csosn: '102',
        cfop: '5102',
        perfilTributarioId: 'padrao_tributado_simples',
      );
      db.setEmpresaId(empresaB);
      await db.adicionarProdutosLote([migrado.toMap()]);

      final linhas = await db.carregarLista(LocalStorageService.keyProdutos);
      final linha = linhas.firstWhere((p) => p['id'] == idProduto,
          orElse: () => <String, dynamic>{});
      print('linha gravada em lote: $linha');
      expect(campo(linha, 'perfilTributarioId', 'perfil_tributario_id'),
          'padrao_tributado_simples',
          reason: 'o perfil padrão precisa chegar ao banco junto com o produto');
      expect(campo(linha, 'csosn', 'csosn'), '102');
    });
  });
}
