import 'dart:convert';
import 'dart:typed_data';

import 'package:barcode/barcode.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/empresa.dart';
import '../models/produto.dart';
import '../utils/perfis_tributarios_merge.dart' show chaveEtiquetas, chaveEtiquetasAtualizadoEm;
import 'impressao_service.dart';

/// Tamanhos de etiqueta mais comuns no varejo (em milímetros).
class EtiquetaTamanho {
  /// 50x30mm - Mais comum para precificação de produtos no varejo.
  static const EtiquetaTamanho precoPadrao =
      EtiquetaTamanho._(50, 30, '50 × 30 mm • Padrão varejo');

  /// 60x40mm - Etiqueta maior, com mais espaço para informações.
  static const EtiquetaTamanho grande =
      EtiquetaTamanho._(60, 40, '60 × 40 mm • Mais informações');

  /// 40x40mm - Quadrada, usada para produtos pequenos.
  static const EtiquetaTamanho quadrada =
      EtiquetaTamanho._(40, 40, '40 × 40 mm • Quadrada');

  /// 50x25mm - Compacta.
  static const EtiquetaTamanho compacta =
      EtiquetaTamanho._(50, 25, '50 × 25 mm • Compacta');

  /// 33x21mm - Mini etiqueta para amostras/mini produtos.
  static const EtiquetaTamanho mini =
      EtiquetaTamanho._(33, 21, '33 × 21 mm • Mini');

  // ─────────── Folhas A4 (2 e 3 colunas) e formatos de gôndola ───────────

  /// 99,1x38,1mm - Folha A4 em 2 colunas (2 × 7 = 14 etiquetas).
  /// É a medida clássica de folha em 2 colunas usada no varejo.
  static const EtiquetaTamanho duasColunas =
      EtiquetaTamanho._(99.1, 38.1, '99 × 38 mm • 2 colunas (A4 · 2×7)');

  /// 99,1x33,9mm - Folha A4 em 2 colunas mais baixa (2 × 8 = 16 etiquetas).
  static const EtiquetaTamanho duasColunasFina =
      EtiquetaTamanho._(99.1, 33.9, '99 × 34 mm • 2 colunas (A4 · 2×8)');

  /// 100x50mm - Folha A4 em 2 colunas largas (2 × 5 = 10 etiquetas).
  static const EtiquetaTamanho duasColunasGrande =
      EtiquetaTamanho._(100, 50, '100 × 50 mm • 2 colunas (A4 · 2×5)');

  /// 63,5x38,1mm - Folha A4 em 3 colunas (3 × 7 = 21 etiquetas).
  static const EtiquetaTamanho tresColunas =
      EtiquetaTamanho._(63.5, 38.1, '63 × 38 mm • 3 colunas (A4 · 3×7)');

  /// 70x35mm - Etiqueta de gôndola/prateleira: preço grande + código de barras.
  static const EtiquetaTamanho gondola =
      EtiquetaTamanho._(70, 35, '70 × 35 mm • Gôndola');

  /// 100x30mm - Fita de gôndola, uma linha de produto por etiqueta.
  static const EtiquetaTamanho fita =
      EtiquetaTamanho._(100, 30, '100 × 30 mm • Fita / gôndola');

  /// Modelos prontos mostrados no editor, do mais usado para o mais específico.
  static const List<EtiquetaTamanho> todos = [
    precoPadrao,
    grande,
    quadrada,
    compacta,
    mini,
    gondola,
    fita,
    duasColunas,
    duasColunasFina,
    duasColunasGrande,
    tresColunas,
  ];

  final double larguramm;
  final double alturamm;
  final String rotulo;

  const EtiquetaTamanho._(this.larguramm, this.alturamm, this.rotulo);

  /// Configuração completa com margens e fontes proporcionais a este tamanho.
  EtiquetaConfig get configuracaoPadrao => EtiquetaConfig(
        larguramm: larguramm,
        alturamm: alturamm,
        margemEsqmm: _margem,
        margemDirmm: _margem,
        margemVmm: _margem,
        fonteTitulo: _fonteTitulo,
        fonteCorpo: _fonteCorpo,
      );

  /// 5% da largura, entre 2 e 6 mm.
  double get _margem => (larguramm * 0.05).clamp(2.0, 6.0).toDouble();

  /// Fonte do nome do produto, proporcional à largura (base: 50 mm).
  double get _fonteTitulo =>
      (larguramm / 50.0 * 9.0).clamp(7.0, 14.0).toDouble();

  /// Fonte dos demais textos, proporcional à largura (base: 50 mm).
  double get _fonteCorpo => (larguramm / 50.0 * 7.0).clamp(5.0, 11.0).toDouble();
}

/// Configuração de layout de uma etiqueta.
class EtiquetaConfig {
  /// Largura da etiqueta em mm.
  final double larguramm;

  /// Altura da etiqueta em mm.
  final double alturamm;

  /// Margem esquerda em mm.
  final double margemEsqmm;

  /// Margem direita em mm.
  final double margemDirmm;

  /// Margem superior/inferior em mm.
  final double margemVmm;

  /// Fonte do nome do produto, em pt.
  final double fonteTitulo;

  /// Fonte dos demais textos, em pt.
  final double fonteCorpo;

  /// Quantidade de cópias por produto.
  final int quantidade;

  const EtiquetaConfig({
    this.larguramm = 50.0,
    this.alturamm = 30.0,
    this.margemEsqmm = 5.0,
    this.margemDirmm = 5.0,
    this.margemVmm = 5.0,
    this.fonteTitulo = 10.0,
    this.fonteCorpo = 8.0,
    this.quantidade = 1,
  });

  /// Converte milímetros em pontos (1 mm = 2,83465 pt).
  static const double _mmParaPt = 2.83465;

  double get larguraPt => larguramm * _mmParaPt;
  double get alturaPt => alturamm * _mmParaPt;
  double get margemEsqPt => margemEsqmm * _mmParaPt;
  double get margemDirPt => margemDirmm * _mmParaPt;
  double get margemVPt => margemVmm * _mmParaPt;

  /// Largura útil (descontando as margens laterais), em pontos.
  double get larguraUtilPt => larguraPt - margemEsqPt - margemDirPt;

  /// Altura útil (descontando as margens superior/inferior), em pontos.
  double get alturaUtilPt => alturaPt - (margemVPt * 2);

  EtiquetaConfig copyWith({
    double? larguramm,
    double? alturamm,
    double? margemEsqmm,
    double? margemDirmm,
    double? margemVmm,
    double? fonteTitulo,
    double? fonteCorpo,
    int? quantidade,
  }) {
    return EtiquetaConfig(
      larguramm: larguramm ?? this.larguramm,
      alturamm: alturamm ?? this.alturamm,
      margemEsqmm: margemEsqmm ?? this.margemEsqmm,
      margemDirmm: margemDirmm ?? this.margemDirmm,
      margemVmm: margemVmm ?? this.margemVmm,
      fonteTitulo: fonteTitulo ?? this.fonteTitulo,
      fonteCorpo: fonteCorpo ?? this.fonteCorpo,
      quantidade: quantidade ?? this.quantidade,
    );
  }

  Map<String, dynamic> toMap() => {
        'larguramm': larguramm,
        'alturamm': alturamm,
        'margemEsqmm': margemEsqmm,
        'margemDirmm': margemDirmm,
        'margemVmm': margemVmm,
        'fonteTitulo': fonteTitulo,
        'fonteCorpo': fonteCorpo,
        'quantidade': quantidade,
      };

  factory EtiquetaConfig.fromMap(Map<String, dynamic> mapa) {
    double ler(String chave, double padrao) {
      final valor = mapa[chave];
      return valor is num ? valor.toDouble() : padrao;
    }

    final quantidade = mapa['quantidade'];
    return EtiquetaConfig(
      larguramm: ler('larguramm', 50),
      alturamm: ler('alturamm', 30),
      margemEsqmm: ler('margemEsqmm', 5),
      margemDirmm: ler('margemDirmm', 5),
      margemVmm: ler('margemVmm', 5),
      fonteTitulo: ler('fonteTitulo', 10),
      fonteCorpo: ler('fonteCorpo', 8),
      quantidade: quantidade is num ? quantidade.toInt() : 1,
    );
  }
}

/// Guarda o último modelo de etiqueta usado por empresa, no próprio terminal.
///
/// É a mesma ideia da impressora padrão: cada máquina lembra o que o operador
/// escolheu naquela empresa, sem precisar mexer no cadastro.
class EtiquetaConfigStorage {
  static const String _prefixo = 'etiqueta_config_';

  static String _chave(String empresaId) => '$_prefixo$empresaId';

  static Future<EtiquetaConfig?> carregar(String empresaId) async {
    final prefs = await SharedPreferences.getInstance();
    final bruto = prefs.getString(_chave(empresaId));
    if (bruto == null || bruto.isEmpty) return null;
    try {
      final mapa = jsonDecode(bruto) as Map<String, dynamic>;
      return EtiquetaConfig.fromMap(mapa);
    } catch (_) {
      return null;
    }
  }

  static Future<void> salvar(String empresaId, EtiquetaConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_chave(empresaId), jsonEncode(config.toMap()));
  }
}

/// Modelo de etiqueta com nome, salvo pelo operador.
///
/// Diferente do último uso (que é sobrescrito a cada impressão), um modelo
/// nomeado fica guardado até o operador apagá-lo.
class EtiquetaModelo {
  final String nome;
  final EtiquetaConfig config;

  const EtiquetaModelo({required this.nome, required this.config});

  Map<String, dynamic> toMap() => {'nome': nome, 'config': config.toMap()};

  factory EtiquetaModelo.fromMap(Map<String, dynamic> mapa) {
    final nome = mapa['nome'];
    final config = mapa['config'];
    return EtiquetaModelo(
      nome: nome is String ? nome : '',
      // Vem do JSON do banco, onde o mapa pode chegar como Map<dynamic,dynamic>.
      config: config is Map
          ? EtiquetaConfig.fromMap(Map<String, dynamic>.from(config))
          : const EtiquetaConfig(),
    );
  }
}

/// Guarda os modelos de etiqueta nomeados POR EMPRESA no banco de dados.
///
/// A fonte da verdade é `empresa.configuracoes['etiquetas']`, que o sistema
/// já persiste no PostgreSQL local (JSONB) e na nuvem (Supabase) — e que é
/// mesclada local × nuvem pelo carimbo `etiquetas_atualizado_em`, igual aos
/// perfis de preço.
///
/// O SharedPreferences continua sendo espelho: serve para ler modelos
/// gravados por versões antigas (legado) e para mostrar algo quando a
/// empresa ainda não foi carregada.
class EtiquetaModeloStorage {
  static const String _prefixo = 'etiqueta_modelos_';
  static const int _limite = 30;

  static String _chave(String empresaId) => '$_prefixo$empresaId';

  /// Modelos gravados no banco (configurações da empresa).
  ///
  /// Quando a empresa ainda não tem a chave `etiquetas` (nunca gravou por
  /// aqui), devolve `null` — assim o chamador pode tentar o espelho local.
  static List<EtiquetaModelo>? ler(Map<String, dynamic>? configuracoes) {
    final bruto = configuracoes?[chaveEtiquetas];
    if (bruto is! List) return null;
    return bruto
        .whereType<Map>()
        .map((item) => EtiquetaModelo.fromMap(Map<String, dynamic>.from(item)))
        .where((modelo) => modelo.nome.isNotEmpty)
        .take(_limite)
        .toList();
  }

  /// Monta a PRÓXIMA configuração da empresa com [modelos] gravados e o
  /// carimbo de atualização (para o merge local × nuvem saber quem é mais
  /// novo). Não altera o mapa recebido.
  static Map<String, dynamic> gravar(
    Map<String, dynamic>? configuracoes,
    List<EtiquetaModelo> modelos,
  ) {
    final atual = configuracoes != null
        ? Map<String, dynamic>.from(configuracoes)
        : <String, dynamic>{};
    atual[chaveEtiquetas] = modelos
        .take(_limite)
        .map((modelo) => modelo.toMap())
        .toList();
    atual[chaveEtiquetasAtualizadoEm] = DateTime.now().toUtc().toIso8601String();
    return atual;
  }

  // ══════════════════ espelho local (SharedPreferences) ══════════════════

  /// Espelho local: modelos gravados por versões antigas do app.
  static Future<List<EtiquetaModelo>> listarLocal(String empresaId) async {
    final prefs = await SharedPreferences.getInstance();
    final bruto = prefs.getString(_chave(empresaId));
    if (bruto == null || bruto.isEmpty) return [];
    try {
      final lista = jsonDecode(bruto) as List<dynamic>;
      return lista
          .whereType<Map<String, dynamic>>()
          .map(EtiquetaModelo.fromMap)
          .where((modelo) => modelo.nome.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Atualiza o espelho local, para o terminal continuar vendo os modelos
  /// mesmo sem empresa carregada.
  static Future<void> espelharLocal(
    String empresaId,
    List<EtiquetaModelo> modelos,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    if (modelos.isEmpty) {
      await prefs.remove(_chave(empresaId));
      return;
    }
    await prefs.setString(
      _chave(empresaId),
      jsonEncode(modelos.map((m) => m.toMap()).toList()),
    );
  }
}

/// Código e simbologia desenhados na etiqueta.
class CodigoBarrasEtiqueta {
  final String dados;
  final Barcode simbolo;

  const CodigoBarrasEtiqueta(this.dados, this.simbolo);
}

/// Geração e impressão de etiquetas de preço.
class EtiquetaService {
  static final NumberFormat _moeda =
      NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');

  /// Gera o PDF das etiquetas: uma página por cópia de cada produto, no
  /// tamanho exato pedido.
  static Future<Uint8List> gerarEtiquetasPDF({
    required List<Produto> produtos,
    required EtiquetaConfig config,
    Empresa? empresa,
  }) async {
    if (produtos.isEmpty) {
      throw ArgumentError('Nenhum produto para etiquetar');
    }

    final pdf = pw.Document();

    final larguraPt = config.larguraPt;
    final alturaPt = config.alturaPt;
    final margemEsq = _limitarMargem(config.margemEsqPt, larguraPt);
    final margemDir = _limitarMargem(config.margemDirPt, larguraPt);
    final margemV = _limitarMargem(config.margemVPt, alturaPt);
    final quantidade =
        config.quantidade < 1 ? 1 : (config.quantidade > 99 ? 99 : config.quantidade);

    for (final produto in produtos) {
      for (var copia = 0; copia < quantidade; copia++) {
        pdf.addPage(
          pw.Page(
            pageFormat: PdfPageFormat(larguraPt, alturaPt, marginAll: 0),
            build: (pw.Context contexto) => pw.Container(
              padding: pw.EdgeInsets.fromLTRB(
                margemEsq,
                margemV,
                margemDir,
                margemV,
              ),
              child: _conteudoDaEtiqueta(
                produto: produto,
                config: config,
                empresa: empresa,
              ),
            ),
          ),
        );
      }
    }

    return pdf.save();
  }

  /// Margem nunca pode passar de 1/3 da dimensão, senão o conteúdo não cabe.
  static double _limitarMargem(double margem, double dimensao) =>
      margem.clamp(0.0, dimensao / 3).toDouble();

  static pw.Widget _conteudoDaEtiqueta({
    required Produto produto,
    required EtiquetaConfig config,
    Empresa? empresa,
  }) {
    final preco = produto.precoAtual;
    final temPromocao = produto.promocaoAtiva && preco < produto.preco;
    final unidade = produto.unidadeVenda.trim();
    final nomeEmpresa = empresa?.nomeExibicao.trim();
    final codigo = codigoDeBarras(produto);

    final fontePreco =
        (config.fonteCorpo * 2).clamp(config.fonteCorpo + 3, 30).toDouble();
    final fonteDetalhe = (config.fonteCorpo - 2).clamp(4.0, 10.0).toDouble();

    final precoTexto = produto.vendaFracionada && unidade.isNotEmpty
        ? '${_moeda.format(preco)} / $unidade'
        : _moeda.format(preco);

    final alturaCodigo =
        (config.alturaUtilPt * 0.28).clamp(10.0, 30.0).toDouble();

    return pw.FittedBox(
      fit: pw.BoxFit.scaleDown,
      child: pw.Column(
        mainAxisSize: pw.MainAxisSize.min,
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Text(
            produto.nome.toUpperCase(),
            textAlign: pw.TextAlign.center,
            maxLines: 2,
            overflow: pw.TextOverflow.clip,
            style: pw.TextStyle(
              fontSize: config.fonteTitulo,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          if (temPromocao) ...[
            pw.SizedBox(height: 1),
            pw.Text(
              'de ${_moeda.format(produto.preco)}',
              textAlign: pw.TextAlign.center,
              maxLines: 1,
              style: pw.TextStyle(
                fontSize: fonteDetalhe,
                decoration: pw.TextDecoration.lineThrough,
              ),
            ),
          ],
          pw.SizedBox(height: 1),
          pw.Text(
            precoTexto,
            textAlign: pw.TextAlign.center,
            maxLines: 1,
            style: pw.TextStyle(
              fontSize: fontePreco,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          if (codigo != null) ...[
            pw.SizedBox(height: 2),
            pw.BarcodeWidget(
              barcode: codigo.simbolo,
              data: codigo.dados,
              width: config.larguraUtilPt,
              height: alturaCodigo,
              drawText: false,
            ),
            pw.SizedBox(height: 1),
            pw.Text(
              codigo.dados,
              textAlign: pw.TextAlign.center,
              maxLines: 1,
              style: pw.TextStyle(
                fontSize: fonteDetalhe,
                color: PdfColors.grey700,
              ),
            ),
          ],
          if (nomeEmpresa != null && nomeEmpresa.isNotEmpty) ...[
            pw.SizedBox(height: 1),
            pw.Text(
              nomeEmpresa,
              textAlign: pw.TextAlign.center,
              maxLines: 1,
              style: pw.TextStyle(
                fontSize: fonteDetalhe,
                color: PdfColors.grey600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Código de barras a desenhar na etiqueta.
  ///
  /// Usa EAN-13/EAN-8 quando o código é um código de barras de varejo válido
  /// (incluindo o dígito verificador), porque esses símbolos cabem em etiquetas
  /// estreitas. Para os demais códigos, usa Code128. Retorna `null` quando não
  /// há código imprimível.
  static CodigoBarrasEtiqueta? codigoDeBarras(Produto produto) {
    final candidatos = [
      produto.codigoBarras,
      produto.codigo,
      ...produto.codigosBarrasAdicionais,
    ];

    for (final candidato in candidatos) {
      final dados = (candidato ?? '').trim();
      if (dados.isEmpty) continue;
      if (!_somenteAscii(dados)) continue;

      if (_eanValido(dados, 13)) {
        return CodigoBarrasEtiqueta(dados, Barcode.ean13());
      }
      if (_eanValido(dados, 8)) {
        return CodigoBarrasEtiqueta(dados, Barcode.ean8());
      }
      return CodigoBarrasEtiqueta(dados, Barcode.code128());
    }
    return null;
  }

  static bool _somenteAscii(String texto) =>
      texto.codeUnits.every((codigo) => codigo >= 32 && codigo <= 126);

  /// Valida o dígito verificador de EAN-13/EAN-8.
  static bool _eanValido(String codigo, int tamanho) {
    if (codigo.length != tamanho) return false;
    final digitos = <int>[];
    for (final caractere in codigo.split('')) {
      final digito = int.tryParse(caractere);
      if (digito == null) return false;
      digitos.add(digito);
    }

    final verificador = digitos.removeLast();
    var soma = 0;
    for (var i = 0; i < digitos.length; i++) {
      // Peso 3 nas posições ímpares contando da direita.
      final peso = (digitos.length - i).isOdd ? 3 : 1;
      soma += digitos[i] * peso;
    }
    return (10 - (soma % 10)) % 10 == verificador;
  }

  /// Gera e envia as etiquetas para a impressão.
  ///
  /// O [ImpressaoService] usa a impressora configurada na empresa/terminal e
  /// cai no diálogo do sistema quando não há impressora salva.
  static Future<void> imprimirEtiquetas({
    required BuildContext context,
    required List<Produto> produtos,
    required EtiquetaConfig config,
    required Empresa empresa,
    bool termico = true,
  }) async {
    final bytes = await gerarEtiquetasPDF(
      produtos: produtos,
      config: config,
      empresa: empresa,
    );

    // Se a tela já fechou durante a geração do PDF, não há o que imprimir.
    if (!context.mounted) return;

    final identificacao = produtos.length == 1
        ? (produtos.first.codigo ?? produtos.first.id)
        : '${produtos.length}_produtos';

    await ImpressaoService.imprimirPdf(
      bytes: bytes,
      empresa: empresa,
      name: 'Etiquetas_$identificacao',
      termico: termico,
      context: context,
    );
  }
}
