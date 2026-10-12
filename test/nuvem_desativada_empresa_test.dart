import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_exodo_novo/models/empresa.dart';

void main() {
  group('Toggle de nuvem por empresa', () {
    test('deve respeitar a flag de nuvem temporariamente desativada', () {
      final empresaDesativada = Empresa(
        id: 'empresa-1',
        razaoSocial: 'Loja Teste',
        slug: 'loja-teste',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        configuracoes: {'nuvem_ativa': false},
      );

      final empresaAtiva = Empresa(
        id: 'empresa-2',
        razaoSocial: 'Loja Ativa',
        slug: 'loja-ativa',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        configuracoes: {'nuvem_ativa': true},
      );

      expect(empresaDesativada.nuvemAtiva, isFalse);
      expect(empresaAtiva.nuvemAtiva, isTrue);
    });
  });
}
