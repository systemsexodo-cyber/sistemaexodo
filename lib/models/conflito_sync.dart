import 'dart:convert';

/// Uma disputa entre ESTE banco local e a nuvem, esperando decisão do usuário.
///
/// O sincronizador parqueia aqui (tabela `exodo_sync_conflitos`, com
/// `resolvido = FALSE`) toda vez que a mesma linha foi alterada nas duas
/// máquinas: o outro PC empurrou a versão dele para a nuvem depois do último
/// download desta máquina, e esta máquina tem uma alteração local ainda não
/// enviada. Sem este registro a edição local era descartada em silêncio.
///
/// Nada é aplicado no banco local enquanto o conflito está aberto: o download
/// pula esse id (o `ids_bloqueados_no_download` do sincronizador), então a
/// versão que o usuário está vendo continua sendo a DELE até ele decidir.
class ConflitoSync {
  final String id;
  final String tabela;
  final String registroId;
  final Map<String, dynamic> dadosLocais;
  final Map<String, dynamic> dadosNuvem;
  final DateTime? criadoEm;

  const ConflitoSync({
    required this.id,
    required this.tabela,
    required this.registroId,
    this.dadosLocais = const {},
    this.dadosNuvem = const {},
    this.criadoEm,
  });

  /// Nome da tabela do jeito que o usuário conhece.
  String get rotuloTabela {
    switch (tabela) {
      case 'produtos':
        return 'Produto';
      case 'clientes':
        return 'Cliente';
      case 'vendas_balcao':
        return 'Venda';
      case 'pedidos':
        return 'Pedido';
      case 'contas_pagar':
        return 'Conta a pagar';
      case 'estoque_historico':
        return 'Histórico de estoque';
      case 'funcionarios':
        return 'Funcionário';
      case 'empresas':
        return 'Empresa';
      default:
        return tabela;
    }
  }

  /// Nome do registro (o que o usuário reconhece na tela).
  String get nomeDoRegistro {
    for (final chave in const ['nome', 'produto_nome', 'razao_social', 'numero', 'descricao']) {
      final valor = (dadosLocais[chave] ?? dadosNuvem[chave])?.toString().trim() ?? '';
      if (valor.isNotEmpty) return valor;
    }
    return registroId;
  }

  /// Campos em que a sua versão e a da nuvem realmente divergem.
  ///
  /// Carimbos de controle (data de alteração, marca de sincronizado) não
  /// entram: só o que muda o dado em si interessa para decidir.
  List<String> get camposDivergentes => diferencas(dadosLocais, dadosNuvem);

  static const Set<String> _carimbos = {
    'updated_at',
    'created_at',
    'criado_em',
    'atualizado_em',
    '_sincronizado_nuvem',
    'data_alteracao',
  };

  /// Compara dois registros e devolve os campos diferentes (ignorando carimbos).
  ///
  /// Puro de propósito: é a regra que decide o que aparece na tela de conflitos,
  /// então precisa poder ser testada sem banco nenhum.
  static List<String> diferencas(
    Map<String, dynamic> locais,
    Map<String, dynamic> nuvem,
  ) {
    final campos = <String>{...locais.keys, ...nuvem.keys}.difference(_carimbos)..toList();
    final divergentes = <String>[];
    for (final campo in campos) {
      if (!_mesmoValor(locais[campo], nuvem[campo])) divergentes.add(campo);
    }
    divergentes.sort();
    return divergentes;
  }

  static bool _mesmoValor(dynamic a, dynamic b) {
    if (a == null && b == null) return true;
    if (a is Map || b is Map || a is List || b is List) {
      try {
        return jsonEncode(_normalizar(a)) == jsonEncode(_normalizar(b));
      } catch (_) {
        return a.toString() == b.toString();
      }
    }
    if (a is num && b is num) return (a - b).abs() < 0.000001;
    return a?.toString() == b?.toString();
  }

  /// Ordena as chaves de mapas aninhados, para dois JSONs iguais compararem igual.
  ///
  /// Um lado pode chegar como mapa (decodificado pelo driver) e o outro como o
  /// JSON em texto (coluna text, ou jsonb serializado pelo sincronizador). Sem
  /// abrir o texto, os dois viram "diferentes" e o usuário recebe um conflito
  /// que não existe.
  static dynamic _normalizar(dynamic valor) {
    if (valor is Map) {
      final chaves = valor.keys.map((k) => k.toString()).toList()..sort();
      return {for (final k in chaves) k: _normalizar(valor[k])};
    }
    if (valor is List) return valor.map(_normalizar).toList();
    if (valor is String) {
      final texto = valor.trim();
      if (texto.startsWith('{') || texto.startsWith('[')) {
        try {
          return _normalizar(jsonDecode(texto));
        } catch (_) {
          return valor;
        }
      }
    }
    return valor;
  }

  /// Aceita tanto jsonb (Map/List) quanto o JSON serializado como texto.
  static Map<String, dynamic> _lerMapa(dynamic valor) {
    if (valor == null) return const {};
    if (valor is Map) return Map<String, dynamic>.from(valor);
    if (valor is String && valor.trim().isNotEmpty) {
      try {
        final decodificado = jsonDecode(valor);
        if (decodificado is Map) return Map<String, dynamic>.from(decodificado);
      } catch (_) {
        // jsonb ilegível: o conflito continua válido, só sem detalhamento.
      }
    }
    return const {};
  }

  static DateTime? _lerData(dynamic valor) {
    if (valor == null) return null;
    if (valor is DateTime) return valor.isUtc ? valor.toLocal() : valor;
    try {
      final d = DateTime.parse(valor.toString());
      return d.isUtc ? d.toLocal() : d;
    } catch (_) {
      return null;
    }
  }

  factory ConflitoSync.fromMap(Map<String, dynamic> map) {
    return ConflitoSync(
      id: map['id']?.toString() ?? '',
      tabela: map['tabela']?.toString() ?? '',
      registroId: (map['registro_id'] ?? map['registroId'])?.toString() ?? '',
      dadosLocais: _lerMapa(map['dados_locais'] ?? map['dadosLocais']),
      dadosNuvem: _lerMapa(map['dados_nuvem'] ?? map['dadosNuvem']),
      criadoEm: _lerData(map['criado_em'] ?? map['criadoEm']),
    );
  }
}
