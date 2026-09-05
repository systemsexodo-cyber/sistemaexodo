import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/nfce.dart';
import '../models/empresa.dart';

/// Serviço responsável por salvar XMLs e PDFs de NFC-e automaticamente
/// em C:\ExodoNFCe\[CNPJ]\[YYYY-MM]\ ao emitir ou autorizar uma nota.
class NfceXmlLocalService {
  static const String _pastaBase = r'C:\ExodoNFCe';

  /// Salva o XML da NFC-e automaticamente após emissão autorizada.
  /// Roda em background (fire-and-forget) para não bloquear o fluxo.
  static Future<void> salvarXmlAposEmissao({
    required NFCe nfce,
    required Empresa empresa,
  }) async {
    // Só executar em plataformas desktop (Windows/Linux/Mac)
    if (kIsWeb) return;
    if (!Platform.isWindows) return;

    // Só salvar se a nota foi autorizada
    final status = nfce.status?.toLowerCase() ?? '';
    if (status != 'autorizada' && status != 'sucesso') return;

    try {
      final xml = (nfce.xmlEnviado ?? '').trim();
      if (xml.isEmpty) {
        debugPrint('[NfceXml] XML vazio, nada para salvar.');
        return;
      }

      final dt = nfce.createdAt ?? nfce.dataEmissao;
      final mesDir = '${dt.year}-${dt.month.toString().padLeft(2, '0')}';
      final cnpj = (empresa.cnpj ?? '').replaceAll(RegExp(r'[^0-9]'), '');

      // Pasta: C:\ExodoNFCe\[CNPJ]\[YYYY-MM]
      final dir = Directory('$_pastaBase\\$cnpj\\$mesDir');
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }

      // Nome do arquivo: [CHAVE]-nfe.xml ou NFCe_[NUMERO]-nfe.xml
      final nomeArquivo = (nfce.chaveAcesso != null && nfce.chaveAcesso!.isNotEmpty)
          ? '${nfce.chaveAcesso}-nfe.xml'
          : 'NFCe_${nfce.numero ?? nfce.id}-nfe.xml';

      final arquivoXml = File('${dir.path}\\$nomeArquivo');

      // Só escreve se ainda não existir (evita sobrescrever versão com protocolo)
      if (!arquivoXml.existsSync()) {
        arquivoXml.writeAsStringSync(xml, encoding: utf8);
        debugPrint('[NfceXml] ✅ XML salvo em: ${arquivoXml.path}');
      } else {
        debugPrint('[NfceXml] XML já existe, ignorando: ${arquivoXml.path}');
      }
    } catch (e) {
      // Não lança exceção — falha silenciosa para não prejudicar o fluxo de venda
      debugPrint('[NfceXml] ⚠️ Falha ao salvar XML local: $e');
    }
  }
}
