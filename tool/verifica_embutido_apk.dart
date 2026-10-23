// Prova de que o CELULAR alcanca a nuvem usando SOMENTE o config embutido em
// `assets/app.env` (é o que vai dentro do APK).
//
// No Android não existe `.env.neon` no disco: o valor sai do mapa embutido, via
// `EnvConfig.carregarDoAsset()` -> `NeonConfig.definirEmbutido()`. Este script
// reproduz exatamente esse caminho (é Dart puro, sem Flutter).
//
// Rode na raiz do projeto, com o `.env.neon` FORA do caminho (o runner faz isso):
//
//   dart run tool/verifica_embutido_apk.dart
// ignore_for_file: avoid_print

import 'dart:io';

import 'package:sistema_exodo_novo/services/neon_client.dart';
import 'package:sistema_exodo_novo/services/neon_config.dart';

Future<void> main() async {
  print('=' * 76);
  print('Neon — config embutido do APK (assets/app.env)');
  print('=' * 76);

  final arquivo = File('assets/app.env');
  if (!arquivo.existsSync()) {
    print('assets/app.env não encontrado');
    exit(2);
  }

  // Mesmo caminho do app: lê o arquivo empacotado e injeta como "embutido".
  NeonConfig.definirEmbutido(NeonConfig.parseEnv(arquivo.readAsStringSync()));

  print(
    'serviços resolvidos: '
    '${NeonConfig.servicosConfigurados.isEmpty ? "(nenhum)" : NeonConfig.servicosConfigurados.join(", ")}',
  );
  print('Data API : ${NeonConfig.dataApiUrl.isEmpty ? "(vazio)" : "definida"}');
  print('Auth     : ${NeonConfig.authBaseUrl.isEmpty ? "(vazio)" : "definida"}');
  print('Storage  : ${NeonConfig.storageDisponivel}');
  print('Postgres direto: ${NeonConfig.postgresDisponivel}');

  // Se o `.env.neon` do PC tivesse sido lido, o Postgres direto apareceria
  // configurado (ele só está lá, não aqui). Isso garante que este teste mede o
  // caminho do celular, e não o do PC.
  if (NeonConfig.postgresDisponivel) {
    print('');
    print('!! o .env.neon do PC também foi lido — o teste NÃO está isolado.');
    exit(1);
  }

  if (!NeonConfig.dataApiDisponivel) {
    print('');
    print('!! sem NEON_DATA_API_URL no config embutido.');
    exit(1);
  }

  final nuvem = NeonClient.instance;
  await nuvem.inicializar();
  final empresas = await nuvem.from('empresas').select('id').limit(5);
  nuvem.auth.parar();

  print('');
  print(
    'SELECT em empresas usando só o config do APK: ${empresas.length} linha(s)',
  );
  print(empresas.isEmpty
      ? 'resultado: FALHOU (nenhuma linha)'
      : 'resultado: OK');
  print('=' * 76);
  exit(empresas.isEmpty ? 1 : 0);
}
