import 'package:sistema_exodo_novo/models/conta_pagar.dart';
import 'package:sistema_exodo_novo/models/mesa_comanda.dart';
import 'package:uuid/uuid.dart';

/// Arredonda um valor monetário para centavos.
double centavos(double valor) => (valor * 100).roundToDouble() / 100;

/// Origem dos itens de um recebimento: a mesa/comanda raiz ou uma comanda
/// vinculada à mesa.
class OrigemRecebimento {
  final String id;
  final String rotulo;
  final List<ItemMesaComanda> itens;

  const OrigemRecebimento({
    required this.id,
    required this.rotulo,
    required this.itens,
  });
}

/// Resultado do planejamento de um recebimento.
///
/// - [quantidadePorItem]: itemId -> quantidade quitada agora (pode ser
///   fracionada quando o cliente paga um valor livre).
/// - [valorPorItem]: itemId -> reais dos itens quitados agora (sem garçom).
/// - [valorPorOrigem]: origemId -> reais a registrar no histórico daquela
///   mesa/comanda, já com o garçom proporcional.
class PlanoRecebimento {
  final Map<String, double> quantidadePorItem;
  final Map<String, double> valorPorItem;
  final Map<String, double> valorPorOrigem;
  final double valorItens;
  final bool garcomRetirado;

  const PlanoRecebimento({
    required this.quantidadePorItem,
    required this.valorPorItem,
    required this.valorPorOrigem,
    required this.valorItens,
    required this.garcomRetirado,
  });

  /// Valor total que deve ser recebido (itens + garçom).
  double get valorTotal =>
      centavos(valorPorOrigem.values.fold(0.0, (soma, v) => soma + v));

  double get valorGarcom => centavos(valorTotal - valorItens);

  bool get vazio => valorTotal <= 0.005;

  List<String> get itensIds =>
      quantidadePorItem.keys.toList(growable: false);
}

/// Soma do que ainda falta pagar em itens (sem couvert e sem garçom).
double totalPendenteItens(List<OrigemRecebimento> origens) {
  var total = 0.0;
  for (final origem in origens) {
    for (final item in origem.itens) {
      if (item.status == StatusItem.cancelado) continue;
      total += item.subtotalPendente;
    }
  }
  return centavos(total);
}

/// Monta o plano de recebimento.
///
/// Com [quantidadesPorItem] (ou [itensSelecionados]) o recebimento é "por
/// item": cada item escolhido é quitado pela quantidade informada, limitada ao
/// que ainda falta. Com [valor] o recebimento é por valor livre: o dinheiro é
/// distribuído na ordem dos itens e o que sobrar continua pendente.
///
/// [quantidadesPorItem] tem prioridade sobre [itensSelecionados] e permite
/// pagar apenas parte da quantidade de um item (ex.: 2 de 3 unidades).
///
/// O garçom (10% dos itens) é sempre calculado sobre a parte dos itens, de
/// modo que cada real recebido de item quita também a sua fatia de garçom.
PlanoRecebimento planejarRecebimento({
  required List<OrigemRecebimento> origens,
  Set<String>? itensSelecionados,
  Map<String, double>? quantidadesPorItem,
  double? valor,
  bool garcomRetirado = false,
}) {
  final quantidade = <String, double>{};
  final valoresItens = <String, double>{};
  final itensPorOrigem = <String, double>{};
  final fator = garcomRetirado ? 1.0 : 1.1;

  if (quantidadesPorItem != null || itensSelecionados != null) {
    for (final origem in origens) {
      var totalOrigem = 0.0;
      for (final item in origem.itens) {
        if (item.status == StatusItem.cancelado) continue;
        final pendente = item.quantidadePendente;
        if (pendente <= 0.0001) continue;
        final selecionada = quantidadesPorItem != null
            ? (quantidadesPorItem[item.id] ?? 0.0)
            : (itensSelecionados!.contains(item.id) ? pendente : 0.0);
        final quantidadeItem = selecionada.clamp(0.0, pendente).toDouble();
        if (quantidadeItem <= 0.0001) continue;
        final valorItem = centavos(
          item.precoUnitarioComAdicionais * quantidadeItem,
        );
        if (valorItem <= 0) continue;
        quantidade[item.id] = quantidadeItem;
        valoresItens[item.id] = valorItem;
        totalOrigem += valorItem;
      }
      if (totalOrigem > 0.004) itensPorOrigem[origem.id] = centavos(totalOrigem);
    }
  } else {
    var disponivel = centavos(valor ?? 0.0);
    if (disponivel < 0) disponivel = 0.0;

    for (final origem in origens) {
      if (disponivel <= 0.004) break;

      final pendenteOrigem = centavos(
        origem.itens
            .where((item) => item.status != StatusItem.cancelado)
            .fold(0.0, (soma, item) => soma + item.subtotalPendente),
      );
      if (pendenteOrigem <= 0.004) continue;

      // Custo de quitar essa origem inteira (itens + garçom proporcional).
      final custoOrigem = centavos(pendenteOrigem * fator);
      final consumir =
          disponivel >= custoOrigem - 0.004 ? custoOrigem : disponivel;
      var restanteItens = centavos(consumir / fator);
      var totalItensOrigem = 0.0;

      for (final item in origem.itens) {
        if (restanteItens <= 0.004) break;
        if (item.status == StatusItem.cancelado) continue;
        final unitario = item.precoUnitarioComAdicionais;
        final pendente = item.quantidadePendente;
        if (unitario <= 0 || pendente <= 0.0001) continue;

        final custoItem = centavos(unitario * pendente);
        if (custoItem <= restanteItens + 0.004) {
          quantidade[item.id] = pendente;
          valoresItens[item.id] = custoItem;
          totalItensOrigem += custoItem;
          restanteItens = centavos(restanteItens - custoItem);
        } else {
          final quantidadeParcial = restanteItens / unitario;
          quantidade[item.id] = quantidadeParcial;
          valoresItens[item.id] = centavos(restanteItens);
          totalItensOrigem += centavos(restanteItens);
          restanteItens = 0;
        }
      }

      if (totalItensOrigem <= 0.004) continue;
      itensPorOrigem[origem.id] = centavos(totalItensOrigem);
      disponivel = centavos(disponivel - centavos(totalItensOrigem * fator));
    }
  }

  final valorItens =
      centavos(valoresItens.values.fold(0.0, (soma, v) => soma + v));
  final valorPorOrigem = <String, double>{};
  for (final entrada in itensPorOrigem.entries) {
    valorPorOrigem[entrada.key] =
        garcomRetirado ? entrada.value : centavos(entrada.value * 1.1);
  }
  _acertarCentavos(
    valorPorOrigem,
    garcomRetirado ? valorItens : centavos(valorItens * 1.1),
  );

  return PlanoRecebimento(
    quantidadePorItem: quantidade,
    valorPorItem: valoresItens,
    valorPorOrigem: valorPorOrigem,
    valorItens: valorItens,
    garcomRetirado: garcomRetirado,
  );
}

/// Ajusta a maior origem para que a soma das partes feche no centavo.
void _acertarCentavos(Map<String, double> partes, double totalDesejado) {
  if (partes.isEmpty) return;
  final soma = centavos(partes.values.fold(0.0, (s, v) => s + v));
  final diferenca = centavos(totalDesejado - soma);
  if (diferenca.abs() < 0.005) return;
  final maiorChave = partes.keys.reduce(
    (a, b) => partes[a]! >= partes[b]! ? a : b,
  );
  final ajustado = centavos(partes[maiorChave]! + diferenca);
  partes[maiorChave] = ajustado < 0 ? 0.0 : ajustado;
}

/// Aplica as quantidades pagas aos itens, limitando ao que cada item tem.
List<ItemMesaComanda> aplicarQuantidadesPagas(
  List<ItemMesaComanda> itens,
  Map<String, double> quantidadePorItem,
) {
  if (quantidadePorItem.isEmpty) return itens;
  var mudou = false;
  final atualizados = itens.map((item) {
    final acrescimo = quantidadePorItem[item.id];
    if (acrescimo == null || acrescimo <= 0) return item;
    final novaQuantidade =
        (item.quantidadePaga + acrescimo).clamp(0.0, item.quantidade);
    if ((novaQuantidade - item.quantidadePaga).abs() < 0.000001) return item;
    mudou = true;
    return item.copyWith(quantidadePaga: novaQuantidade.toDouble());
  }).toList();
  return mudou ? atualizados : itens;
}

/// Ids dos itens totalmente pagos, preservando os que já estavam marcados.
List<String> idsItensPagos(
  List<ItemMesaComanda> itens, [
  List<String> anteriores = const [],
]) {
  final ids = <String>{...anteriores};
  for (final item in itens) {
    if (item.status == StatusItem.cancelado) continue;
    if (item.estaPago) ids.add(item.id);
  }
  return ids.toList(growable: false);
}

/// Divide cada forma de pagamento entre as partes (mesa/comandas), mantendo o
/// total exato que entrou no caixa.
///
/// [foraDasPartes] é o dinheiro que não entra no histórico das partes (couvert,
/// que tem controle próprio em `couvertPago`).
Map<String, List<RegistroPagamento>> distribuirPagamentosPorPartes({
  required List<Map<String, dynamic>> pagamentos,
  required Map<String, double> partes,
  String? pessoaPagou,
  double foraDasPartes = 0.0,
  String Function(String chave)? observacao,
  Map<String, Map<String, double>>? quantidadesPorOrigem,
}) {
  const uuid = Uuid();
  final resultado = <String, List<RegistroPagamento>>{
    for (final chave in partes.keys) chave: <RegistroPagamento>[],
  };
  final chaves = partes.entries
      .where((e) => e.value > 0.004)
      .map((e) => e.key)
      .toList();
  if (chaves.isEmpty) return resultado;

  final totalPartes = centavos(
    chaves.fold(0.0, (soma, chave) => soma + partes[chave]!),
  );
  if (totalPartes <= 0.004) return resultado;

  final totalGeral = centavos(totalPartes + foraDasPartes);

  for (var indice = 0; indice < pagamentos.length; indice++) {
    final pagamento = pagamentos[indice];
    final valorOriginal =
        (pagamento['valor'] as num?)?.toDouble() ?? 0.0;
    if (valorOriginal <= 0.004) continue;

    // Só a fatia dos itens entra no histórico; o couvert fica no couvertPago.
    final ehUltimo = indice == pagamentos.length - 1;
    final valor =
        ehUltimo && totalGeral <= 0.004
            ? valorOriginal
            : (totalGeral <= 0.004
                ? valorOriginal
                : centavos(valorOriginal * totalPartes / totalGeral));
    if (valor <= 0.004) continue;

    final forma = (pagamento['tipo']?.toString() ?? 'outro').split('.').last;
    final observacaoPagamento = pagamento['observacao'] as String?;
    var acumulado = 0.0;

    for (var i = 0; i < chaves.length; i++) {
      final chave = chaves[i];
      final cota = i == chaves.length - 1
          ? centavos(valor - acumulado)
          : centavos(valor * partes[chave]! / totalPartes);
      acumulado += cota;
      if (cota <= 0.004) continue;

      final base = observacao?.call(chave) ?? 'Recebimento';
      resultado[chave]!.add(
        RegistroPagamento(
          id: uuid.v4(),
          valor: cota,
          dataPagamento: DateTime.now(),
          formaPagamento: forma,
          observacao: (observacaoPagamento == null ||
                  observacaoPagamento.isEmpty)
              ? base
              : '$base - $observacaoPagamento',
          itensPagos: const [],
          itensQuantidades: quantidadesPorOrigem?[chave],
          pessoaPagou: (pessoaPagou == null || pessoaPagou.isEmpty)
              ? null
              : pessoaPagou,
        ),
      );
    }
  }

  return resultado;
}
