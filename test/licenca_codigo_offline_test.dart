// O código curto de liberação offline (EXO-OFF-XXXXXX-XXXXXX) é a contingência
// para quando a nuvem de licenças não responde. Estes testes usam códigos
// gerados pelo `tools/licencas/gerar_codigo_offline.js` e garantem que o app
// confere o mesmo MAC, prende o código ao computador e recusa adulteração.

import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_exodo_novo/services/licenca_instalacao_service.dart';

const _maquina = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

void main() {
  test('aceita o código emitido pelo gerador e devolve a validade', () {
    final validade = LicencaInstalacaoService.validarCodigoOffline(
      'EXO-OFF-02EYCZ-SQFRGQ',
      _maquina,
    );
    // O gerador grava o dia 01/12/2026; o código vale até o fim dele.
    expect(validade, DateTime.utc(2026, 12, 2));
  });

  test('aceita o cliente digitando em minúsculas, com espaços ou sem hífens', () {
    for (final digitado in [
      'exo-off-02eycz-sqfrgq',
      '  EXO-OFF-02EYCZ-SQFRGQ  ',
      'EXO OFF 02EYCZ SQFRGQ',
    ]) {
      expect(
        LicencaInstalacaoService.validarCodigoOffline(digitado, _maquina),
        DateTime.utc(2026, 12, 2),
        reason: 'entrada: $digitado',
      );
    }
  });

  test('código de outro computador não libera este', () {
    expect(
      LicencaInstalacaoService.validarCodigoOffline(
        'EXO-OFF-02EYCZ-SQFRGQ',
        'b000000000000000000000000000000000000000000000000000000000000000',
      ),
      isNull,
    );
  });

  test('um caractere trocado invalida o código', () {
    expect(
      LicencaInstalacaoService.validarCodigoOffline(
        'EXO-OFF-02EYCZ-SQFRGR',
        _maquina,
      ),
      isNull,
    );
  });

  test('texto que não é código não é aceito', () {
    for (final entrada in ['', 'EXO-ABCD-EFGH-IJKL', 'EXO-OFF-123']) {
      expect(
        LicencaInstalacaoService.validarCodigoOffline(entrada, _maquina),
        isNull,
        reason: 'entrada: "$entrada"',
      );
    }
  });

  test('a validade cresce com o dia assinado', () {
    final validade = LicencaInstalacaoService.validarCodigoOffline(
      'EXO-OFF-02N2WX-13FF22',
      _maquina,
    );
    // Dia 15/06/2027 no gerador.
    expect(validade, DateTime.utc(2027, 6, 16));
  });
}
