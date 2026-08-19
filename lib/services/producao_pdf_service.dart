import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/departamento.dart';
import '../models/empresa.dart';
import '../models/produto.dart';
import 'data_service.dart';
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

/// Serviço de impressão de TICKETS DE PRODUÇÃO.
///
/// Cada produto pode ter uma impressora de produção configurada
/// (`impressoraProducao` / `impressoraProducaoExtra`, direto no produto ou no
/// departamento). Ao salvar uma venda ou lançar um pedido de delivery, os
/// itens são agrupados por impressora e cada grupo imprime um ticket térmico
/// (80mm) NA impressora correspondente do setor (Cozinha, Bar, etc.).
class ProducaoPdfService {
  static String? _limpar(String? valor) {
    if (valor == null) return null;
    final v = valor.trim();
    return v.isEmpty ? null : v;
  }

  /// Resolve a lista de impressoras de produção de um produto.
  ///
  /// A impressão sai no DEPARTAMENTO do produto (impressora configurada no
  /// departamento) e em cada departamento adicional selecionado no produto
  /// (`departamentosAdicionais` — multi-seleção). Dados legados
  /// (`impressoraProducao`/`impressoraProducaoExtra` direto no produto)
  /// continuam valendo quando não há departamentos configurados.
  static List<String> _impressorasDoItem({
    required String produtoId,
    required DataService dataService,
  }) {
    Produto? produto;
    for (final p in dataService.produtos) {
      if (p.id == produtoId) {
        produto = p;
        break;
      }
    }
    if (produto == null) return const [];

    final setores = <String>{};

    // Mapa id -> departamento para resolução rápida
    final depsPorId = <String, Departamento>{};
    for (final d in dataService.departamentos) {
      depsPorId[d.id] = d;
    }

    void adicionarDepartamento(String? deptId) {
      if (deptId == null || deptId.isEmpty) return;
      final dept = depsPorId[deptId];
      if (dept == null) return;
      final principal = _limpar(dept.impressoraProducao);
      if (principal != null) setores.add(principal);
      for (final e in dept.impressoraProducaoExtra) {
        final nome = _limpar(e);
        if (nome != null) setores.add(nome);
      }
    }

    // Departamento principal do produto
    adicionarDepartamento(produto.departamentoId);
    // Departamentos adicionais (multi-impressão por departamento)
    for (final id in produto.departamentosAdicionais) {
      adicionarDepartamento(id);
    }

    // Legado: impressora configurada direto no produto (sem departamento)
    if (setores.isEmpty || produto.departamentoId == null) {
      final principal = _limpar(produto.impressoraProducao);
      if (principal != null) setores.add(principal);
      for (final e in produto.impressoraProducaoExtra) {
        final nome = _limpar(e);
        if (nome != null) setores.add(nome);
      }
    }

    return setores.toList();
  }

  /// Resolve a(s) impressora(s) de um DEPARTAMENTO pelo NOME (ex: "Cozinha",
  /// "Bar"). Usado quando o garçom escolhe o setor no lançamento: a impressão
  /// sai na impressora configurada naquele departamento, em vez de resolver
  /// produto por produto.
  static List<String> _impressorasDoDepartamentoPorNome(
    String nomeSetor,
    DataService dataService,
  ) {
    Departamento? dep;
    final alvo = nomeSetor.trim().toLowerCase();
    for (final d in dataService.departamentos) {
      if (d.nome.trim().toLowerCase() == alvo) {
        dep = d;
        break;
      }
    }
    if (dep == null) return const [];

    final setores = <String>{};
    final principal = _limpar(dep.impressoraProducao);
    if (principal != null) setores.add(principal);
    for (final e in dep.impressoraProducaoExtra) {
      final nome = _limpar(e);
      if (nome != null) setores.add(nome);
    }
    return setores.toList();
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

  /// Imprime um TICKET DE TESTE nas impressoras informadas.
  ///
  /// Gera um ticket de exemplo (com cliente, mesa, itens, pagamento — o
  /// mesmo layout da produção) e imprime em cada impressora da lista. Se a
  /// lista vier vazia, imprime na impressora padrão do terminal.
  /// Retorna a quantidade de tickets impressos.
  static Future<int> imprimirTicketTeste({
    required Empresa empresa,
    required List<String> impressoras,
    required DataService dataService,
  }) async {
    final alvos = impressoras
        .map((e) => _limpar(e))
        .whereType<String>()
        .toSet()
        .toList();

    // Nenhuma impressora de produção configurada → usa a padrão do terminal
    final impressorasAlvo = alvos.isEmpty ? <String>[''] : alvos;

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
    for (final imp in impressorasAlvo) {
      try {
        final bytes = await _gerarTicket(
          empresa: empresa,
          setor: imp.isEmpty ? 'TERMINAL (PADRÃO)' : imp,
          numeroDocumento: 'TESTE-0001',
          tipoDocumento: 'TESTE DE PRODUÇÃO',
          clienteNome: 'Cliente Teste',
          itens: itens,
          detalhes: detalhes,
        );
        await ImpressaoService.imprimirPdfNaImpressora(
          bytes: bytes,
          nomeImpressora: imp,
          name: 'Teste_Producao',
          termico: true,
        );
        impressos++;
        debugPrint('[Producao] Ticket de teste impresso em "${imp.isEmpty ? 'padrão' : imp}"');
      } catch (e) {
        debugPrint('[Producao] Erro no ticket de teste em "$imp": $e');
      }
    }
    return impressos;
  }

  /// Imprime os tickets de produção de uma venda/pedido.
  ///
  /// Agrupa os itens pela impressora de produção configurada em cada produto
  /// (ou no departamento) e envia um ticket térmico para CADA impressora
  /// correspondente. Itens sem impressora de produção são ignorados.
  ///
  /// Quando [setorForcado] é informado (ex: "Cozinha" — o setor que o garçom
  /// escolheu no lançamento), os itens são impressos na impressora configurada
  /// NAQUELE departamento. Produtos com departamentos adicionais
  /// (`departamentosAdicionais`) também imprimem nas impressoras desses
  /// departamentos extras. Se o departamento do setor não tiver impressora,
  /// vale a resolução por produto.
  ///
  /// Retorna a quantidade de tickets impressos (0 = nenhum item com impressora
  /// de produção configurada). Falhas em uma impressora não impedem as demais.
  static Future<int> imprimirTicketsProducao({
    required List<ItemProducaoInput> itens,
    required DataService dataService,
    required Empresa empresa,
    required String numeroDocumento,
    String? clienteNome,
    bool isDelivery = false,
    DetalhesTicketProducao? detalhes,
    String? setorForcado,
  }) async {
    if (itens.isEmpty) return 0;

    // Agrupar itens por impressora de produção
    final porImpressora = <String, List<ItemProducaoInput>>{};

    // Setor forçado: usa a impressora do DEPARTAMENTO com esse nome
    final nomeSetor = _limpar(setorForcado);
    if (nomeSetor != null) {
      final impressorasSetor =
          _impressorasDoDepartamentoPorNome(nomeSetor, dataService);
      if (impressorasSetor.isNotEmpty) {
        for (final item in itens) {
          for (final imp in impressorasSetor) {
            porImpressora.putIfAbsent(imp, () => []).add(item);
          }
          // Departamentos adicionais do produto continuam imprimindo
          for (final imp in _impressorasDoItem(
            produtoId: item.id,
            dataService: dataService,
          )) {
            porImpressora.putIfAbsent(imp, () => []).add(item);
          }
        }
      }
    }

    // Fallback (sem setor forçado ou departamento sem impressora):
    // resolução normal por produto
    if (porImpressora.isEmpty) {
      for (final item in itens) {
        final impressoras = _impressorasDoItem(
          produtoId: item.id,
          dataService: dataService,
        );
        if (impressoras.isEmpty) continue;
        for (final imp in impressoras) {
          porImpressora.putIfAbsent(imp, () => []).add(item);
        }
      }
    }

    if (porImpressora.isEmpty) return 0;

    final tipoDocumento = isDelivery ? 'PEDIDO DELIVERY' : 'PEDIDO DE PRODUÇÃO';
    var impressos = 0;

    for (final entry in porImpressora.entries) {
      try {
        final bytes = await _gerarTicket(
          empresa: empresa,
          setor: nomeSetor ?? entry.key,
          numeroDocumento: numeroDocumento,
          tipoDocumento: tipoDocumento,
          clienteNome: clienteNome,
          itens: entry.value,
          detalhes: detalhes,
        );
        await ImpressaoService.imprimirPdfNaImpressora(
          bytes: bytes,
          nomeImpressora: entry.key,
          name: 'Producao_${numeroDocumento}_${entry.key}',
          termico: true,
        );
        impressos++;
        debugPrint('[Producao] Ticket impresso na impressora "${entry.key}" '
            '(${entry.value.length} itens)');
      } catch (e) {
        debugPrint('[Producao] Erro ao imprimir ticket na impressora '
            '"${entry.key}": $e');
      }
    }

    return impressos;
  }
}
