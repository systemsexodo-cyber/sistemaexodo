// Reenvio de NFC-e: o número só avança depois de duplicidade 539.
import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_exodo_novo/services/nfce_duplicidade_helper.dart';

void main() {
  test('reenvio sem duplicidade reusa o número original', () {
    expect(NfceDuplicidadeHelper.numeroOriginalReenvio('142'), 142);
    expect(NfceDuplicidadeHelper.numeroOriginalReenvio(' 7 '), 7);
    expect(NfceDuplicidadeHelper.numeroOriginalReenvio('0'), isNull);
    expect(NfceDuplicidadeHelper.numeroOriginalReenvio(''), isNull);
  });

  test('pulo só depois da 539, para a frente do recusado', () {
    expect(
      NfceDuplicidadeHelper.proximoAposDuplicidade(numeroTentado: 100),
      101,
    );
    expect(
      NfceDuplicidadeHelper.proximoAposDuplicidade(
        numeroTentado: 100,
        duplicados: const [100, 103],
        ocupados: const [101, 102],
      ),
      104,
    );
  });

  test('não desce para preencher buraco antigo após duplicidade', () {
    expect(
      NfceDuplicidadeHelper.proximoAposDuplicidade(
        numeroTentado: 200,
        ocupados: const [198],
        numeroInicial: 1,
      ),
      201,
    );
  });
}
