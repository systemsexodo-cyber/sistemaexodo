import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Item de um pedido guardado no aparelho, usado para repetir a compra.
class PedidoClienteLocalItem {
  final String id;
  final String nome;
  final int quantidade;
  final double preco;

  const PedidoClienteLocalItem({
    required this.id,
    required this.nome,
    required this.quantidade,
    required this.preco,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'nome': nome,
        'quantidade': quantidade,
        'preco': preco,
      };

  factory PedidoClienteLocalItem.fromJson(Map<String, dynamic> json) {
    return PedidoClienteLocalItem(
      id: (json['id'] ?? '').toString(),
      nome: (json['nome'] ?? '').toString(),
      quantidade: (json['quantidade'] as num?)?.round() ?? 1,
      preco: (json['preco'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

/// Pedido feito pelo cliente na loja publica, guardado no proprio aparelho.
///
/// Serve para o cliente reabrir o acompanhamento depois de fechar o aviso de
/// confirmacao da compra (ou a aba que abriu o rastreamento). Depois que o
/// pedido termina (ou passa de um dia), o mesmo registro serve para repetir a
/// compra. Fica so no aparelho: nao vai para a nuvem nem para o painel do
/// lojista.
class PedidoClienteLocal {
  final String codigo;
  final String numero;
  final double total;
  final DateTime data;
  final String? status;
  final List<PedidoClienteLocalItem> itens;

  /// Saiu do balao/vitrine mas continua guardado para consulta depois.
  final bool arquivado;

  const PedidoClienteLocal({
    required this.codigo,
    required this.numero,
    required this.total,
    required this.data,
    this.status,
    this.itens = const [],
    this.arquivado = false,
  });

  /// O pedido terminou (concluido, pago, entregue, finalizado ou cancelado)
  /// ou ja passou de um dia?
  ///
  /// A partir dai o balao da loja deixa de ser "acompanhar" e passa a ser
  /// "pedidos feitos", com atalho para repetir a compra.
  bool get podeRepetir {
    final s = (status ?? '').toLowerCase().trim();
    if (s.isNotEmpty) {
      // startsWith cobre tambem as formas acentuadas (concluido/concluído),
      // sem precisar de acento no codigo.
      if (s.startsWith('conclu') ||
          s.startsWith('entreg') ||
          s.startsWith('finaliz') ||
          s.startsWith('cancel') ||
          s == 'pago') {
        return true;
      }
    }
    return DateTime.now().difference(data) >= const Duration(days: 1);
  }

  Map<String, dynamic> toJson() => {
        'codigo': codigo,
        'numero': numero,
        'total': total,
        'data': data.toIso8601String(),
        if (status != null) 'status': status,
        if (itens.isNotEmpty)
          'itens': itens.map((item) => item.toJson()).toList(),
        if (arquivado) 'arquivado': true,
      };

  factory PedidoClienteLocal.fromJson(Map<String, dynamic> json) {
    final itensBrutos = json['itens'];
    final itens = <PedidoClienteLocalItem>[];
    if (itensBrutos is List) {
      for (final item in itensBrutos) {
        if (item is Map) {
          itens.add(PedidoClienteLocalItem.fromJson(
              Map<String, dynamic>.from(item)));
        }
      }
    }
    return PedidoClienteLocal(
      codigo: (json['codigo'] ?? '').toString(),
      numero: (json['numero'] ?? '').toString(),
      total: (json['total'] as num?)?.toDouble() ?? 0.0,
      data: DateTime.tryParse((json['data'] ?? '').toString()) ?? DateTime.now(),
      status: json['status']?.toString(),
      itens: itens,
      arquivado: json['arquivado'] == true,
    );
  }
}

/// Leitura/gravacao dos pedidos do cliente no armazenamento local.
class PedidosClienteLocalService {
  /// Chave antiga, com apenas o codigo do ultimo pedido.
  static const String chaveUltimoPedido = 'exodo_loja_ultimo_pedido';

  /// Lista dos pedidos recentes do cliente neste aparelho.
  static const String chaveLista = 'exodo_loja_pedidos_cliente';

  /// Quantos pedidos ficam no balao (os mais recentes primeiro).
  static const int maximo = 10;

  /// Quantos pedidos removidos do balao ficam no historico local.
  static const int maximoArquivados = 50;

  static Future<List<PedidoClienteLocal>> carregar() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final bruto = prefs.getString(chaveLista);
      final pedidos = <PedidoClienteLocal>[];
      if (bruto != null && bruto.isNotEmpty) {
        final lista = jsonDecode(bruto);
        if (lista is List) {
          for (final item in lista) {
            if (item is Map) {
              final pedido =
                  PedidoClienteLocal.fromJson(Map<String, dynamic>.from(item));
              if (pedido.codigo.isNotEmpty) pedidos.add(pedido);
            }
          }
        }
      }

      // Compatibilidade: quem comprou antes desta versao tem apenas o codigo
      // do ultimo pedido salvo. Ele vira o primeiro item da lista.
      if (pedidos.isEmpty) {
        final codigoAntigo = prefs.getString(chaveUltimoPedido) ?? '';
        if (codigoAntigo.isNotEmpty) {
          pedidos.add(PedidoClienteLocal(
            codigo: codigoAntigo,
            numero: codigoAntigo,
            total: 0,
            data: DateTime.now(),
          ));
        }
      }

      return pedidos;
    } catch (e) {
      debugPrint('>>> [PedidosClienteLocal] Erro ao carregar: $e');
      return const [];
    }
  }

  /// Guarda (ou atualiza) um pedido no topo da lista.
  static Future<void> registrar(PedidoClienteLocal pedido) async {
    if (pedido.codigo.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final atuais = await carregar();
      // O limite do balao vale so para os pedidos ativos. Os guardados tem
      // cota propria, para uma compra nova nao apagar o historico que o
      // cliente deixou salvo para consultar depois.
      final ativos = <PedidoClienteLocal>[
        pedido,
        ...atuais.where((p) => p.codigo != pedido.codigo && !p.arquivado),
      ];
      final arquivados =
          atuais.where((p) => p.codigo != pedido.codigo && p.arquivado).toList();
      if (ativos.length > maximo) ativos.removeRange(maximo, ativos.length);
      if (arquivados.length > maximoArquivados) {
        arquivados.removeRange(maximoArquivados, arquivados.length);
      }
      final lista = <PedidoClienteLocal>[...ativos, ...arquivados];
      await prefs.setString(
        chaveLista,
        jsonEncode(lista.map((p) => p.toJson()).toList()),
      );
      // Mantem a chave antiga com o ultimo codigo (outras telas ainda leem).
      await prefs.setString(chaveUltimoPedido, pedido.codigo);
    } catch (e) {
      debugPrint('>>> [PedidosClienteLocal] Erro ao salvar: $e');
    }
  }

  /// Tira o pedido do balao sem apagar: ele passa para "Pedidos guardados",
  /// onde o cliente ainda consegue consultar e repetir a compra.
  static Future<void> arquivar(String codigo) =>
      _definirArquivado(codigo, true);

  /// Devolve um pedido guardado para o balao.
  static Future<void> desarquivar(String codigo) =>
      _definirArquivado(codigo, false);

  static Future<void> _definirArquivado(String codigo, bool arquivado) async {
    if (codigo.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final atuais = await carregar();
      final atualizados = atuais
          .map((p) => p.codigo == codigo
              ? PedidoClienteLocal(
                  codigo: p.codigo,
                  numero: p.numero,
                  total: p.total,
                  data: p.data,
                  status: p.status,
                  itens: p.itens,
                  arquivado: arquivado,
                )
              : p)
          .toList();
      await prefs.setString(
        chaveLista,
        jsonEncode(atualizados.map((p) => p.toJson()).toList()),
      );
    } catch (e) {
      debugPrint('>>> [PedidosClienteLocal] Erro ao arquivar: $e');
    }
  }

  static Future<void> remover(String codigo) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final atuais = await carregar();
      final lista = atuais.where((p) => p.codigo != codigo).toList();
      await prefs.setString(
        chaveLista,
        jsonEncode(lista.map((p) => p.toJson()).toList()),
      );
      if (prefs.getString(chaveUltimoPedido) == codigo) {
        if (lista.isEmpty) {
          await prefs.remove(chaveUltimoPedido);
        } else {
          await prefs.setString(chaveUltimoPedido, lista.first.codigo);
        }
      }
    } catch (e) {
      debugPrint('>>> [PedidosClienteLocal] Erro ao remover: $e');
    }
  }
}
