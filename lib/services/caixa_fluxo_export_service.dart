import 'dart:convert';
import 'dart:typed_data';

import 'package:intl/intl.dart';

// Salvamento do arquivo: download no navegador (web) ou arquivo temporário
// compartilhado no desktop/mobile (io).
import 'caixa_fluxo_export_web.dart' if (dart.library.io) 'caixa_fluxo_export_io.dart'
    as saver;

/// Uma linha do fluxo de caixa para exportação em CSV.
class LinhaFluxoExport {
  final DateTime data;
  final String tipo;
  final String descricao;
  final String forma;
  final double valor; // + entrada / - saída
  final bool contabilizado;

  const LinhaFluxoExport({
    required this.data,
    required this.tipo,
    required this.descricao,
    required this.forma,
    required this.valor,
    this.contabilizado = true,
  });
}

/// Exporta o Fluxo de Caixa (movimentações do dia/filtro atual) em CSV.
///
/// Usa ponto-e-vírgula como separador (padrão do Excel em português) e vírgula
/// como separador decimal, igual às outras exportações do sistema.
class CaixaFluxoExportService {
  static final DateFormat _formatoDia = DateFormat('dd/MM/yyyy');
  static final DateFormat _formatoHora = DateFormat('HH:mm');
  static final DateFormat _formatoDataHora = DateFormat('dd/MM/yyyy HH:mm');

  /// Monta o conteúdo CSV. Função pura (sem I/O) para poder ser testada.
  ///
  /// Só movimentações [LinhaFluxoExport.contabilizado] entram nos totais —
  /// mesas/comandas "a receber" aparecem como linha, mas não somam.
  static String construirCSV(
    List<LinhaFluxoExport> linhas, {
    String? caixa,
    DateTime? abertura,
  }) {
    final buffer = StringBuffer();
    buffer.writeln('FLUXO DE CAIXA${caixa != null && caixa.isNotEmpty ? ' - $caixa' : ''}');
    // Data e hora de abertura do caixa: sem ela não dá para saber a qual sessão
    // o CSV pertence (dois caixas do mesmo dia têm as mesmas movimentações).
    if (abertura != null) {
      buffer.writeln('Abertura do caixa;${_formatoDataHora.format(abertura.toLocal())}');
    }
    buffer.writeln('Gerado em;${_formatoDia.format(DateTime.now())} '
        '${_formatoHora.format(DateTime.now())}');
    buffer.writeln('');
    buffer.writeln('Data;Hora;Tipo;Descricao;Forma;Valor;Contabilizado');

    var entradas = 0.0;
    var saidas = 0.0;
    var contabilizadas = 0;
    var aReceber = 0;

    for (final l in linhas) {
      buffer.writeln([
        _formatoDia.format(l.data.toLocal()),
        _formatoHora.format(l.data.toLocal()),
        _fix(l.tipo),
        _fix(l.descricao),
        _fix(l.forma),
        _valor(l.valor),
        l.contabilizado ? 'Sim' : 'Nao',
      ].join(';'));

      if (!l.contabilizado) {
        aReceber++;
        continue;
      }
      contabilizadas++;
      if (l.valor >= 0) {
        entradas += l.valor;
      } else {
        saidas += -l.valor;
      }
    }

    buffer.writeln('');
    buffer.writeln('TOTAIS (somente contabilizadas)');
    buffer.writeln('Movimentacoes;$contabilizadas');
    buffer.writeln('Entradas;${_valor(entradas)}');
    buffer.writeln('Saidas;${_valor(saidas)}');
    buffer.writeln('Saldo;${_valor(entradas - saidas)}');
    if (aReceber > 0) {
      buffer.writeln('A receber (nao contabilizadas);$aReceber');
    }

    return buffer.toString();
  }

  /// Gera e entrega o CSV (download na web, arquivo compartilhado no desktop).
  ///
  /// Retorna o nome/caminho do arquivo gerado, ou `null` se nada foi salvo.
  static Future<String?> exportar(
    List<LinhaFluxoExport> linhas, {
    String? caixa,
    DateTime? abertura,
  }) async {
    final conteudo = construirCSV(linhas, caixa: caixa, abertura: abertura);
    final bytes = Uint8List.fromList(utf8.encode(conteudo));
    final nome = 'fluxo_caixa_${DateTime.now().millisecondsSinceEpoch}.csv';
    return saver.salvarArquivoCSV(bytes, nome);
  }

  static String _fix(String texto) =>
      texto.replaceAll('\n', ' ').replaceAll(';', ',').trim();

  static String _valor(double v) => v.toStringAsFixed(2).replaceAll('.', ',');
}
