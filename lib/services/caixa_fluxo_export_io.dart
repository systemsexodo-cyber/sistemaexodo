import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Salva o CSV do fluxo de caixa em arquivo temporário e abre o
/// compartilhamento (desktop/mobile) — mesmo padrão usado no DANFE.
Future<String?> salvarArquivoCSV(Uint8List bytes, String nomeArquivo) async {
  final diretorio = await getTemporaryDirectory();
  final arquivo = File('${diretorio.path}/$nomeArquivo');
  await arquivo.writeAsBytes(bytes, flush: true);
  await Share.shareXFiles(
    [XFile(arquivo.path)],
    text: 'Fluxo de caixa',
  );
  return arquivo.path;
}
