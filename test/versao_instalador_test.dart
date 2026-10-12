// Teste que amarra a versão do instalador à versão do app.
//
// Por que existe: as duas versões vivem em arquivos diferentes
// (Instalador_Exodo_Completo.iss e lib/services/app_update_service.dart) e
// nada as ligava. O resultado ja aconteceu: o instalador dizia 1.0.43 enquanto
// o app embutido ainda era um build de semanas antes, com a versao antiga — e
// so apareceu porque alguem comparou as datas na mao.
//
// Se este teste quebrar, a solucao e subir as DUAS para o mesmo numero (nao
// editar este teste).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:sistema_exodo_novo/services/app_update_service.dart';

String? _versaoDoInstalador() {
  final arquivo = File('Instalador_Exodo_Completo.iss');
  if (!arquivo.existsSync()) {
    return null;
  }
  final regra = RegExp(r'#define\s+MyAppVersion\s+"([^"]+)"');
  return regra.firstMatch(arquivo.readAsStringSync())?.group(1);
}

void main() {
  test('a versao do instalador e a versao do app sao a mesma', () {
    final doInstalador = _versaoDoInstalador();
    expect(
      doInstalador,
      isNotNull,
      reason: 'Instalador_Exodo_Completo.iss nao tem "#define MyAppVersion"'
          ' (ou o arquivo sumiu da raiz do projeto)',
    );
    expect(
      doInstalador,
      AppUpdateService.currentAppVersion,
      reason: 'Suba a versao nos DOIS arquivos: '
          'Instalador_Exodo_Completo.iss (MyAppVersion) e '
          'app_update_service.dart (currentAppVersion).',
    );
  });

  test('a versao tem o formato x.y.z', () {
    expect(
      AppUpdateService.currentAppVersion,
      matches(RegExp(r'^\d+\.\d+\.\d+$')),
      reason: 'o app compara versoes numericamente: '
          '"1.0.44" funciona, "v1.0.44" quebra a comparacao',
    );
  });
}