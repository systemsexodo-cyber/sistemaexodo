// VÍNCULO MATRIZ / FILIAL — regra de visibilidade das empresas.
//
// O grupo é formado por uma matriz (sem `empresa_matriz_id`) e suas filiais
// (com `empresa_matriz_id` apontando para a matriz). A permissão do usuário é
// que decide se ele continua vendo só a própria empresa ou se passa a ver o
// grupo inteiro. Os DADOS continuam separados por empresa — isto só muda a
// lista que aparece no login/Portal.

import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_exodo_novo/models/empresa.dart';
import 'package:sistema_exodo_novo/models/usuario.dart';
import 'package:sistema_exodo_novo/services/auth_service.dart';

void main() {
  Empresa empresa(String id, {String? matrizId, bool ativo = true}) {
    final agora = DateTime(2026, 1, 1);
    return Empresa(
      id: id,
      razaoSocial: 'Empresa $id',
      nomeFantasia: 'Empresa $id',
      slug: 'empresa-$id',
      ativo: ativo,
      createdAt: agora,
      updatedAt: agora,
      configuracoes: matrizId == null
          ? null
          : <String, dynamic>{'empresa_matriz_id': matrizId},
    );
  }

  Usuario usuario(
    String? empresaId, {
    bool acessoMultiempresa = false,
    String email = 'dono@loja.com',
  }) {
    final agora = DateTime(2026, 1, 1);
    return Usuario(
      id: 'u1',
      nome: 'Dono',
      email: email,
      senha: '123',
      empresaId: empresaId,
      acessoMultiempresa: acessoMultiempresa,
      createdAt: agora,
      updatedAt: agora,
    );
  }

  List<String> ids(List<Empresa> empresas) =>
      empresas.map((e) => e.id).toList();

  final empresas = [
    empresa('A'), // matriz do grupo 1
    empresa('B', matrizId: 'A'), // filial do grupo 1
    empresa('C', matrizId: 'A'), // filial do grupo 1
    empresa('D'), // empresa independente
    empresa('E', matrizId: 'A', ativo: false), // filial inativa
  ];

  test('sem a permissão, vê apenas a própria empresa', () {
    final visiveis = AuthService.empresasVisiveisPara(
      usuario: usuario('B'),
      empresas: empresas,
    );
    expect(ids(visiveis), ['B']);
  });

  test('com a permissão, a filial vê a matriz e as irmãs ativas', () {
    final visiveis = AuthService.empresasVisiveisPara(
      usuario: usuario('B', acessoMultiempresa: true),
      empresas: empresas,
    );
    expect(ids(visiveis), ['A', 'B', 'C']);
  });

  test('com a permissão, a matriz vê as filiais ativas', () {
    final visiveis = AuthService.empresasVisiveisPara(
      usuario: usuario('A', acessoMultiempresa: true),
      empresas: empresas,
    );
    expect(ids(visiveis), ['A', 'B', 'C']);
  });

  test('empresa independente com a permissão não puxa outro grupo', () {
    final visiveis = AuthService.empresasVisiveisPara(
      usuario: usuario('D', acessoMultiempresa: true),
      empresas: empresas,
    );
    expect(ids(visiveis), ['D']);
  });

  test('filial de filial pertence ao mesmo grupo da raiz', () {
    final comCorrente = [
      ...empresas.where((e) => e.id != 'C'),
      empresa('C', matrizId: 'B'),
    ];
    final visiveis = AuthService.empresasVisiveisPara(
      usuario: usuario('C', acessoMultiempresa: true),
      empresas: comCorrente,
    );
    expect(ids(visiveis), ['A', 'B', 'C']);
  });

  test('conta de suporte "user" continua vendo todas as ativas', () {
    final visiveis = AuthService.empresasVisiveisPara(
      usuario: usuario(null, email: 'user'),
      empresas: empresas,
    );
    expect(ids(visiveis), ['A', 'B', 'C', 'D']);
  });

  test('sem empresa vinculada, a lista fica vazia', () {
    final visiveis = AuthService.empresasVisiveisPara(
      usuario: usuario(null, acessoMultiempresa: true),
      empresas: empresas,
    );
    expect(visiveis, isEmpty);
  });
}
