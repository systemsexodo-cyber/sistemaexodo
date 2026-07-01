import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../models/produto.dart';
import '../models/empresa.dart';
import '../models/nfce.dart';
import 'supabase_service.dart';
import 'database_service.dart';
import 'google_drive_service.dart';
import 'local_bridge_detector.dart';

/// Interface base para serviços de NFC-e
abstract class NFCeServiceBase {
  Future<NFCe> emitir({
    required Empresa empresa,
    required List<Produto> produtos,
    required Map<String, double> quantidades,
    required List<NFCePagamento> pagamentos,
    required double valorTotal,
    String? cpfCnpjConsumidor,
    String? nomeConsumidor,
    String? observacoes,
    String? vendaId,
    String? vendaNumero,
    bool ambienteHomologacao = true,
    int? serie,
  });

  Future<Map<String, dynamic>> cancelarNFCe({
    required NFCe nfce,
    required Empresa empresa,
    String? justificativa,
  });
}

/// Serviço de emissão local: chama o Bridge em localhost:8000
/// e salva o resultado no Supabase + SQLite
class NFCeBackendService extends NFCeServiceBase {
  static const String _localBridgeUrl = 'http://localhost:8000';

  final String? _customBaseUrl;

  static final NFCeBackendService instance = NFCeBackendService._();
  NFCeBackendService._() : _customBaseUrl = null;
  NFCeBackendService({String? baseUrl}) : _customBaseUrl = baseUrl;

  String get baseUrl => _customBaseUrl ?? _localBridgeUrl;

  /// Inicializa o serviço detectando automaticamente o bridge local
  static Future<NFCeBackendService> createWithAutoDetection({String? customUrl}) async {
    final bridgeUrl = await LocalBridgeDetector.getBridgeUrl(customUrl: customUrl);
    return NFCeBackendService(baseUrl: bridgeUrl);
  }

  // ------------------------------------------------------------
  // PREPARAÇÃO DOS DADOS
  // ------------------------------------------------------------

  Map<String, dynamic> _prepararPayload({
    required Empresa empresa,
    required List<Produto> produtos,
    required Map<String, double> quantidades,
    required List<NFCePagamento> pagamentos,
    required double valorTotal,
    String? cpfCnpjConsumidor,
    String? nomeConsumidor,
    String? observacoes,
    bool ambienteHomologacao = true,
    int? serie,
    String? vendaId,
    String? vendaNumero,
  }) {
    final serieNum = serie ?? int.tryParse(empresa.serieNFCe ?? '1') ?? 1;
    return {
      'empresa': {
        'cnpj': empresa.cnpj?.replaceAll(RegExp(r'[^0-9]'), '') ?? '',
        'razao_social': empresa.razaoSocial,
        'nome_fantasia': empresa.nomeFantasia ?? empresa.razaoSocial,
        'inscricao_estadual':
            empresa.inscricaoEstadual?.replaceAll(RegExp(r'[^0-9]'), '') ?? '',
        'logradouro': empresa.endereco ?? '',
        'numero': empresa.numero ?? 'S/N',
        'bairro': empresa.bairro ?? '',
        'municipio': empresa.cidade ?? '',
        'codigo_municipio': empresa.configuracoes?['codigo_municipio'] ?? '',
        'uf': empresa.estado ?? 'SP',
        'cep': empresa.cep?.replaceAll(RegExp(r'[^0-9]'), '') ?? '',
        'crt':
            int.tryParse(
              empresa.configuracoes?['crt']?.toString() ?? '1',
            ) ??
            1,
        'ambiente': ambienteHomologacao ? 2 : 1,
        'certificado_base64':
            empresa.configuracoes?['certificadoDigitalBytes'] ??
            empresa.configuracoes?['certificado_base64'] ??
            empresa.certificadoDigitalUrl ?? '',
        'senha_certificado':
            empresa.senhaCertificado ??
            empresa.configuracoes?['certificadoDigitalSenha'] ??
            empresa.configuracoes?['senha_certificado'] ?? '',
        'csc': empresa.csc ?? '',
        'csc_id': empresa.cscIdToken ?? '',
      },
      'itens': produtos.map((p) {
        final qty = quantidades[p.id] ?? 1.0;
        return {
          'codigo': p.codigo ?? p.id,
          'descricao': p.nome,
          'ncm': p.ncm ?? '00000000',
          'cfop': '5102',
          'quantidade': qty,
          'valor_unitario': p.precoAtual,
          'valor_total': p.precoAtual * qty,
        };
      }).toList(),
      'pagamentos': pagamentos
          .map((p) => {'tipo': p.tipo, 'valor': p.valor})
          .toList(),
      'valor_total': valorTotal,
      'venda_numero': vendaNumero,
      'cpf_cliente': cpfCnpjConsumidor,
      'serie': serieNum,
    };
  }

  // ------------------------------------------------------------
  // EMIT
  // ------------------------------------------------------------

  @override
  Future<NFCe> emitir({
    required Empresa empresa,
    required List<Produto> produtos,
    required Map<String, double> quantidades,
    required List<NFCePagamento> pagamentos,
    required double valorTotal,
    String? cpfCnpjConsumidor,
    String? nomeConsumidor,
    String? observacoes,
    String? vendaId,
    String? vendaNumero,
    bool ambienteHomologacao = true,
    int? serie,
  }) async {
    debugPrint('>>> [NFCeLocal] Preparando payload...');

    final payload = _prepararPayload(
      empresa: empresa,
      produtos: produtos,
      quantidades: quantidades,
      pagamentos: pagamentos,
      valorTotal: valorTotal,
      cpfCnpjConsumidor: cpfCnpjConsumidor,
      nomeConsumidor: nomeConsumidor,
      observacoes: observacoes,
      ambienteHomologacao: ambienteHomologacao,
      serie: serie,
      vendaId: vendaId,
      vendaNumero: vendaNumero,
    );

    debugPrint('>>> [NFCeLocal] Enviando para $baseUrl/api/nfce/emitir...');

    late http.Response response;
    try {
      response = await http
          .post(
            Uri.parse('$baseUrl/api/nfce/emitir'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 60));
    } catch (e) {
      throw Exception(
        'Não foi possível conectar ao Emissor NFC-e.\n\n'
        'Certifique-se que o ExodoNfceBridge.exe está aberto.\n\n'
        'Detalhe: $e',
      );
    }

    if (response.statusCode != 200) {
      String detail = '';
      try {
        final errBody = jsonDecode(response.body);
        detail = errBody['detail'] ?? errBody['error'] ?? response.body;
      } catch (_) {
        detail = response.body;
      }
      throw Exception('Erro do Emissor (${response.statusCode}): $detail');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    debugPrint('>>> [NFCeLocal] Resposta: ${data.keys.toList()}');

    // Verificar se a emissão foi bem sucedida
    final statusResp = data['status']?.toString().toLowerCase() ?? '';
    if (statusResp == 'erro' || statusResp == 'error') {
      final msg = data['error'] ?? data['mensagem'] ?? data['message'] ?? 'Erro desconhecido';
      throw Exception(msg.toString());
    }

    // Construir objeto NFCe
    final now = DateTime.now();
    final nfce = NFCe(
      id: data['id']?.toString() ?? now.millisecondsSinceEpoch.toString(),
      numero: data['numero']?.toString() ?? vendaNumero ?? '0',
      serie:
          data['serie']?.toString() ??
          (serie?.toString() ?? empresa.serieNFCe ?? '1'),
      chaveAcesso:
          data['chave_acesso']?.toString() ?? data['chNFe']?.toString(),
      protocolo:
          data['protocolo']?.toString() ?? data['nProt']?.toString(),
      dataEmissao: now,
      empresaId: empresa.id,
      itens: [],
      valorTotal: valorTotal,
      cpfCnpjConsumidor: cpfCnpjConsumidor,
      nomeConsumidor: nomeConsumidor,
      pagamentos: pagamentos,
      xmlEnviado:
          data['xml_autorizado']?.toString() ?? data['xml']?.toString(),
      qrCode: data['qr_code']?.toString() ?? data['qrCode']?.toString(),
      status: 'autorizada',
      vendaId: vendaId,
      vendaNumero: vendaNumero,
      createdAt: now,
      updatedAt: now,
    );

    debugPrint('>>> [NFCeLocal] NFC-e emitida: ${nfce.chaveAcesso}');

    // Salvar no Supabase e SQLite em paralelo (fire-and-forget com log de erros)
    _salvarNosbancos(nfce, empresa);

    return nfce;
  }

  // ------------------------------------------------------------
  // CANCELAR
  // ------------------------------------------------------------

  @override
  Future<Map<String, dynamic>> cancelarNFCe({
    required NFCe nfce,
    required Empresa empresa,
    String? justificativa,
  }) async {
    final payload = {
      'chave_acesso': nfce.chaveAcesso,
      'protocolo': nfce.protocolo,
      'cnpj': empresa.cnpj?.replaceAll(RegExp(r'[^0-9]'), '') ?? '',
      'justificativa': justificativa ?? 'Cancelamento via sistema',
    };

    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/nfce/cancelar'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 45));

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (data['success'] == true) {
        // Atualizar status no Supabase
        _atualizarStatusSupabase(nfce.id, 'cancelada').catchError(
          (e) => debugPrint('>>> [NFCeLocal] Erro ao cancelar no Supabase: $e'),
        );
        // Atualizar status no SQLite
        _atualizarStatusSqlite(nfce.id, 'cancelada').catchError(
          (e) => debugPrint('>>> [NFCeLocal] Erro ao cancelar no SQLite: $e'),
        );
      }

      return {
        'success': data['success'] ?? false,
        'message': data['message'] ?? data['error'] ?? 'Cancelamento processado',
        'data': data,
      };
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  // ------------------------------------------------------------
  // PERSISTÊNCIA
  // ------------------------------------------------------------

  /// Salva a NFC-e emitida no Supabase e no SQLite local.
  /// Roda em background - não bloqueia a UI.
  void _salvarNosbancos(NFCe nfce, Empresa empresa) {
    // 1. Supabase
    _salvarNoSupabase(nfce).catchError(
      (e) => debugPrint('>>> [NFCeLocal] Falha ao salvar no Supabase: $e'),
    );

    // 2. SQLite
    _salvarNoSqlite(nfce).catchError(
      (e) => debugPrint('>>> [NFCeLocal] Falha ao salvar no SQLite: $e'),
    );

    // 3. Google Drive (XML)
    if (nfce.xmlEnviado != null && nfce.xmlEnviado!.isNotEmpty) {
      // TODO: Implementar salvamento no Google Drive
      debugPrint('>>> [NFCeLocal] XML disponível para salvar no Google Drive');
    }
  }

  Future<void> _salvarNoSupabase(NFCe nfce) async {
    if (!SupabaseService.isAvailable) {
      debugPrint('>>> [NFCeLocal] Supabase offline - NFC-e ficará só no SQLite.');
      return;
    }

    final data = {
      'id': nfce.id,
      'empresa_id': nfce.empresaId,
      'numero': nfce.numero,
      'serie': nfce.serie,
      'chave_acesso': nfce.chaveAcesso,
      'protocolo': nfce.protocolo,
      'status': nfce.status ?? 'autorizada',
      'valor_total': nfce.valorTotal,
      'cpf_cnpj_consumidor': nfce.cpfCnpjConsumidor,
      'nome_consumidor': nfce.nomeConsumidor,
      'xml_autorizado': nfce.xmlEnviado,
      'qr_code': nfce.qrCode,
      'venda_id': nfce.vendaId,
      'venda_numero': nfce.vendaNumero,
      'pagamentos': jsonEncode(nfce.pagamentos.map((p) => p.toMap()).toList()),
      'data_emissao': nfce.dataEmissao.toIso8601String(),
      'created_at': nfce.createdAt.toIso8601String(),
      'updated_at': nfce.updatedAt.toIso8601String(),
    };

    try {
      await SupabaseService.instance.client
          .from('nfces')
          .upsert(data);
      debugPrint('>>> [NFCeLocal] NFC-e salva no Supabase.');
    } catch (e) {
      debugPrint('>>> [NFCeLocal] Erro ao salvar NFC-e no Supabase: $e');
      rethrow;
    }
  }

  Future<void> _salvarNoSqlite(NFCe nfce) async {
    if (kIsWeb) return;

    try {
      await DatabaseService().salvarLista('nfces', [nfce.toMap()]);
      debugPrint('>>> [NFCeLocal] NFC-e salva no PostgreSQL.');
    } catch (e) {
      debugPrint('>>> [NFCeLocal] Erro ao salvar NFC-e no PostgreSQL: $e');
      rethrow;
    }
  }

  Future<void> _atualizarStatusSupabase(String nfceId, String status) async {
    if (!SupabaseService.isAvailable) return;
    await SupabaseService.instance.client
        .from('nfces')
        .update({'status': status, 'updated_at': DateTime.now().toIso8601String()})
        .eq('id', nfceId);
  }

  Future<void> _atualizarStatusSqlite(String nfceId, String status) async {
    if (kIsWeb) return;
    await DatabaseService().atualizarStatusNFCe(nfceId, status);
  }

  /// Verifica se o bridge está online
  Future<bool> verificarConexao() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/health'))
          .timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (_) {
      // Tentar endpoint raiz como fallback
      try {
        final response = await http
            .get(Uri.parse('$baseUrl/'))
            .timeout(const Duration(seconds: 4));
        return response.statusCode == 200;
      } catch (_) {
        return false;
      }
    }
  }

  /// Consulta NFC-e emitida
  Future<Map<String, dynamic>> consultar({
    required String chaveAcesso,
    required Empresa empresa,
  }) async {
    final payload = {
      'chave_acesso': chaveAcesso,
      'cnpj': empresa.cnpj?.replaceAll(RegExp(r'[^0-9]'), '') ?? '',
    };

    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/nfce/consultar'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 30));

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return {
        'success': data['success'] ?? false,
        'message': data['message'] ?? data['error'] ?? 'Consulta processada',
        'data': data,
      };
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }
}
