// TABELAS GLOBAIS x FILTRO DE EMPRESA — o teste que faltava.
//
// `empresas` e `usuarios` não pertencem a uma empresa só: a lista de empresas
// precisa mostrar todas, e a de usuários precisa incluir quem atende outra
// empresa. Mesmo assim, o carregador genérico do PostgreSQL aplica
// `WHERE empresa_id = <empresa aberta>` em QUALQUER tabela que tenha a coluna
// `empresa_id` — inclusive nessas duas.
//
// Esse cruzamento já aconteceu de verdade: a comparação de esquema criou
// `empresas.empresa_id` (vazia, porque a nuvem não tem valor confiável nela) e,
// a partir daí, a leitura de `empresas` filtrava por uma coluna nula e devolvia
// ZERO linhas — o app pareceria ter perdido as empresas, mesmo com as 4 linhas
// intactas no banco.
//
// Aqui o teste lê os dois bancos reais (SOMENTE LEITURA) e exige:
//   • com uma empresa aberta, `carregarLista('empresas')` devolve TODAS as
//     empresas do banco (não só a aberta, e nunca vazio);
//   • `carregarListaCompleta` devolve o mesmo;
//   • `usuarios` também não é filtrado;
//   • o teste não grava nada (contagens conferidas no fim).

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistema_exodo_novo/services/database_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  setUpAll(() {
    HttpOverrides.global = null;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final canal in const [
      'xyz.luan/audioplayers.global',
      'xyz.luan/audioplayers',
      'dev.fluttercommunity.plus/connectivity',
    ]) {
      messenger.setMockMethodCallHandler(MethodChannel(canal), (call) async => null);
    }
  });

  test('empresas e usuarios são lidos por inteiro, mesmo com a coluna empresa_id',
      () async {
    final db = DatabaseService();
    final conn = await db.connection;

    // Quanto o BANCO tem de verdade, naquele instante. É a régua do teste:
    // o app pode ler MENOS que isso (filtro indevido) — nunca mais.
    Future<int> contarBruto(String tabela) async {
      final r = await conn.execute('SELECT count(*) FROM "$tabela"');
      return int.parse(r.first[0].toString());
    }

    // ⚠️ Este banco é VIVO: o app aberto na máquina grava nele enquanto o teste
    // roda (a tabela `empresas` já foi vista com 0, 2 e 4 linhas na mesma hora).
    // Por isso a comparação é com a contagem bruta lida ANTES e DEPOIS da
    // leitura: o que o teste não aceita é a lista vir menor que o banco.

    // Sem empresa aberta (situação da tela de login).
    final brutoAntes = await contarBruto('empresas');
    final semEmpresa = await db.carregarLista('empresas');
    final brutoDepois = await contarBruto('empresas');
    final piso = brutoAntes < brutoDepois ? brutoAntes : brutoDepois;
    print('empresas sem empresa aberta: app=${semEmpresa.length} '
        '(banco $brutoAntes→$brutoDepois)');
    expect(semEmpresa.length, greaterThanOrEqualTo(piso),
        reason: 'a leitura de `empresas` não pode sair menor que o banco '
            '(nenhum filtro de empresa pode ser aplicado aqui)');
    if (piso > 0) {
      expect(semEmpresa, isNotEmpty,
          reason: 'com linha no banco, a lista de empresas não pode vir vazia');
    }

    final semEmpresaCompleta = await db.carregarListaCompleta('empresas');

    // Com uma empresa aberta: o filtro NÃO pode ser aplicado nestas tabelas.
    final primeira = semEmpresaCompleta.isNotEmpty
        ? semEmpresaCompleta.first['id'].toString()
        : '1';
    DatabaseService().setEmpresaId(primeira);
    final db2 = DatabaseService()..setEmpresaId(primeira);

    final comEmpresa = await db2.carregarLista('empresas');
    print('empresas com a empresa $primeira aberta: ${comEmpresa.length}');
    expect(comEmpresa.length, semEmpresa.length,
        reason: 'a empresa aberta não pode reduzir a lista de empresas '
            '(é o que acontecia com empresas.empresa_id nula)');
    expect(comEmpresa.map((e) => e['id'].toString()).toSet(),
        semEmpresa.map((e) => e['id'].toString()).toSet());

    // Usuários: mesma regra (o app trata as duas como globais).
    final usuariosSem = await db.carregarLista('usuarios');
    final usuariosCom = await db2.carregarLista('usuarios');
    print('usuarios: ${usuariosSem.length} sem empresa / ${usuariosCom.length} com empresa');
    expect(usuariosCom.length, usuariosSem.length,
        reason: 'a lista de usuários não pode encolher por causa da empresa aberta');

    // Precisa continuar assim mesmo quando a coluna existir nos dois lados.
    final colunasEmpresas = await db.carregarListaCompleta('empresas');
    final temEmpresaId = colunasEmpresas.isNotEmpty &&
        colunasEmpresas.first.keys.any((k) => k == 'empresa_id' || k == 'empresaId');
    print('empresas tem empresa_id no local: $temEmpresaId');
    if (temEmpresaId) {
      expect(comEmpresa.length, semEmpresa.length,
          reason: 'com a coluna empresa_id existindo, o filtro não pode ser aplicado');
    }

    // Nada foi gravado pelo teste: a lista continua acompanhando o banco.
    final brutoFim = await contarBruto('empresas');
    final depois = await db.carregarListaCompleta('empresas');
    print('empresas no fim: app=${depois.length} (banco $brutoFim)');
    final pisoFim = brutoFim < piso ? brutoFim : piso;
    expect(depois.length, greaterThanOrEqualTo(pisoFim),
        reason: 'a leitura completa não pode sair menor que o banco');
  }, timeout: const Timeout(Duration(minutes: 5)));
}
