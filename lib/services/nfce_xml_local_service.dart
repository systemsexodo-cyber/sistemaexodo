import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'neon_storage.dart' show FileOptions;
import '../models/nfce.dart';
import '../models/empresa.dart';
import 'supabase_service.dart';

/// Serviço responsável por salvar XMLs e PDFs de NFC-e automaticamente
/// em C:\ExodoNFCe\[CNPJ]\[YYYY-MM]\ ao emitir ou autorizar uma nota, e por
/// enviar o XML para a nuvem (bucket `xmls`), de onde o Portal do Contador
/// faz o download.
///
/// O envio não pode depender do momento da emissão: quando a nuvem está fora
/// (ou recusa o upload), o XML entra numa fila em disco e é reenviado em
/// segundo plano — senão a nota simplesmente não aparecia no Portal do
/// Contador.
class NfceXmlLocalService {
  static const String _pastaBase = r'C:\ExodoNFCe';

  /// Bucket do Supabase Storage com os XMLs do Portal do Contador.
  /// Estrutura: `xmls/<empresa_id>/<chave>.xml`
  static const String _bucketNuvem = 'xmls';

  /// Fila de uploads pendentes (nuvem fora na hora da autorização).
  static const String _arquivoPendentes = r'C:\ExodoNFCe\_pendentes_upload_xml.json';

  /// Teto da fila: um XML tem ~10 KB, então 500 é folgado e evita crescer sem
  /// limite numa máquina que ficou dias sem nuvem.
  static const int _maxPendentes = 500;

  static const Duration _intervaloReenvio = Duration(minutes: 5);

  static final List<Map<String, dynamic>> _pendentes = [];
  static Timer? _timerPendentes;
  static bool _enviandoPendentes = false;

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

  /// Carrega a fila de uploads pendentes e liga o reenvio periódico.
  ///
  /// Chamado no boot do app (depois da contingência). Nunca deve impedir a
  /// abertura: qualquer erro fica só no log.
  static Future<void> inicializar() async {
    if (kIsWeb || !Platform.isWindows) return;
    try {
      _carregarPendentes();
      _timerPendentes?.cancel();
      _timerPendentes = Timer.periodic(_intervaloReenvio, (_) {
        unawaited(enviarPendentes());
      });
      debugPrint(
        '[NfceXml] Fila de upload iniciada (${_pendentes.length} XML(s) pendente(s))',
      );
      if (_pendentes.isNotEmpty) {
        unawaited(enviarPendentes());
      }
    } catch (e) {
      debugPrint('[NfceXml] ⚠️ Não foi possível iniciar a fila de upload: $e');
    }
  }

  /// Tenta subir todos os XMLs da fila. Idempotente: cada XML tem caminho fixo
  /// (`<empresa_id>/<chave>.xml`) e o upload usa upsert.
  static Future<int> enviarPendentes() async {
    if (kIsWeb || !Platform.isWindows) return 0;
    if (_enviandoPendentes || _pendentes.isEmpty) return 0;

    _enviandoPendentes = true;
    var enviados = 0;
    try {
      final restantes = <Map<String, dynamic>>[];
      for (final pendente in List<Map<String, dynamic>>.from(_pendentes)) {
        final ok = await _subir(
          empresaId: pendente['empresa_id']?.toString() ?? '',
          chave: pendente['chave']?.toString() ?? '',
          xml: pendente['xml']?.toString() ?? '',
        );
        if (ok) {
          enviados++;
        } else {
          restantes.add(pendente);
        }
      }
      _pendentes
        ..clear()
        ..addAll(restantes);
      _salvarPendentes();
      if (enviados > 0) {
        debugPrint('[NfceXml] ☁️ $enviados XML(s) pendente(s) enviados agora '
            '(${_pendentes.length} na fila)');
      }
    } catch (e) {
      debugPrint('[NfceXml] ⚠️ Erro ao reenviar XMLs pendentes: $e');
    } finally {
      _enviandoPendentes = false;
    }
    return enviados;
  }

  /// Quantos XMLs estão esperando a nuvem.
  static int get pendentesDeUpload => _pendentes.length;

  /// Sobe o XML para `xmls/<empresa_id>/<chave>.xml` no Storage.
  ///
  /// O bucket é privado e quem baixa é o portal/app com a chave de serviço,
  /// por isso o upload aqui não depende de políticas públicas. Se falhar, o
  /// arquivo entra na fila em vez de se perder.
  static Future<void> _enviarParaNuvem({
    required String empresaId,
    required String chave,
    required String xml,
  }) async {
    if (empresaId.trim().isEmpty || chave.isEmpty) {
      debugPrint('[NfceXml] Sem empresa_id/chave — XML não enviado para a nuvem.');
      return;
    }

    final ok = await _subir(empresaId: empresaId, chave: chave, xml: xml);
    if (ok) return;

    if (_enfileirarPendente(empresaId: empresaId, chave: chave, xml: xml)) {
      debugPrint(
        '[NfceXml] 📥 XML guardado na fila para envio posterior '
        '(${_pendentes.length} na fila): $_bucketNuvem/$empresaId/$chave.xml',
      );
    }
  }

  /// Upload direto (sem fila). `true` quando o arquivo está na nuvem.
  static Future<bool> _subir({
    required String empresaId,
    required String chave,
    required String xml,
  }) async {
    if (empresaId.trim().isEmpty || chave.isEmpty || xml.trim().isEmpty) {
      return false;
    }
    if (!SupabaseService.isAvailable) return false;

    try {
      await SupabaseService.instance.client.storage.from(_bucketNuvem).uploadBinary(
            '$empresaId/$chave.xml',
            Uint8List.fromList(utf8.encode(xml)),
            fileOptions: const FileOptions(upsert: true, contentType: 'application/xml'),
          );
      debugPrint('[NfceXml] ☁️ XML enviado para a nuvem: $_bucketNuvem/$empresaId/$chave.xml');
      return true;
    } catch (e) {
      debugPrint('[NfceXml] ⚠️ Falha ao enviar XML para a nuvem: $e');
      return false;
    }
  }

  // ─────────────────────────────────────────────────
  // FILA EM DISCO
  // ─────────────────────────────────────────────────

  /// Guarda o XML para envio posterior. Devolve `false` quando já estava na
  /// fila (mesma empresa + mesma chave).
  static bool _enfileirarPendente({
    required String empresaId,
    required String chave,
    required String xml,
  }) {
    final id = '$empresaId/$chave';
    if (_pendentes.any((pendente) => pendente['id'] == id)) return false;

    _pendentes.add({
      'id': id,
      'empresa_id': empresaId,
      'chave': chave,
      'xml': xml,
      'guardado_em': DateTime.now().toIso8601String(),
    });
    // Fila cheia: descarta os mais antigos (o backfill roda por fora).
    while (_pendentes.length > _maxPendentes) {
      _pendentes.removeAt(0);
    }
    _salvarPendentes();
    return true;
  }

  static void _carregarPendentes() {
    try {
      final arquivo = File(_arquivoPendentes);
      if (!arquivo.existsSync()) return;
      final conteudo = arquivo.readAsStringSync(encoding: utf8);
      if (conteudo.trim().isEmpty) return;
      final lista = jsonDecode(conteudo);
      if (lista is! List) return;
      _pendentes
        ..clear()
        ..addAll(
          lista
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item)),
        );
    } catch (e) {
      debugPrint('[NfceXml] ⚠️ Não consegui ler a fila de uploads: $e');
    }
  }

  static void _salvarPendentes() {
    try {
      final dir = Directory(_pastaBase);
      if (!dir.existsSync()) dir.createSync(recursive: true);
      File(
        _arquivoPendentes,
      ).writeAsStringSync(jsonEncode(_pendentes), encoding: utf8);
    } catch (e) {
      debugPrint('[NfceXml] ⚠️ Não consegui gravar a fila de uploads: $e');
    }
  }
}
