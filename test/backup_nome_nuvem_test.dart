// O nome que o backup local usa na NUVEM precisa ser aceito pelo Storage.
//
// O Storage do Supabase recusa chaves com acento — responde 400 "Invalid key".
// Era essa a razão de o backup de "É O BICHO PETSHOP" nunca chegar à nuvem: o
// arquivo local se chama `É_O_BICHO_PETSHOP_empresa_...sql` e o nome montado com
// o nome da empresa era recusado no upload (a pasta dessa empresa na nuvem
// estava parada, com os últimos arquivos de 15/09).
//
// Aqui: (1) a função que limpa o nome tira o acento; (2) o upload com o nome
// limpo funciona de verdade; (3) o arquivo de teste é removido no fim.
//
// Rodar: flutter test test/backup_nome_nuvem_test.dart

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sistema_exodo_novo/services/backup_restore_service.dart';
import 'package:sistema_exodo_novo/supabase_config.dart';

void main() {
  // Pasta dentro do bucket 'dumps' que não é de nenhuma empresa: nada aqui
  // aparece nas listas do app e tudo é apagado no fim do teste.
  const pastaTeste = '__teste_nome_nuvem__';

  test('o nome do backup na nuvem perde o acento (Storage recusa chave acentuada)',
      () async {
    final client = SupabaseClient(SupabaseConfig.url, SupabaseConfig.anonKey);
    final storage = client.storage.from('dumps');

    const nomeLocal = 'É_O_BICHO_PETSHOP_empresa_2026-09-25_1031.sql';
    final nomeNuvem =
        BackupRestoreService.nomeNaNuvemPara(nomeLocal, 'E_O_BICHO_PETSHOP', DateTime.now());
    expect(nomeNuvem, 'E_O_BICHO_PETSHOP_empresa_2026-09-25_1031.sql');

    // 1. O nome cru, com acento, é RECUSADO pelo Storage (é o bug de origem).
    var recusouOAcento = false;
    try {
      await storage.uploadBinary('$pastaTeste/$nomeLocal',
          Uint8List.fromList([1, 2, 3]),
          fileOptions: const FileOptions(upsert: true));
    } catch (e) {
      recusouOAcento = true;
      print('Storage recusou o nome com acento (esperado): $e');
    }
    expect(recusouOAcento, isTrue,
        reason: 'se o Storage passou a aceitar acento, o nome limpo pode ser revisto');

    // 2. Com o nome limpo, o mesmo upload funciona e o arquivo aparece na lista.
    await storage.uploadBinary('$pastaTeste/$nomeNuvem',
        Uint8List.fromList([1, 2, 3]),
        fileOptions: const FileOptions(upsert: true));
    final listados = (await storage.list(path: '$pastaTeste/'))
        .map((f) => f.name)
        .toList();
    print('arquivos aceitos na nuvem: $listados');
    expect(listados, contains(nomeNuvem));

    // 3. Limpeza: o teste não deixa nada no bucket.
    await storage.remove(['$pastaTeste/$nomeNuvem']);
    final depois = (await storage.list(path: '$pastaTeste/')).map((f) => f.name).toList();
    expect(depois, isEmpty, reason: 'o teste precisa limpar o que subiu');
  }, timeout: const Timeout(Duration(minutes: 3)));
}
