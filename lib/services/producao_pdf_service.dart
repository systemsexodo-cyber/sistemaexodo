import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/departamento.dart';
import '../models/empresa.dart';
import '../models/produto.dart';
import '../models/ticket_producao.dart';
import 'data_service.dart';
import 'fila_producao_service.dart';
import 'impressao_service.dart';

/// Detalhes do pedido/venda exibidos no cabeçalho do ticket de produção:
/// mesa/comanda, telefone do cliente, endereço de entrega, motorista,
/// previsão, forma de pagamento, troco e observações gerais — para o pessoal
/// do setor produzir o pedido sem precisar perguntar.
class DetalhesTicketProducao {
  final String? mesaComanda; // ex: "MESA 5" ou "COMANDA 12"
  final String? clienteTelefone;
  final String? enderecoEntrega; // endereço completo de entrega
  final String? motorista;
  final String? previsaoEntrega; // ex: "30-45 min" ou "18:30"
  final List<String> formasPagamento; // ex: ["Dinheiro", "PIX"]
  final double? troco;
  final bool pagamentoConcluido; // true = já pago
  final String? observacoesGerais; // observação geral do pedido/venda
  final DateTime? dataPedido; // Hora em que o pedido foi feito (para a cozinha saber há quanto tempo)
  final String? usuarioCriou; // Nome do garçom/operador que lançou o pedido

  const DetalhesTicketProducao({
    this.mesaComanda,
    this.clienteTelefone,
    this.enderecoEntrega,
    this.motorista,
    this.previsaoEntrega,
    this.formasPagamento = const [],
    this.troco,
    this.pagamentoConcluido = false,
    this.observacoesGerais,
    this.dataPedido,
    this.usuarioCriou,
  });
}

/// Item que entra no ticket de produção.
///
/// Aceita produtos vindos do carrinho do PDV ([ItemCarrinho]), de uma venda
/// salva ([ItemVendaBalcao]) ou de um pedido ([ItemPedido]) — para a
/// reimpressão pelo histórico, por exemplo.
class ItemProducaoInput {
  final String id; // ID do produto (usado para resolver a impressora)
  final String nome;
  final double quantidade;
  final String? observacao;
  final List<String> adicionais; // Nomes dos adicionais selecionados
  final List<String> opcoesCombo; // Nomes das opções de combo selecionadas
  final DateTime? dataHora; // Quando ESTE item foi lançado (hora por item)
  final String? usuarioCriou; // Garçom que lançou ESTE item

  const ItemProducaoInput({
    required this.id,
    required this.nome,
    required this.quantidade,
    this.observacao,
    this.adicionais = const [],
    this.opcoesCombo = const [],
    this.dataHora,
    this.usuarioCriou,
  });
}

/// Destino de um ticket de produção: o SETOR (departamento) que prepara o item
/// e a impressora onde a via daquele setor deve sair.
///
/// A impressão é resolvida por DESTINO, não por impressora: com 3 setores
/// marcados no produto saem 3 vias — uma na impressora de cada setor — mesmo
/// quando dois setores apontam para a mesma impressora. Quando o setor não tem
/// impressora configurada, [impressora] vem vazia e vale a impressora padrão do
/// terminal (mesma regra do cadastro de Departamentos).
class DestinoProducao {
  final String setor; // ex.: "Cozinha"
  final String impressora; // nome no Windows — '' = padrão do terminal

  const DestinoProducao({required this.setor, required this.impressora});

  bool get usaPadrao => impressora.trim().isEmpty;

  String get descricao =>
      '${setor.trim().isEmpty ? 'PRODUÇÃO' : setor.trim()} → '
      '${usaPadrao ? 'Padrão do terminal' : impressora}';

  @override
  bool operator ==(Object other) =>
      other is DestinoProducao &&
      other.setor == setor &&
      other.impressora == impressora;

  @override
  int get hashCode => Object.hash(setor, impressora);

  @override
  String toString() => descricao;
}

/// Serviço de impressão de TICKETS DE PRODUÇÃO.
///
/// Cada produto tem um departamento de preparação (e pode ter departamentos
/// extras marcados). Cada departamento tem a sua impressora, definida no
/// cadastro de Departamentos. Ao salvar uma venda ou lançar um pedido, os itens
/// são agrupados por DESTINO (setor + impressora) e cada destinos imprime um
/// ticket térmico (80mm) na impressora do seu setor (Cozinha, Bar, etc.).
class ProducaoPdfService {
  static String? _limpar(String? valor) {
    if (valor == null) return null;
    final v = valor.trim();
    return v.isEmpty ? null : v;
  }

  /// Impressoras configuradas em um departamento.
  ///
  /// Um departamento SEM impressora devolve `''`, que significa "impressora
  /// padrão do terminal" — mesma regra do cadastro de Departamentos — para que
  /// o setor sempre tenha uma via.
  static List<String> _impressorasDoDepartamento(Departamento dep) {
    final nomes = <String>[];
    void adicionar(String? valor) {
      final nome = valor?.trim() ?? '';
      if (nome.isEmpty || nomes.contains(nome)) return;
      nomes.add(nome);
    }

    adicionar(dep.impressoraProducao);
    for (final e in dep.impressoraProducaoExtra) {
      adicionar(e);
    }
    if (nomes.isEmpty) nomes.add('');
    return nomes;
  }

  /// Texto curto com a(s) impressora(s) de um departamento, para a UI.
  /// Ex.: "Microsoft Print to PDF" ou "Padrão do terminal".
  static String descricaoImpressorasDoDepartamento(Departamento dep) =>
      _impressorasDoDepartamento(dep)
          .map((e) => e.isEmpty ? 'Padrão do terminal' : e)
          .join(' • ');

  /// Resolve os DESTINOS de impressão de produção de um produto: o departamento
  /// principal e cada departamento extra marcado viram pelo menos um destino —
  /// um ticket por setor, na impressora daquele setor.
  ///
  /// Função pura (não depende do [DataService]) para poder ser testada.
  static List<DestinoProducao> resolverDestinos({
    required Iterable<Departamento> departamentos,
    String? departamentoId,
    List<String> departamentosAdicionais = const [],
    String? impressoraProducao,
    List<String> impressorasProducaoExtra = const [],
  }) {
    final depsPorId = <String, Departamento>{};
    for (final d in departamentos) {
      depsPorId[d.id] = d;
    }

    final destinos = <DestinoProducao>[];
    final idsVistos = <String>{};

    void adicionar(String setor, String impressora) {
      final destino = DestinoProducao(setor: setor, impressora: impressora);
      if (!destinos.contains(destino)) destinos.add(destino);
    }

    void adicionarDepartamento(String? id) {
      if (id == null || id.isEmpty) return;
      if (!idsVistos.add(id)) return; // o mesmo setor não imprime duas vezes
      final dep = depsPorId[id];
      if (dep == null) return;
      for (final imp in _impressorasDoDepartamento(dep)) {
        adicionar(dep.nome, imp);
      }
    }

    // Departamento principal do produto
    adicionarDepartamento(departamentoId);
    // Departamentos extras marcados (uma via por setor)
    for (final id in departamentosAdicionais) {
      adicionarDepartamento(id);
    }

    // Legado: produto sem departamento — as impressoras gravadas direto no
    // produto continuam valendo (o valor pode ser o setor ou a impressora).
    if (destinos.isEmpty) {
      void adicionarLegado(String? valor) {
        final nome = _limpar(valor);
        if (nome != null) adicionar(nome, nome);
      }

      adicionarLegado(impressoraProducao);
      for (final e in impressorasProducaoExtra) {
        adicionarLegado(e);
      }
    }

    return destinos;
  }

  /// Mesma resolução de [resolverDestinos], lendo os departamentos do
  /// [DataService] (empresa atual).
  static List<DestinoProducao> destinosDoProduto({
    required Produto produto,
    required DataService dataService,
  }) {
    return resolverDestinos(
      departamentos: dataService.departamentos,
      departamentoId: produto.departamentoId,
      departamentosAdicionais: produto.departamentosAdicionais,
      impressoraProducao: produto.impressoraProducao,
      impressorasProducaoExtra: produto.impressoraProducaoExtra,
    );
  }

  // ── FILA DE PRODUÇÃO (vias que não saíram) ───────────────────────────────
  // O ticket precisa poder ser reimpresso depois, então guardamos o payload
  // (itens + detalhes) junto com o motivo da falha.

  /// Identificador estável da via: o mesmo documento/setor/impressora não gera
  /// duas entradas na fila.
  static String _idDoTicket(
    String documento,
    String setor,
    String impressora,
  ) =>
      '${documento.trim().toUpperCase()}|${setor.trim().toLowerCase()}|'
      '${impressora.trim().toLowerCase()}';

  static Map<String, dynamic> _itemParaMap(ItemProducaoInput item) {
    return {
      'id': item.id,
      'nome': item.nome,
      'quantidade': item.quantidade,
      if (item.observacao != null && item.observacao!.trim().isNotEmpty)
        'observacao': item.observacao,
      if (item.adicionais.isNotEmpty) 'adicionais': item.adicionais,
      if (item.opcoesCombo.isNotEmpty) 'opcoes_combo': item.opcoesCombo,
      if (item.dataHora != null) 'data_hora': item.dataHora!.toIso8601String(),
      if (item.usuarioCriou != null && item.usuarioCriou!.trim().isNotEmpty)
        'usuario_criou': item.usuarioCriou,
    };
  }

  static ItemProducaoInput _itemDeMap(Map<String, dynamic> map) {
    List<String> textos(dynamic raw) =>
        (raw as List?)?.map((e) => e.toString()).toList() ?? const [];
    return ItemProducaoInput(
      id: (map['id'] ?? '').toString(),
      nome: (map['nome'] ?? '').toString(),
      quantidade: (map['quantidade'] as num?)?.toDouble() ?? 1,
      observacao: map['observacao']?.toString(),
      adicionais: textos(map['adicionais']),
      opcoesCombo: textos(map['opcoes_combo']),
      dataHora: DateTime.tryParse((map['data_hora'] ?? '').toString()),
      usuarioCriou: map['usuario_criou']?.toString(),
    );
  }

  static Map<String, dynamic> _detalhesParaMap(DetalhesTicketProducao? det) {
    if (det == null) return const {};
    return {
      if (det.mesaComanda != null) 'mesa_comanda': det.mesaComanda,
      if (det.clienteTelefone != null) 'cliente_telefone': det.clienteTelefone,
      if (det.enderecoEntrega != null) 'endereco_entrega': det.enderecoEntrega,
      if (det.motorista != null) 'motorista': det.motorista,
      if (det.previsaoEntrega != null) 'previsao_entrega': det.previsaoEntrega,
      if (det.formasPagamento.isNotEmpty)
        'formas_pagamento': det.formasPagamento,
      if (det.troco != null) 'troco': det.troco,
      'pagamento_concluido': det.pagamentoConcluido,
      if (det.observacoesGerais != null)
        'observacoes_gerais': det.observacoesGerais,
      if (det.dataPedido != null)
        'data_pedido': det.dataPedido!.toIso8601String(),
      if (det.usuarioCriou != null) 'usuario_criou': det.usuarioCriou,
    };
  }

  static DetalhesTicketProducao _detalhesDeMap(Map<String, dynamic> map) {
    if (map.isEmpty) return const DetalhesTicketProducao();
    return DetalhesTicketProducao(
      mesaComanda: map['mesa_comanda']?.toString(),
      clienteTelefone: map['cliente_telefone']?.toString(),
      enderecoEntrega: map['endereco_entrega']?.toString(),
      motorista: map['motorista']?.toString(),
      previsaoEntrega: map['previsao_entrega']?.toString(),
      formasPagamento: (map['formas_pagamento'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      troco: (map['troco'] as num?)?.toDouble(),
      pagamentoConcluido: map['pagamento_concluido'] == true,
      observacoesGerais: map['observacoes_gerais']?.toString(),
      dataPedido: DateTime.tryParse((map['data_pedido'] ?? '').toString()),
      usuarioCriou: map['usuario_criou']?.toString(),
    );
  }

  /// Cria o registro da via que NÃO saiu, com tudo o que é preciso para
  /// reimprimir depois.
  static TicketProducao _ticketDaFalha({
    required DestinoProducao destino,
    required List<ItemProducaoInput> itens,
    required String numeroDocumento,
    required String tipoDocumento,
    String? clienteNome,
    DetalhesTicketProducao? detalhes,
    required String erro,
  }) {
    return TicketProducao(
      id: _idDoTicket(numeroDocumento, destino.setor, destino.impressora),
      documento: numeroDocumento,
      tipoDocumento: tipoDocumento,
      setor: destino.setor,
      impressora: destino.impressora,
      cliente: clienteNome,
      referencia: detalhes?.mesaComanda,
      resumoItens: [
        for (final item in itens)
          '${_formatarQuantidade(item.quantidade)}x ${item.nome}',
      ],
      ultimoErro: erro,
      payloadItens: itens.map(_itemParaMap).toList(),
      payloadDetalhes: _detalhesParaMap(detalhes),
    );
  }

  /// Reimprime UMA via que ficou pendente (usado pelo Monitor de Produção).
  ///
  /// Sai da fila quando a impressão confirma na impressora do setor; se falhar
  /// de novo, a via continua na fila com mais uma tentativa e o novo motivo.
  static Future<bool> reimprimirTicket({
    required TicketProducao ticket,
    required Empresa empresa,
    FilaProducaoService? fila,
  }) async {
    final filaEfetiva = fila ?? FilaProducaoService.instancia;
    try {
      final bytes = await _gerarTicket(
        empresa: empresa,
        setor: ticket.setor.isEmpty ? 'PRODUÇÃO' : ticket.setor,
        numeroDocumento: ticket.documento,
        tipoDocumento: ticket.tipoDocumento,
        clienteNome: ticket.cliente,
        itens: ticket.payloadItens.map(_itemDeMap).toList(),
        detalhes: _detalhesDeMap(ticket.payloadDetalhes),
      );
      final resultado = await ImpressaoService.imprimirPdfNaImpressora(
        bytes: bytes,
        nomeImpressora: ticket.impressora,
        name: 'Producao_${ticket.documento}_${ticket.setor}',
        termico: true,
      );
      if (resultado.saiuOndeFoiPedido(ticket.usaPadraoDoTerminal)) {
        await filaEfetiva.registrarSucesso(
          documento: ticket.documento,
          setor: ticket.setor,
          impressora: ticket.impressora,
        );
        debugPrint('[Producao] ✅ Reimpressa a via de "${ticket.setor}" '
            '(${ticket.documento}) em "${resultado.impressoraUsada}"');
        return true;
      }
      final erro = resultado.aviso ?? 'A via não saiu na impressora do setor';
      await filaEfetiva.registrarFalha(ticket.copyWith(ultimoErro: erro));
      debugPrint('[Producao] ⚠️ Reimpressão de "${ticket.setor}" falhou: $erro');
      return false;
    } catch (e) {
      await filaEfetiva.registrarFalha(ticket.copyWith(ultimoErro: '$e'));
      debugPrint('[Producao] ❌ Erro ao reimprimir a via de "${ticket.setor}": $e');
      return false;
    }
  }

  /// Agrupa os itens por DESTINO (setor + impressora) — cada grupo é uma via.
  ///
  /// [destinosPorProdutoId] é a resolução de cada produto (ver
  /// [resolverDestinos]) e [destinosForcados] são destinos extras (ex.: o setor
  /// escolhido no lançamento). Um item nunca se repete dentro do mesmo ticket.
  ///
  /// Função pura, para poder ser testada sem impressora nem banco.
  static Map<DestinoProducao, List<ItemProducaoInput>> agruparPorDestino({
    required List<ItemProducaoInput> itens,
    required Map<String, List<DestinoProducao>> destinosPorProdutoId,
    List<DestinoProducao> destinosForcados = const [],
  }) {
    final grupos = <DestinoProducao, List<ItemProducaoInput>>{};
    final itensJaNoGrupo = <DestinoProducao, Set<int>>{};

    void adicionar(int indice, DestinoProducao destino) {
      final ids = itensJaNoGrupo.putIfAbsent(destino, () => <int>{});
      if (!ids.add(indice)) return; // o item não se repete no mesmo ticket
      grupos.putIfAbsent(destino, () => []).add(itens[indice]);
    }

    for (var i = 0; i < itens.length; i++) {
      for (final destino in destinosForcados) {
        adicionar(i, destino);
      }
      for (final destino in destinosPorProdutoId[itens[i].id] ?? const []) {
        adicionar(i, destino);
      }
    }

    return grupos;
  }

  /// Destinos de um DEPARTAMENTO identificado pelo NOME ou pelo ID (ex:
  /// "Cozinha" ou "dep_cozinha"). Usado quando o garçom escolhe o setor no
  /// lançamento: a via sai na impressora configurada naquele setor, em vez de
  /// resolver produto por produto.
  static List<DestinoProducao> _destinosDoDepartamento(
    String setor,
    DataService dataService,
  ) {
    final alvo = setor.trim().toLowerCase();
    if (alvo.isEmpty) return const [];
    for (final d in dataService.departamentos) {
      if (d.nome.trim().toLowerCase() == alvo ||
          d.id.trim().toLowerCase() == alvo) {
        return [
          for (final imp in _impressorasDoDepartamento(d))
            DestinoProducao(setor: d.nome, impressora: imp),
        ];
      }
    }
    return const [];
  }

  /// Gera um PDF térmico (80mm) com o ticket de produção de um setor.
  static Future<Uint8List> _gerarTicket({
    required Empresa empresa,
    required String setor,
    required String numeroDocumento,
    required String tipoDocumento,
    required String? clienteNome,
    required List<ItemProducaoInput> itens,
    DetalhesTicketProducao? detalhes,
  }) async {
    final pdf = pw.Document();
    final formatoData = DateFormat('dd/MM/yyyy HH:mm');
    final det = detalhes;

    // Linhas de cabeçalho: mesa/comanda, cliente, telefone, entrega, pagamento
    final linhasCabecalho = <String>[];

    if (det?.mesaComanda != null && det!.mesaComanda!.trim().isNotEmpty) {
      linhasCabecalho.add('${det.mesaComanda!.trim()}');
    }
    if (clienteNome != null && clienteNome.trim().isNotEmpty) {
      linhasCabecalho.add('Cliente: ${clienteNome.trim()}');
    }
    if (det?.clienteTelefone != null && det!.clienteTelefone!.trim().isNotEmpty) {
      linhasCabecalho.add('Fone: ${det.clienteTelefone!.trim()}');
    }
    if (det?.enderecoEntrega != null && det!.enderecoEntrega!.trim().isNotEmpty) {
      linhasCabecalho.add('Entrega: ${det.enderecoEntrega!.trim()}');
    }
    if (det?.motorista != null && det!.motorista!.trim().isNotEmpty) {
      linhasCabecalho.add('Motorista: ${det.motorista!.trim()}');
    }
    if (det?.previsaoEntrega != null && det!.previsaoEntrega!.trim().isNotEmpty) {
      linhasCabecalho.add('Previsão: ${det.previsaoEntrega!.trim()}');
    }

    // Resumo de pagamento (importante para o setor saber se cobra na entrega)
    String? linhaPagamento;
    if (det != null && det.formasPagamento.isNotEmpty) {
      final formas = det.formasPagamento.toSet().join(' + ');
      final status = det.pagamentoConcluido ? 'PAGO' : 'A RECEBER';
      linhaPagamento = '$formas — $status';
      if (!det.pagamentoConcluido && det.troco != null && det.troco! > 0) {
        linhaPagamento = '$linhaPagamento\nTroco: R\$ ${det.troco!.toStringAsFixed(2)}';
      }
    } else if (det != null && det.pagamentoConcluido) {
      linhaPagamento = 'PAGO';
    }

    pdf.addPage(
      pw.Page(
        pageFormat: const PdfPageFormat(
          80 * PdfPageFormat.mm,
          double.infinity,
          marginAll: 0,
        ),
        margin: const pw.EdgeInsets.all(8),
        build: (_) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.Center(
                child: pw.Text(
                  empresa.nomeExibicao,
                  style: pw.TextStyle(
                    fontSize: 11,
                    fontWeight: pw.FontWeight.bold,
                  ),
                  textAlign: pw.TextAlign.center,
                ),
              ),
              pw.SizedBox(height: 2),
              pw.Center(
                child: pw.Text(
                  tipoDocumento,
                  style: pw.TextStyle(
                    fontSize: 13,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.black,
                  ),
                  textAlign: pw.TextAlign.center,
                ),
              ),
              pw.Center(
                child: pw.Text(
                  'Nº $numeroDocumento',
                  style: pw.TextStyle(
                    fontSize: 11,
                    fontWeight: pw.FontWeight.bold,
                  ),
                  textAlign: pw.TextAlign.center,
                ),
              ),
              pw.Center(
                child: pw.Text(
                  'Data: ${formatoData.format(DateTime.now())}',
                  style: const pw.TextStyle(fontSize: 9),
                  textAlign: pw.TextAlign.center,
                ),
              ),
              // HORA DO PEDIDO (para a cozinha saber há quanto tempo)
              if (_horaPedido(det) != null)
                pw.Center(
                  child: pw.Text(
                    'Pedido: ${_horaPedido(det)!}  •  ${_tempoDecorrido(det)}',
                    style: pw.TextStyle(
                      fontSize: 11,
                      fontWeight: pw.FontWeight.bold,
                    ),
                    textAlign: pw.TextAlign.center,
                  ),
                ),
              // Garçom que lançou o pedido
              if (det?.usuarioCriou != null && det!.usuarioCriou!.trim().isNotEmpty)
                pw.Center(
                  child: pw.Text(
                    'Garçom: ${det.usuarioCriou!.trim()}',
                    style: const pw.TextStyle(fontSize: 9),
                    textAlign: pw.TextAlign.center,
                  ),
                ),
              if (linhasCabecalho.isNotEmpty) ...[
                pw.SizedBox(height: 4),
                pw.Divider(),
                pw.SizedBox(height: 4),
                for (final linha in linhasCabecalho)
                  pw.Text(
                    linha,
                    style: pw.TextStyle(
                      fontSize: 10,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                if (linhaPagamento != null) ...[
                  pw.SizedBox(height: 2),
                  pw.Text(
                    linhaPagamento,
                    style: pw.TextStyle(
                      fontSize: 10,
                      fontWeight: pw.FontWeight.bold,
                      color: det?.pagamentoConcluido == true
                          ? PdfColors.green800
                          : PdfColors.red800,
                    ),
                  ),
                ],
                if (det?.observacoesGerais != null &&
                    det!.observacoesGerais!.trim().isNotEmpty) ...[
                  pw.SizedBox(height: 2),
                  pw.Text(
                    'Obs: ${det.observacoesGerais!.trim()}',
                    style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey800),
                  ),
                ],
              ],
              pw.SizedBox(height: 4),
              pw.Divider(),
              pw.SizedBox(height: 4),
              for (var i = 0; i < itens.length; i++) ...[
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      '${i + 1}.',
                      style: pw.TextStyle(
                        fontSize: 11,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.SizedBox(width: 2),
                    pw.Expanded(
                      child: pw.Text(
                        '${_formatarQuantidade(itens[i].quantidade)}x  ${itens[i].nome}',
                        style: pw.TextStyle(
                          fontSize: 11,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                if (itens[i].adicionais.isNotEmpty)
                  pw.Text(
                    '   + ${itens[i].adicionais.join(', ')}',
                    style: const pw.TextStyle(fontSize: 9),
                  ),
                if (itens[i].opcoesCombo.isNotEmpty)
                  pw.Text(
                    '   > ${itens[i].opcoesCombo.join(', ')}',
                    style: const pw.TextStyle(fontSize: 9),
                  ),
                if (itens[i].observacao != null && itens[i].observacao!.trim().isNotEmpty)
                  pw.Text(
                    '   Obs: ${itens[i].observacao!.trim()}',
                    style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey800),
                  ),
                // Hora em que ESTE item foi lançado + quem lançou
                if (itens[i].dataHora != null ||
                    (itens[i].usuarioCriou != null && itens[i].usuarioCriou!.trim().isNotEmpty))
                  pw.Text(
                    '   ${_horaItem(itens[i])}',
                    style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
                  ),
                pw.SizedBox(height: 3),
              ],
              pw.SizedBox(height: 4),
              pw.Divider(),
              pw.SizedBox(height: 3),
              pw.Center(
                child: pw.Text(
                  'SETOR: $setor',
                  style: pw.TextStyle(
                    fontSize: 9,
                    fontWeight: pw.FontWeight.bold,
                  ),
                  textAlign: pw.TextAlign.center,
                ),
              ),
            ],
          );
        },
      ),
    );

    return await pdf.save();
  }

  static String _formatarQuantidade(double qtd) {
    if (qtd == qtd.roundToDouble()) {
      return qtd.toInt().toString();
    }
    return qtd.toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
  }

  static final DateFormat _formatoHora = DateFormat('HH:mm');

  /// Hora do pedido (HH:mm). Usa [DetalhesTicketProducao.dataPedido]; quando
  /// não informada, não exibe a linha (os chamadores devem preencher).
  static String? _horaPedido(DetalhesTicketProducao? det) {
    final data = det?.dataPedido;
    if (data == null) return null;
    return _formatoHora.format(data);
  }

  /// Tempo decorrido desde o pedido, em texto amigável (ex: "há 5 min").
  static String _tempoDecorrido(DetalhesTicketProducao? det) {
    final data = det?.dataPedido;
    if (data == null) return '';
    final diff = DateTime.now().difference(data);
    if (diff.inMinutes < 1) return 'agora';
    if (diff.inMinutes < 60) return 'há ${diff.inMinutes} min';
    final horas = diff.inHours;
    if (horas < 24) return 'há $horas h';
    return 'há ${diff.inDays} d';
  }

  /// Linha com hora e garçom de um item (ex: "14:32 • João").
  static String _horaItem(ItemProducaoInput item) {
    final partes = <String>[];
    if (item.dataHora != null) partes.add(_formatoHora.format(item.dataHora!));
    if (item.usuarioCriou != null && item.usuarioCriou!.trim().isNotEmpty) {
      partes.add(item.usuarioCriou!.trim());
    }
    return partes.join(' • ');
  }

  /// Imprime um TICKET DE TESTE nos DESTINOS informados.
  ///
  /// Gera um ticket de exemplo (com cliente, mesa, itens, pagamento — o mesmo
  /// layout da produção) e imprime UMA VIA POR DESTINO, ou seja, uma na
  /// impressora de cada setor de produção. Sem destino configurado, imprime na
  /// impressora padrão do terminal. Retorna a quantidade de tickets impressos.
  static Future<int> imprimirTicketTeste({
    required Empresa empresa,
    required DataService dataService,
    List<DestinoProducao> destinos = const [],
  }) async {
    // Nenhum setor com impressora configurada → confere o layout na padrão
    final alvos = destinos.isEmpty
        ? const <DestinoProducao>[
            DestinoProducao(setor: 'TERMINAL (PADRÃO)', impressora: ''),
          ]
        : destinos.toSet().toList();

    final itens = <ItemProducaoInput>[
      const ItemProducaoInput(
        id: 'teste-1',
        nome: 'X-Burger Completo',
        quantidade: 2,
        adicionais: ['Bacon extra', 'Queijo cheddar'],
      ),
      const ItemProducaoInput(
        id: 'teste-2',
        nome: 'Batata Frita Grande',
        quantidade: 1,
        observacao: 'Sem sal',
      ),
      const ItemProducaoInput(
        id: 'teste-3',
        nome: 'Refrigerante Lata 350ml',
        quantidade: 1,
        opcoesCombo: ['Coca-Cola'],
      ),
    ];

    final detalhes = const DetalhesTicketProducao(
      mesaComanda: 'MESA 5',
      clienteTelefone: '(12) 99999-9999',
      enderecoEntrega: 'Rua Teste, 123 - Centro',
      motorista: 'João (entregador)',
      previsaoEntrega: '30-45 min',
      formasPagamento: ['PIX'],
      troco: 5.50,
      pagamentoConcluido: true,
      observacoesGerais: 'TESTE DE IMPRESSÃO — verifique se o ticket saiu correto nesta impressora.',
    );

    var impressos = 0;
    for (final destino in alvos) {
      try {
        final bytes = await _gerarTicket(
          empresa: empresa,
          setor: destino.setor.isEmpty ? 'PRODUÇÃO' : destino.setor,
          numeroDocumento: 'TESTE-0001',
          tipoDocumento: 'TESTE DE PRODUÇÃO',
          clienteNome: 'Cliente Teste',
          itens: itens,
          detalhes: detalhes,
        );
        await ImpressaoService.imprimirPdfNaImpressora(
          bytes: bytes,
          nomeImpressora: destino.impressora,
          name: 'Teste_Producao_${destino.setor}',
          termico: true,
        );
        impressos++;
        debugPrint('[Producao] Ticket de teste do setor "${destino.setor}" '
            'impresso em "${destino.usaPadrao ? 'padrão' : destino.impressora}"');
      } catch (e) {
        debugPrint('[Producao] Erro no ticket de teste do setor '
            '"${destino.setor}" (${destino.impressora}): $e');
      }
    }
    return impressos;
  }

  /// Imprime os tickets de produção de uma venda/pedido.
  ///
  /// Resolve os DESTINOS (setor + impressora) de cada item: o departamento de
  /// preparação do produto e cada departamento extra marcado no produto viram um
  /// destino — ou seja, sai UMA VIA POR SETOR, na impressora daquele setor —
  /// mesmo quando dois setores usam a mesma impressora.
  ///
  /// Quando [setorForcado] é informado (o setor escolhido no lançamento, pelo
  /// nome ou pelo id), os itens também saem na impressora daquele departamento.
  /// Itens sem nenhum setor/impressora configurado são ignorados.
  ///
  /// Retorna a quantidade de tickets impressos (0 = nenhum destino
  /// configurado). Falhas em um destino não impedem os demais.
  ///
  /// Toda via que NÃO chega à impressora do setor entra na [fila] de produção
  /// (Monitor de Produção), com o motivo e o payload para reimprimir depois —
  /// inclusive quando a impressora do setor não existe no terminal e a via
  /// acaba saindo na impressora padrão.
  static Future<int> imprimirTicketsProducao({
    required List<ItemProducaoInput> itens,
    required DataService dataService,
    required Empresa empresa,
    required String numeroDocumento,
    String? clienteNome,
    bool isDelivery = false,
    DetalhesTicketProducao? detalhes,
    String? setorForcado,
    FilaProducaoService? fila,
  }) async {
    final filaEfetiva = fila ?? FilaProducaoService.instancia;
    if (itens.isEmpty) return 0;

    // Setor escolhido no lançamento (nome OU id do departamento)
    final nomeSetor = _limpar(setorForcado);
    debugPrint('[Producao] imprimirTicketsProducao: setorForcado="$setorForcado" '
        'itens=${itens.length}');
    final destinosSetor = nomeSetor == null
        ? const <DestinoProducao>[]
        : _destinosDoDepartamento(nomeSetor, dataService);
    if (nomeSetor != null) {
      debugPrint('[Producao] Destinos do setor "$nomeSetor": $destinosSetor');
    }

    final produtosPorId = <String, Produto>{};
    for (final p in dataService.produtos) {
      produtosPorId[p.id] = p;
    }

    // Destinos de cada produto (resolvido uma vez por produto, não por item)
    final destinosPorProdutoId = <String, List<DestinoProducao>>{};
    for (final item in itens) {
      if (destinosPorProdutoId.containsKey(item.id)) continue;
      final produto = produtosPorId[item.id];
      if (produto == null) {
        debugPrint('[Producao] ⚠️ Produto ${item.id} ("${item.nome}") não '
            'encontrado — setor não resolvido');
        destinosPorProdutoId[item.id] = const [];
        continue;
      }
      destinosPorProdutoId[item.id] = destinosDoProduto(
        produto: produto,
        dataService: dataService,
      );
    }

    // Agrupa os itens por DESTINO (setor + impressora): uma via por destino.
    final grupos = agruparPorDestino(
      itens: itens,
      destinosPorProdutoId: destinosPorProdutoId,
      destinosForcados: destinosSetor,
    );

    if (grupos.isEmpty) {
      debugPrint('[Producao] ⚠️ Nenhum setor/impressora de produção configurado '
          'para ${itens.length} itens');
      return 0;
    }
    debugPrint('[Producao] Vias a imprimir: '
        '${grupos.keys.map((d) => d.descricao).toList()}');

    final tipoDocumento = isDelivery ? 'PEDIDO DELIVERY' : 'PEDIDO DE PRODUÇÃO';
    var impressos = 0;

    for (final entry in grupos.entries) {
      final destino = entry.key;
      final itensDoSetor = entry.value;
      try {
        final bytes = await _gerarTicket(
          empresa: empresa,
          setor: destino.setor.isEmpty ? 'PRODUÇÃO' : destino.setor,
          numeroDocumento: numeroDocumento,
          tipoDocumento: tipoDocumento,
          clienteNome: clienteNome,
          itens: itensDoSetor,
          detalhes: detalhes,
        );
        final resultado = await ImpressaoService.imprimirPdfNaImpressora(
          bytes: bytes,
          nomeImpressora: destino.impressora,
          name: 'Producao_${numeroDocumento}_${destino.setor}',
          termico: true,
        );
        if (resultado.impresso) impressos++;

        if (resultado.saiuOndeFoiPedido(destino.usaPadrao)) {
          // Saiu no lugar certo: se havia uma pendência deste setor, sai da fila.
          await filaEfetiva.registrarSucesso(
            documento: numeroDocumento,
            setor: destino.setor,
            impressora: destino.impressora,
          );
          debugPrint('[Producao] Ticket do setor "${destino.setor}" impresso em '
              '"${destino.usaPadrao ? 'padrão do terminal' : destino.impressora}" '
              '(${itensDoSetor.length} itens)');
        } else {
          // Saiu noutro lugar (ou não saiu): a cozinha fica sem a via — entra na
          // fila para o operador reimprimir só este setor.
          final erro =
              resultado.aviso ?? 'A via não saiu na impressora do setor';
          await filaEfetiva.registrarFalha(_ticketDaFalha(
            destino: destino,
            itens: itensDoSetor,
            numeroDocumento: numeroDocumento,
            tipoDocumento: tipoDocumento,
            clienteNome: clienteNome,
            detalhes: detalhes,
            erro: erro,
          ));
          debugPrint('[Producao] ⚠️ Via do setor "${destino.setor}" não saiu na '
              'impressora do setor: $erro');
        }
      } catch (e) {
        await filaEfetiva.registrarFalha(_ticketDaFalha(
          destino: destino,
          itens: itensDoSetor,
          numeroDocumento: numeroDocumento,
          tipoDocumento: tipoDocumento,
          clienteNome: clienteNome,
          detalhes: detalhes,
          erro: '$e',
        ));
        debugPrint('[Producao] Erro ao imprimir o ticket do setor '
            '"${destino.setor}" (${destino.impressora}): $e');
      }
    }

    return impressos;
  }
}
