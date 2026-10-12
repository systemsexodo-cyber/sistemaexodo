import 'dart:typed_data';

import '../pages/html_helper_web.dart';

/// Salva o CSV do fluxo de caixa no navegador (dispara o download).
Future<String?> salvarArquivoCSV(Uint8List bytes, String nomeArquivo) async {
  downloadBytes(bytes, nomeArquivo, 'text/csv;charset=utf-8');
  return nomeArquivo;
}
