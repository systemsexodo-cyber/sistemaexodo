// Teste: o Portal do Contador não pode exibir rascunhos de emissão (`pend-`).
//
// Reproduz o bug relatado: a nota emitida aparece como AUTORIZADA e, logo depois,
// também como "PENDENTE" — o rascunho `pend-<millis>` que o app grava antes de
// falar com a SEFAZ e apaga ao autorizar. Quando esse DELETE falha (app fechado,
// queda de rede), o rascunho fica para trás e o portal o mostrava como se fosse
// outra nota.
//
// O teste cria o próprio rascunho na nuvem e o remove no final, então roda
// contra os dados reais sem deixar sujeira (e sem depender de estado prévio).
//
// Rodar: flutter test test/portal_contador_rascunho_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sistema_exodo_novo/services/portal_contador_service.dart';
import 'package:sistema_exodo_novo/services/supabase_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Empresa (CNPJ 04.829.400/0001-65) liberada para o contador.
  const empresaId = '22ae2c16-a730-43f3-a4f9-19f105eb0d13';

  test('portal ignora rascunho pend- e não duplica a nota autorizada',
      () async {
    // O `flutter test` troca o HttpClient por um mock que devolve 400 em tudo:
    // sem isso NENHUMA chamada real à nuvem acontece (o teste passaria vazio).
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({});

    await SupabaseService.initialize();
    expect(SupabaseService.isAvailable, isTrue, reason: 'sem Supabase');

    final client = Supabase.instance.client;

    // Rascunho igual ao que o app cria ao iniciar uma emissão: mesmo número e
    // série da nota já autorizada, status pendente e SEM chave de acesso.
    final idRascunho = 'pend-${DateTime.now().millisecondsSinceEpoch}';
    await client.from('nfces').insert({
      'id': idRascunho,
      'numero': '8',
      'serie': '1',
      'status': 'pendente',
      'valor_total': 10.0,
      'data_emissao': DateTime.now().toUtc().toIso8601String(),
      'empresa_id': empresaId,
    });
    addTearDown(() async {
      // Nunca deixar rascunho de teste na nuvem.
      await client.from('nfces').delete().eq('id', idRascunho);
      final sobrou = await client.from('nfces').select('id').eq('id', idRascunho);
      print('limpeza: ${(sobrou as List).isEmpty ? "rascunho removido" : "AINDA EXISTE"}');
    });

    final gravado = await client
        .from('nfces')
        .select('id,numero,serie,status')
        .eq('id', idRascunho);
    print('rascunho gravado na tabela: $gravado');
    expect(gravado, isNotEmpty, reason: 'o rascunho precisa estar na nuvem');

    final sessao = await PortalContadorService.instance.login(
      cnpj: '04829400000165',
      senha: 'Exodo@2026',
    );

    final documentos = await PortalContadorService.instance.listarDocumentos(
      empresaIds: sessao.empresas.map((e) => e.id).toList(),
      inicio: DateTime(2026, 9, 1),
      fim: DateTime(2026, 9, 30),
    );

    for (final d in documentos) {
      print('${d.tipo.titulo} | Nº ${d.numero} Série ${d.serie} | '
          '${d.status} | ${d.identificacao} | R\$ ${d.valor}');
    }

    // 1) Nenhum rascunho pode aparecer.
    final expostos = documentos.where((d) => d.id.startsWith('pend-')).toList();
    expect(expostos, isEmpty,
        reason: 'rascunho não é documento fiscal e não pode ser listado');

    // 2) A nota Nº 8 Série 1 (autorizada) aparece UMA única vez.
    final nota8 =
        documentos.where((d) => d.numero == '8' && d.serie == '1').toList();
    expect(nota8, hasLength(1), reason: 'a nota 8 apareceu duplicada');
    expect(nota8.first.status, 'autorizada');
    expect(nota8.first.chave.length, 44);
  }, timeout: const Timeout(Duration(minutes: 3)));
}
