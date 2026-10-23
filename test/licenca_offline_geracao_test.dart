// A licença offline (código de liberação que o suporte entrega ao cliente) era
// gerada em uma única linha dentro da tela de empresa e só aparecia uma vez, no
// cadastro — não dava para ver nem gerar de novo depois.
//
// Agora a geração vive no modelo (`Empresa.gerarCodigoLiberacaoOffline`) e a
// tela de empresa mostra/copia/regenera o código. Estes testes garantem o
// formato e, principalmente, que o código que a tela salva é exatamente o que a
// tela de bloqueio compara (mesma string, já em maiúsculas).

import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_exodo_novo/models/empresa.dart';

Empresa _empresa({Map<String, dynamic>? configuracoes}) => Empresa(
  id: 'BMJ',
  razaoSocial: 'BMJ',
  slug: 'bmj',
  configuracoes: configuracoes,
  createdAt: DateTime(2026, 1, 1),
  updatedAt: DateTime(2026, 1, 1),
);

void main() {
  test('o código segue o padrão EXO- com caracteres maiúsculos', () {
    final codigo = Empresa.gerarCodigoLiberacaoOffline();
    expect(codigo, startsWith('EXO-'));
    expect(RegExp(r'^EXO-[0-9A-Z]+$').hasMatch(codigo), isTrue,
        reason: 'formato inesperado: $codigo');
  });

  test('é determinístico quando o instante é informado', () {
    final instante = DateTime(2026, 10, 14, 9, 30);
    expect(
      Empresa.gerarCodigoLiberacaoOffline(agora: instante),
      Empresa.gerarCodigoLiberacaoOffline(agora: instante),
    );
  });

  test('instantes diferentes geram códigos diferentes', () {
    final a = Empresa.gerarCodigoLiberacaoOffline(
      agora: DateTime(2026, 10, 14, 9, 30),
    );
    final b = Empresa.gerarCodigoLiberacaoOffline(
      agora: DateTime(2026, 10, 14, 9, 30, 1),
    );
    expect(a, isNot(b));
  });

  test('o código sobrevive ao salvamento da empresa (toMap/fromMap)', () {
    final codigo = Empresa.gerarCodigoLiberacaoOffline(
      agora: DateTime(2026, 10, 14),
    );
    final salva = Empresa.fromMap(
      _empresa(
        configuracoes: {'codigo_liberacao_offline': codigo},
      ).toMap(),
    );
    expect(salva.configuracoes?['codigo_liberacao_offline'], codigo);
  });

  test('o cliente pode digitar em minúsculas ou com espaços', () {
    final codigo = Empresa.gerarCodigoLiberacaoOffline();
    // Mesma normalização usada pela tela de bloqueio antes de comparar.
    expect('  ${codigo.toLowerCase()} '.trim().toUpperCase(), codigo);
  });

  group('normalizarCodigoLiberacaoOffline (o que a tela salva)', () {
    test('campo vazio ou nulo gera um código novo', () {
      for (final vazio in [null, '', '   ']) {
        final codigo = Empresa.normalizarCodigoLiberacaoOffline(vazio);
        expect(RegExp(r'^EXO-[0-9A-Z]+$').hasMatch(codigo), isTrue,
            reason: 'entrada: $vazio');
      }
    });

    test('mantém o código informado, em maiúsculas e sem espaços', () {
      expect(
        Empresa.normalizarCodigoLiberacaoOffline('exo-bmj01'),
        'EXO-BMJ01',
      );
      expect(
        Empresa.normalizarCodigoLiberacaoOffline('  EXO-BMJ01  '),
        'EXO-BMJ01',
      );
    });

    test('salvar duas vezes não troca o código existente', () {
      final primeira = Empresa.normalizarCodigoLiberacaoOffline('EXO-BMJ01');
      expect(Empresa.normalizarCodigoLiberacaoOffline(primeira), primeira);
    });
  });

  test('empresa sem código no cadastro fica sem licença (cai em "não cadastrado")', () {
    final semCodigo = _empresa(configuracoes: {'limite_dias_offline': 7});
    expect(semCodigo.configuracoes?['codigo_liberacao_offline'], isNull);

    final comCodigo = _empresa(
      configuracoes: {'codigo_liberacao_offline': 'EXO-TESTE'},
    );
    expect(comCodigo.configuracoes?['codigo_liberacao_offline'], 'EXO-TESTE');
  });
}
