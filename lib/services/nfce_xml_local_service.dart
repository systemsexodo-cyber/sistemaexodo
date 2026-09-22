import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions;
import '../models/nfce.dart';
import '../models/empresa.dart';
import 'supabase_service.dart';

/// Serviço responsável por salvar XMLs e PDFs de NFC-e automaticamente
/// em C:\ExodoNFCe\[CNPJ]\[YYYY-MM]\ ao emitir ou autorizar uma nota, e por
/// enviar o XML para a nuvem (bucket `xmls`), de onde o Portal do Contador
/// faz o download.
class NfceXmlLocalService {
  static const String _pastaBase = r'C:\ExodoNFCe';

  /// Bucket do Supabase Storage com os XMLs do Portal do Contador.
  /// Estrutura: `xmls/<empresa_id>/<chave>.xml`
  static const String _bucketNuvem = 'xmls';

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

      final dt = nfce.createdAt;
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
          : 'NFCe_${nfce.numero.isEmpty ? nfce.id : nfce.numero}-nfe.xml';

      final arquivoXml = File('${dir.path}\\$nomeArquivo');

      // Só escreve se ainda não existir (evita sobrescrever versão com protocolo)
      if (!arquivoXml.existsSync()) {
        arquivoXml.writeAsStringSync(xml, encoding: utf8);
        debugPrint('[NfceXml] ✅ XML salvo em: ${arquivoXml.path}');
      } else {
        debugPrint('[NfceXml] XML já existe, ignorando: ${arquivoXml.path}');
      }

      // Envia para a nuvem para o contador baixar no Portal do Contador.
      // Feito sempre (mesmo quando o arquivo local já existia) para cobrir
      // notas antigas que ainda não subiram.
      await _enviarParaNuvem(
        empresaId: empresa.id,
        chave: (nfce.chaveAcesso ?? '').trim(),
        xml: xml,
      );
    } catch (e) {
      // Não lança exceção — falha silenciosa para não prejudicar o fluxo de venda
      debugPrint('[NfceXml] ⚠️ Falha ao salvar XML local: $e');
    }
  }

  /// Sobe o XML para `xmls/<empresa_id>/<chave>.xml` no Supabase Storage.
  ///
  /// O bucket é privado e quem baixa é o portal/app com a chave service_role,
  /// por isso o upload aqui não depende de políticas públicas.
  static Future<void> _enviarParaNuvem({
    required String empresaId,
    required String chave,
    required String xml,
  }) async {
    if (!SupabaseService.isAvailable) return;
    if (empresaId.trim().isEmpty || chave.isEmpty) {
      debugPrint('[NfceXml] Sem empresa_id/chave — XML não enviado para a nuvem.');
      return;
    }

    try {
      await SupabaseService.instance.client.storage.from(_bucketNuvem).uploadBinary(
            '$empresaId/$chave.xml',
            Uint8List.fromList(utf8.encode(xml)),
            fileOptions: const FileOptions(upsert: true, contentType: 'application/xml'),
          );
      debugPrint('[NfceXml] ☁️ XML enviado para a nuvem: $_bucketNuvem/$empresaId/$chave.xml');
    } catch (e) {
      debugPrint('[NfceXml] ⚠️ Falha ao enviar XML para a nuvem: $e');
    }
  }
}
