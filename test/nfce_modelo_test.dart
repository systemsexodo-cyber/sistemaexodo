// Teste do que separa NF-e (DANFE) de NFC-e dentro do mesmo tipo NFCe.
//
// A tabela `nfces` (local e Supabase) NÃO tem coluna `modelo`: ao recarregar as
// notas, tudo volta com `modelo == null` — inclusive DANFE modelo 55. Sem olhar
// a chave de acesso, a DANFE entrava no histórico de NFC-e (e no total fiscal).
import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_exodo_novo/models/nfce.dart';

/// Chave real do banco desta máquina (nota 9, série 1, modelo 55).
const _chaveNFe = '35260904829400000165550010000000091632272270';

void main() {
  NFCe nota({int? modelo, String? chave, String numero = '1'}) => NFCe(
        id: 'id-$numero',
        numero: numero,
        serie: '1',
        dataEmissao: DateTime(2026, 9, 21),
        empresaId: '1',
        itens: const [],
        valorTotal: 10,
        pagamentos: const [],
        modelo: modelo,
        chaveAcesso: chave,
        status: 'autorizada',
        createdAt: DateTime(2026, 9, 21),
        updatedAt: DateTime(2026, 9, 21),
      );

  test('chave de 44 dígitos revela o modelo na posição 21-22', () {
    expect(NFCe.modeloDaChave(_chaveNFe), '55');
    // Mesma chave, só trocando o modelo: é o que uma NFC-e teria.
    final chaveNFCe = '${_chaveNFe.substring(0, 20)}65${_chaveNFe.substring(22)}';
    expect(NFCe.modeloDaChave(chaveNFCe), '65');
  });

  test('chave inválida ou ausente não inventa modelo', () {
    expect(NFCe.modeloDaChave(null), isNull);
    expect(NFCe.modeloDaChave(''), isNull);
    expect(NFCe.modeloDaChave('352609'), isNull);
    // Com máscara/separadores a chave continua sendo lida.
    expect(NFCe.modeloDaChave('3526 0904 8294 0000 0165 5500 1000 0000 0916 3227 2270'),
        '55');
  });

  test('nota vinda do banco (modelo nulo) é reconhecida como NF-e pela chave', () {
    final danfe = nota(chave: _chaveNFe, numero: '9');
    expect(danfe.modelo, isNull, reason: 'o banco não guarda a coluna modelo');
    expect(danfe.modeloEfetivo, 55);
    expect(danfe.ehNFe, isTrue);
    expect(danfe.ehNFCe, isFalse);
  });

  test('nota vinda do banco (modelo nulo) com chave 65 é NFC-e', () {
    final nfce = nota(chave: '${_chaveNFe.substring(0, 20)}65${_chaveNFe.substring(22)}');
    expect(nfce.modeloEfetivo, 65);
    expect(nfce.ehNFCe, isTrue);
    expect(nfce.ehNFe, isFalse);
  });

  test('nota em contingência (sem chave) continua sendo NFC-e', () {
    final contingencia = nota(modelo: null, chave: null);
    expect(contingencia.modeloEfetivo, isNull);
    expect(contingencia.ehNFCe, isTrue,
        reason: 'nota sem chave não pode desaparecer do histórico de NFC-e');
  });

  test('o campo modelo continua mandando quando existe', () {
    final nfe = nota(modelo: 55, chave: null); // NF-e sem chave (rejeitada)
    expect(nfe.ehNFe, isTrue);

    final nfce = nota(modelo: 65, chave: _chaveNFe); // campo ganha da chave
    expect(nfce.modeloEfetivo, 65);
    expect(nfce.ehNFCe, isTrue);
  });

  test('histórico de NFC-e ficaria só com as notas 65 e as sem chave', () {
    final lista = [
      nota(numero: '9', chave: _chaveNFe), // DANFE
      nota(numero: '8', chave: '${_chaveNFe.substring(0, 20)}55${_chaveNFe.substring(22)}'), // DANFE
      nota(numero: '10', chave: '${_chaveNFe.substring(0, 20)}65${_chaveNFe.substring(22)}'),
      nota(numero: '0', chave: null, modelo: null), // contingência
    ];

    final visiveis = lista.where((n) => n.ehNFCe).map((n) => n.numero).toList();
    final ocultas = lista.where((n) => n.ehNFe).length;

    expect(visiveis, ['10', '0']);
    expect(ocultas, 2);
  });
}
