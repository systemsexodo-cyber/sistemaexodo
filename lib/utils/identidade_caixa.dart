/// Quem está usando cada NOME DE CAIXA — o registro que evita dois computadores
/// com o MESMO nome.
///
/// O nome do caixa é configuração LOCAL (fica no banco da máquina; o
/// sincronizador não a leva para a nuvem). Isso funciona bem até alguém digitar
/// o mesmo nome nas duas máquinas: aí as duas sequências voltam a andar juntas e
/// a venda sai repetida — exatamente o problema que a numeração por caixa
/// resolveu. Para avisar ANTES disso, cada máquina publica o próprio nome na
/// nuvem (evento [eventoNaNuvem] em `sync_logs`, com o nome em `detalhes`) e
/// depois lê o nome das outras: nenhuma tabela ou coluna nova é necessária.
///
/// Aqui ficam só as REGRAS (quem usa o quê), separadas de rede e banco, para
/// poderem ser conferidas por teste.
library;

import 'numeracao_venda.dart';

class IdentidadeCaixa {
  IdentidadeCaixa._();

  /// Evento gravado em `sync_logs` cada vez que uma máquina publica o nome.
  static const String eventoNaNuvem = 'caixa_identificado';

  /// Última publicação de cada computador: `{nome do PC: nome do caixa}`.
  ///
  /// [eventos] chega da nuvem do MAIS RECENTE para o mais antigo, então a
  /// primeira publicação de um PC é o nome atual dele: um PC que era `CX1` e
  /// virou `CX2` aparece como `CX2` — senão o aviso acusaria um nome já
  /// abandonado. Publicação sem nome (caixa removido) entra como texto vazio,
  /// de propósito: quem apagou o nome não está ocupando prefixo nenhum.
  static Map<String, String> ultimoNomePorPc(
    Iterable<Map<String, dynamic>> eventos,
  ) {
    final porPc = <String, String>{};
    final vistos = <String>{};
    for (final evento in eventos) {
      final pc = (evento['pc_name'] ?? '').toString().trim();
      // Case-insensitive: o hostname do Windows chega em maiúsculas, mas duas
      // grafias do mesmo PC não podem virar "duas máquinas".
      if (pc.isEmpty || !vistos.add(pc.toUpperCase())) continue;
      porPc[pc] =
          NumeracaoVenda.normalizarCaixa(evento['detalhes']?.toString()) ?? '';
    }
    return porPc;
  }

  /// Computadores (≠ [meuPc]) cujo nome de caixa ATUAL é [nome].
  ///
  /// Lista vazia = o nome está livre (ninguém publicou, ninguém usa esse nome ou
  /// a consulta não trouxe nada). Como o que importa é a última publicação de
  /// cada PC, poucas linhas bastam.
  static List<String> maquinasUsandoNome({
    required Iterable<Map<String, dynamic>> eventos,
    required String meuPc,
    required String nome,
  }) {
    final alvo = NumeracaoVenda.normalizarCaixa(nome);
    if (alvo == null) return const [];
    final eu = meuPc.trim().toUpperCase();
    return [
      for (final linha in ultimoNomePorPc(eventos).entries)
        if (linha.key.toUpperCase() != eu && linha.value == alvo) linha.key,
    ];
  }

  /// Nomes dos computadores prontos para o aviso na tela:
  /// `PDV-A`, `PDV-A e PDV-B`, `PDV-A, PDV-B e PDV-C`.
  static String listarMaquinas(List<String> maquinas) {
    if (maquinas.isEmpty) return '';
    if (maquinas.length == 1) return maquinas.first;
    final ultima = maquinas.last;
    final outras = maquinas.sublist(0, maquinas.length - 1).join(', ');
    return '$outras e $ultima';
  }
}
