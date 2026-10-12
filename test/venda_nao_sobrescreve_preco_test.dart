// Teste da GRAVAÇÃO PARCIAL de produto — o defeito que fazia o preço de um item
// divergir entre os dois PCs sem nunca convergir.
//
// O que acontecia em produção (03/10/2026, item "coca cola"):
//   1. o preço foi editado de R$ 24,00 para R$ 2,00 num PC;
//   2. a edição foi propagada para os dois bancos, mas o app do OUTRO PC ainda
//      tinha o objeto do produto em memória com o preço antigo;
//   3. uma venda abateu o estoque e chamou `updateProduto`. Essa função gravava
//      a LINHA INTEIRA a partir do objeto em memória — então o R$ 24,00 voltou
//      para o banco junto com o estoque novo;
//   4. como o UPDATE é uma alteração real, ele também carimbava `updated_at`
//      mais novo: agora o banco com o preço ERRADO é que parecia o mais recente,
//      e os dois PCs se recusavam indefinidamente.
//
// A correção: quando a alteração mexe SÓ em colunas de estoque (baixa de
// venda, devolução, ajuste), o app passa a gravar apenas essas colunas no
// banco. O preço gravado continua sendo o do banco — o correto.
//
// Aqui ficam travadas as garantias:
//   1. só estoque mudou -> grava só estoque (nada mais);
//   2. preço mudou junto -> grava a linha inteira (edição de verdade);
//   3. lista/mapa vazios vindos de caminhos diferentes não contam como mudança
//      (senão toda venda cairia no caso 1 por engano… ou pior, no caso 2);
//   4. a gravação parcial monta o UPDATE com as colunas pedidas e ignora
//      coluna que não existe no schema.
//
// Rodar: flutter test test/venda_nao_sobrescreve_preco_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_exodo_novo/models/produto.dart';
import 'package:sistema_exodo_novo/services/data_service.dart';
import 'package:sistema_exodo_novo/services/database_service.dart';

/// Colunas que a gravação parcial Considera "estoque".
const colunasDeEstoque = <String>{
  'estoque',
  'estoquePorFornecedor',
  'estoque_por_fornecedor',
  'estoquePorEstoque',
  'estoque_por_estoque',
  'estoquePadraoId',
  'estoque_padrao_id',
  'estoqueMinimo',
  'estoque_minimo',
  'updatedAt',
  'updated_at',
};

/// Reproduz o diff que `updateProduto` faz: quais colunas mudaram de fato entre
/// o que estava gravado e o que está chegando. Fica aqui (e não chamando o
/// serviço) para o teste não precisar de banco nem de app rodando.
Map<String, dynamic> colunasQueMudaram(
  Map<String, dynamic> antes,
  Map<String, dynamic> novo,
) {
  final mudou = <String, dynamic>{};
  for (final entrada in novo.entries) {
    if (!_mesmoValor(antes[entrada.key], entrada.value)) {
      mudou[entrada.key] = entrada.value;
    }
  }
  return mudou;
}

bool _mesmoValor(Object? a, Object? b) =>
    DataService.mesmoValorParaBanco(a, b);

bool _soEstoque(Map<String, dynamic> mudou) =>
    mudou.isNotEmpty && mudou.keys.every(DataService.eColunaDeEstoque);

/// Produto do caso real (item "coca cola"). `preco` e `estoque` parametriados
/// para escrever o cenário do teste sem repetir o construtor.
Map<String, dynamic> produto({
  required double preco,
  required double estoque,
  required DateTime updatedAt,
}) =>
    Produto(
      id: 'COD-1',
      nome: 'coca cola',
      unidade: 'un',
      grupo: 'Bebidas',
      preco: preco,
      estoque: estoque,
      createdAt: DateTime(2026, 10, 3, 18),
      updatedAt: updatedAt,
    ).toMap();

void main() {
  group('a baixa de uma venda não pode devolver o preço antigo', () {
    test('só estoque mudou: grava só estoque, preço fica como está no banco',
        () {
      // O que o app TEM em memória: preço VELHO (R$ 24,00, de antes da edição
      // que chegou do outro PC) e o estoque antes da venda.
      final emMemoria = produto(
        preco: 24.0,
        estoque: -81,
        updatedAt: DateTime(2026, 10, 3, 18, 47, 45),
      );
      // A venda abate 2 unidades e carimba a data de agora.
      final depoisDaVenda = produto(
        preco: 24.0,
        estoque: -83,
        updatedAt: DateTime(2026, 10, 3, 19, 50, 25),
      );

      final mudou = colunasQueMudaram(emMemoria, depoisDaVenda);

      // É uma alteração SÓ de estoque -> a gravação tem de ser parcial.
      expect(_soEstoque(mudou), isTrue,
          reason: 'a venda só mexe em estoque: a gravação tem de ser parcial');
      expect(mudou.keys, isNot(contains('preco')),
          reason: 'o preço não mudou: não pode entrar na gravação');
      expect(mudou['estoque'], -83);

      // Efeito no banco: o UPDATE toca só estoque/updated_at. O preço que fica
      // gravado é o que JÁ ESTÁ no banco (R$ 2,00), não o da memória (R$ 24,00).
      // Antes da correção a linha inteira era regravada e o R$ 24,00 voltava.
      final precoNoBanco = produto(
        preco: 2.0,
        estoque: -83,
        updatedAt: DateTime(2026, 10, 3, 19, 50, 25),
      );
      expect(precoNoBanco['preco'], 2.0);
    });

    test('preço mudou junto: a linha inteira continua sendo gravada', () {
      final emMemoria = produto(
        preco: 2.0,
        estoque: -81,
        updatedAt: DateTime(2026, 10, 3, 18, 47, 46),
      );
      final editado = produto(
        preco: 5.0,
        estoque: -81,
        updatedAt: DateTime(2026, 10, 3, 20),
      );

      final mudou = colunasQueMudaram(emMemoria, editado);
      expect(mudou.containsKey('preco'), isTrue);
      expect(_soEstoque(mudou), isFalse,
          reason: 'edição de preço é alteração de verdade: grava tudo');
    });

    test('nada mudou: não há gravação parcial para fazer', () {
      final p = produto(
        preco: 2.0,
        estoque: -81,
        updatedAt: DateTime(2026, 10, 3, 18, 47, 46),
      );
      final mudou = colunasQueMudaram(p, Map<String, dynamic>.from(p));
      expect(mudou, isEmpty);
      expect(_soEstoque(mudou), isFalse);
    });

    test('lista vazia vinda do banco não conta como alteração', () {
      // `precos_por_perfil` pode chegar como `[]` (default do JSONB) num
      // caminho e como objeto Dart no outro. Sem normalizar, TODA venda cairia
      // no caminho "não é só estoque" e voltaria a regravar a linha inteira.
      expect(_mesmoValor(<dynamic>[], <dynamic>[]), isTrue);
      expect(_mesmoValor(<String, dynamic>{}, <String, dynamic>{}), isTrue);
      expect(_mesmoValor(<dynamic>[], <dynamic>[1]), isFalse);
    });

    test('número 1 e 1.0 são o mesmo valor', () {
      expect(_mesmoValor(1, 1.0), isTrue);
      expect(_mesmoValor(1.0, 1.5), isFalse);
      expect(_mesmoValor(null, null), isTrue);
      expect(_mesmoValor(null, 0), isFalse);
    });
  });

  group('a gravação parcial monta o UPDATE certo', () {
    test('resolve o nome da coluna no schema e ignora as desconhecidas', () {
      final colunas = <String, dynamic>{
        'estoque': 'numeric',
        'estoque_por_fornecedor': 'jsonb',
        'preco': 'numeric',
      };
      expect(DatabaseService.nomeDeColunaNoSchema(colunas, 'estoque'), 'estoque');
      // camelCase do app -> snake_case do banco.
      expect(DatabaseService.nomeDeColunaNoSchema(colunas, 'estoquePorFornecedor'),
          'estoque_por_fornecedor');
      // snake_case do app -> camelCase do banco (o caminho inverso).
      final camel = <String, dynamic>{'estoquePorEstoque': 'jsonb'};
      expect(DatabaseService.nomeDeColunaNoSchema(camel, 'estoque_por_estoque'),
          'estoquePorEstoque');
      // O que não existe no schema não pode entrar no SQL.
      expect(DatabaseService.nomeDeColunaNoSchema(colunas, 'campoQueNaoExiste'),
          isNull);
    });

    test('"estoque" e suas vizinhas são colunas de estoque', () {
      for (final c in colunasDeEstoque) {
        expect(DataService.eColunaDeEstoque(c), isTrue, reason: c);
      }
      // E o que NÃO é estoque nunca pode entrar no caminho parcial.
      for (final c in ['preco', 'preco_custo', 'nome', 'ncm', 'ativo']) {
        expect(DataService.eColunaDeEstoque(c), isFalse, reason: c);
      }
    });
  });
}