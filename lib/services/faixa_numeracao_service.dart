import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'database_service.dart';
import 'supabase_service.dart';

/// Uma faixa (bloco) de números de venda/pedido reservada para ESTE computador.
///
/// Por que existe: duas máquinas sem internet não têm como combinar o número da
/// venda. Cada uma gera "o maior que eu tenho + 1" e as duas chegam a
/// `VND-0003`. A nuvem não recusa número repetido (não há restrição de
/// unicidade), então a duplicação passava em silêncio.
///
/// Com faixa reservada, cada PC tem um pedaço próprio da sequência: enquanto a
/// internet existe, ele reserva um bloco (ex.: 434..933) e vende offline dentro
/// dele sem nunca colidir. A nuvem passa a ser consultada uma vez por bloco, em
/// vez de uma vez por venda.
@immutable
class FaixaNumeracao {
  const FaixaNumeracao({
    required this.tipo,
    required this.inicio,
    required this.fim,
    required this.proximo,
    this.origem = 'local',
  });

  /// 'venda' (VND-) ou 'pedido' (PED-).
  final String tipo;

  /// Primeiro número do bloco, inclusive.
  final int inicio;

  /// Último número do bloco, inclusive.
  final int fim;

  /// Próximo número ainda não usado.
  final int proximo;

  /// 'nuvem' quando acabou de ser reservada, 'local' quando veio do banco.
  final String origem;

  bool get esgotada => proximo > fim;

  int get restantes => esgotada ? 0 : fim - proximo + 1;

  /// Faixa com o número atual já gasto.
  FaixaNumeracao avancar() => FaixaNumeracao(
        tipo: tipo,
        inicio: inicio,
        fim: fim,
        proximo: proximo + 1,
        origem: origem,
      );

  Map<String, dynamic> toJson() => {
        't': tipo,
        'i': inicio,
        'f': fim,
        'p': proximo,
        'o': origem,
      };

  /// Aceita tanto o mapa quanto o texto JSON guardado no `exodo_config`.
  ///
  /// Devolve null (em vez de estourar) quando o conteúdo está corrompido: uma
  /// faixa ilegível não pode impedir a venda — o chamador cai no comportamento
  /// antigo e o sincronizador renumera o que subir repetido.
  static FaixaNumeracao? fromJson(Object? bruto, {required String tipo}) {
    try {
      final Map<String, dynamic> mapa;
      if (bruto is String) {
        mapa = Map<String, dynamic>.from(jsonDecode(bruto) as Map);
      } else if (bruto is Map) {
        mapa = Map<String, dynamic>.from(bruto);
      } else {
        return null;
      }
      final inicio = (mapa['i'] as num?)?.toInt() ?? 0;
      final fim = (mapa['f'] as num?)?.toInt() ?? 0;
      final proximo = (mapa['p'] as num?)?.toInt() ?? inicio;
      if (inicio <= 0 || fim < inicio) return null;
      return FaixaNumeracao(
        tipo: (mapa['t'] as String?) ?? tipo,
        inicio: inicio,
        fim: fim,
        proximo: proximo,
        origem: (mapa['o'] as String?) ?? 'local',
      );
    } catch (_) {
      return null;
    }
  }

  @override
  String toString() =>
      'FaixaNumeracao($tipo: usando $proximo, bloco $inicio..$fim, origem $origem)';
}

/// O que vai ser reservado e quanto fica gravado no contador da nuvem.
@immutable
class ReservaCalculada {
  const ReservaCalculada({
    required this.inicio,
    required this.fim,
    required this.proximoLivre,
  });

  final int inicio;
  final int fim;

  /// Valor final do contador na nuvem (o próximo livre depois deste bloco).
  final int proximoLivre;

  int get tamanho => fim - inicio + 1;
}

/// Calcula o bloco a reservar a partir do que o contador da nuvem diz.
///
/// `aPartirDe` é o menor número que a loja ainda pode usar (maior número já
/// emitido + 1, olhando local E nuvem). Ele existe para o caso do contador
/// estar atrasado em relação à realidade — por exemplo, um PC antigo que vendia
/// sem faixa deixou o contador em 300 enquanto a loja já está no 433: reservar a
/// partir de 300 entregaria números já usados.
ReservaCalculada? calcularReserva({
  required int valorNoContador,
  required int aPartirDe,
  required int tamanho,
}) {
  if (tamanho <= 0) return null;
  final bruto = valorNoContador > 0 ? valorNoContador : 1;
  final inicio = bruto >= aPartirDe ? bruto : (aPartirDe < 1 ? 1 : aPartirDe);
  return ReservaCalculada(
    inicio: inicio,
    fim: inicio + tamanho - 1,
    proximoLivre: inicio + tamanho,
  );
}

typedef LerConfig = Future<Object?> Function(String chave);
typedef SalvarConfig = Future<void> Function(String chave, Object? valor);

/// Reserva e consome faixas de numeração, guardando o bloco no banco local.
class FaixaNumeracaoService {
  FaixaNumeracaoService({
    LerConfig? lerConfig,
    SalvarConfig? salvarConfig,
    this.tamanhoPadrao = 500,
  })  : _ler = lerConfig ?? DatabaseService().carregarConfig,
        _salvar = salvarConfig ?? DatabaseService().salvarConfig;

  final LerConfig _ler;
  final SalvarConfig _salvar;

  /// Quantos números cada PC reserva de uma vez. Grande demais deixa buracos na
  /// sequência quando o PC fica sem vender; pequeno demais faz reservar toda hora.
  final int tamanhoPadrao;

  static const String tabelaContador = 'exodo_config';
  static const Duration _tempoLimite = Duration(seconds: 6);

  /// Chave do bloco DESTE PC no banco local.
  String chaveLocal(String tipo, String empresaId) =>
      'exodo_faixa_local_${tipo}_$empresaId';

  /// Chave do contador compartilhado na nuvem (mesma chave para os dois PCs).
  String chaveContador(String tipo, String empresaId) =>
      'exodo_faixa_${tipo}_$empresaId';

  Future<FaixaNumeracao?> lerLocal(String tipo, String empresaId) async {
    if (empresaId.trim().isEmpty) return null;
    try {
      final bruto = await _ler(chaveLocal(tipo, empresaId));
      if (bruto == null) return null;
      return FaixaNumeracao.fromJson(bruto, tipo: tipo);
    } catch (e) {
      debugPrint('>>> [FaixaNumeracao] Não consegui ler o bloco local ($tipo): $e');
      return null;
    }
  }

  Future<void> salvarLocal(FaixaNumeracao faixa, String empresaId) async {
    if (empresaId.trim().isEmpty) return;
    try {
      await _salvar(
        chaveLocal(faixa.tipo, empresaId),
        jsonEncode(faixa.toJson()),
      );
    } catch (e) {
      debugPrint('>>> [FaixaNumeracao] Não consegui gravar o bloco local: $e');
    }
  }

  /// Reserva um bloco novo no contador da nuvem, com compare-and-swap.
  ///
  /// O contador é uma linha em `exodo_config` cujo `valor` é o próximo número
  /// livre. A reserva é um UPDATE condicionado ao valor que acabamos de ler
  /// (`valor = V` → `valor = V + tamanho`): se outro PC mexeu no contador nesse
  /// meio tempo, o UPDATE não pega nada e a gente relê. Sem isso, os dois PCs
  /// reservariam o mesmo bloco — exatamente o problema que estamos resolvendo.
  ///
  /// Devolve null quando não dá para reservar (offline, tabela sem permissão,
  /// contador disputado). O chamador então usa a numeração local antiga.
  Future<FaixaNumeracao?> reservar({
    required String tipo,
    required String empresaId,
    required int aPartirDe,
    int? tamanho,
  }) async {
    final quantidade = tamanho ?? tamanhoPadrao;
    if (quantidade <= 0 || empresaId.trim().isEmpty) return null;
    if (!SupabaseService.isAvailable) return null;

    final chave = chaveContador(tipo, empresaId);
    final client = SupabaseService.instance.client;

    for (var tentativa = 0; tentativa < 5; tentativa++) {
      try {
        final linhas = await client
            .from(tabelaContador)
            .select('valor')
            .eq('chave', chave)
            .limit(1)
            .timeout(_tempoLimite);

        if (linhas.isEmpty) {
          // Primeira reserva desta empresa: o contador nasce já depois de tudo
          // que a loja emitiu, para não entregar número usado.
          final calculada = calcularReserva(
            valorNoContador: 0,
            aPartirDe: aPartirDe,
            tamanho: quantidade,
          );
          if (calculada == null) return null;
          try {
            await client.from(tabelaContador).insert({
              'chave': chave,
              'valor': '${calculada.proximoLivre}',
              'empresa_id': empresaId,
            }).timeout(_tempoLimite);
          } catch (e) {
            continue; // outro PC criou o contador primeiro: relê e tenta de novo
          }
          debugPrint('>>> [FaixaNumeracao] Contador criado ($tipo): '
              '${calculada.inicio}..${calculada.fim} para este PC');
          return FaixaNumeracao(
            tipo: tipo,
            inicio: calculada.inicio,
            fim: calculada.fim,
            proximo: calculada.inicio,
            origem: 'nuvem',
          );
        }

        final atual = int.tryParse('${linhas.first['valor']}') ?? 0;
        final calculada = calcularReserva(
          valorNoContador: atual,
          aPartirDe: aPartirDe,
          tamanho: quantidade,
        );
        if (calculada == null) return null;

        final alteradas = await client
            .from(tabelaContador)
            .update({'valor': '${calculada.proximoLivre}'})
            .eq('chave', chave)
            .eq('valor', '$atual')
            .select('valor')
            .timeout(_tempoLimite);

        if (alteradas.isEmpty) {
          // Perdeu a corrida (o outro PC reservou primeiro): relê o contador.
          debugPrint('>>> [FaixaNumeracao] Contador disputado, tentando de novo '
              '(${tentativa + 1}/5)');
          continue;
        }

        debugPrint('>>> [FaixaNumeracao] Faixa reservada ($tipo): '
            '${calculada.inicio}..${calculada.fim} (contador foi para '
            '${calculada.proximoLivre})');
        return FaixaNumeracao(
          tipo: tipo,
          inicio: calculada.inicio,
          fim: calculada.fim,
          proximo: calculada.inicio,
          origem: 'nuvem',
        );
      } catch (e) {
        debugPrint('>>> [FaixaNumeracao] Não consegui reservar ($tipo): $e');
        return null;
      }
    }
    return null;
  }
}
