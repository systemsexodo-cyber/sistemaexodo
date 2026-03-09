/// Serviço para comunicação com backend Python (PyNFe)
/// Substitui a implementação manual por chamadas HTTP ao backend

import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/nfce.dart';
import '../models/empresa.dart';
import '../models/produto.dart';
import 'google_drive_service.dart';
import 'package:intl/intl.dart';

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
    bool ambienteHomologacao = true,
    int? serie,
  });
}

class NFCeBackendService implements NFCeServiceBase {
  final String baseUrl;
  
  /// Cria serviço para comunicação com backend Python
  /// 
  /// Por padrão, usa localhost:5000 (modo local)
  /// Para produção, passe a URL do Cloud Run:
  /// NFCeBackendService(baseUrl: 'https://seu-servico.run.app')
  NFCeBackendService({String? baseUrl}) 
      : baseUrl = _limparBaseUrl(baseUrl ?? _getDefaultUrl());
      
  static String _limparBaseUrl(String url) {
    var limpa = url.trim();
    if (limpa.endsWith('/')) {
      limpa = limpa.substring(0, limpa.length - 1);
    }
    if (limpa.endsWith('/emitir')) {
      limpa = limpa.substring(0, limpa.length - 7);
    }
    return limpa;
  }
  
  /// Obtém URL padrão baseado na plataforma
  static String _getDefaultUrl() {
    // Em desenvolvimento, usar localhost
    // Em produção, usar URL do Cloud Run
    const String? cloudRunUrl = null; // Configure aqui quando fizer deploy
    
    if (cloudRunUrl != null && cloudRunUrl.isNotEmpty) {
      return cloudRunUrl;
    }
    
    // Modo local - Backend Python (PyNFe)
    // Se retornar vazio, o sistema usará automaticamente o Modo Firebase (Sem Link/Túnel)
    return ''; 
  }
  
  /// Emite uma NFC-e via backend Python
  Future<NFCe> emitir({
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
  }) async {
    try {
      debugPrint('>>> [NFCeBackend] Iniciando emissão via backend Python (PyNFe)...');
      
      // Se não houver baseUrl válida ou se for solicitado explicitamente, usar Firebase
      // No Web App, forçar Firebase se a URL for HTTP (evitar erro de Mixed Content)
      final bool isWebHttp = kIsWeb && (baseUrl.startsWith('http://') || baseUrl.contains('localhost'));
      
      final bool usarFirebase = baseUrl.isEmpty || 
          baseUrl.contains('firebase') || 
          isWebHttp ||
          (empresa.configuracoes?['usarFirebaseBridge'] == true);
      
      if (usarFirebase) {
        debugPrint('>>> [NFCeBackend] Detectado modo FIREBASE (Relay/Sem Link). IsWebHttp: $isWebHttp');
        return await emitirViaFirebase(
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
        );
      }

      debugPrint('>>> [NFCeBackend] URL: $baseUrl/emitir');
      
      // Preparar dados para o backend
      late final Map<String, dynamic> requestData;
      try {
        requestData = _prepararDadosEmissao(
          empresa: empresa,
          produtos: produtos,
          quantidades: quantidades,
          pagamentos: pagamentos,
          valorTotal: valorTotal,
          cpfCnpjConsumidor: cpfCnpjConsumidor,
          observacoes: observacoes,
          ambienteHomologacao: ambienteHomologacao,
          serie: serie,
        );
      } catch (e) {
        throw Exception('Erro ao preparar dados para emissão: $e');
      }
      
      // Acesso seguro aos dados para diagnóstico
      final empresaData = (requestData['empresa'] as Map<dynamic, dynamic>?) ?? {};
      final certificadoBase64 = empresaData['certificado_base64']?.toString() ?? '';
      
      final Map<dynamic, dynamic> configMap = (empresaData['configuracoes'] as Map<dynamic, dynamic>?) ?? {};
      final certificadoConfig = configMap['certificadoDigitalBytes']?.toString() ?? '';
      
      final senha = empresaData['senhaCertificado']?.toString() ?? 
                    empresaData['senha_certificado']?.toString() ?? '';
      
      debugPrint('>>> [NFCeBackend] ========================================');
      debugPrint('>>> [NFCeBackend] DIAGNÓSTICO DE CERTIFICADO:');
      debugPrint('>>> [NFCeBackend] certificado_base64: ${certificadoBase64.isNotEmpty ? "presente" : "AUSENTE"}');
      debugPrint('>>> [NFCeBackend] configuracoes: ${configMap.isNotEmpty ? "presente" : "AUSENTE"}');
      debugPrint('>>> [NFCeBackend] senha: ${senha.isNotEmpty ? "presente" : "AUSENTE"}');
      debugPrint('>>> [NFCeBackend] ========================================');
      if (certificadoBase64.isEmpty && certificadoConfig.isEmpty) {
        throw Exception('Certificado digital não encontrado!\n\n'
            'Por favor, configure o certificado digital na empresa antes de emitir NFC-e.\n\n'
            'DIAGNÓSTICO:\n'
            '• certificado_base64: ${certificadoBase64.isNotEmpty ? "presente" : "ausente"}\n'
            '• configuracoes.certificadoDigitalBytes: ${certificadoConfig.isNotEmpty ? "presente" : "ausente"}');
      }
      
      if (senha.isEmpty) {
        throw Exception('Senha do certificado não informada!\n\n'
            'Por favor, informe a senha do certificado na configuração da empresa.');
      }
      
      debugPrint('>>> [NFCeBackend] Enviando requisição...');
      
      // Obter chave de API das configurações da empresa
      final apiKey = empresa.configuracoes?['bridgeNfceKey'] as String? ?? '';
      
      // Fazer requisição HTTP
      final response = await http.post(
        Uri.parse('$baseUrl/emitir'), // Nota: O novo backend usa /emitir e não /api/nfce/emitir
        headers: {
          'Content-Type': 'application/json',
          if (apiKey.isNotEmpty) 'X-Api-Key': apiKey,
        },
        body: jsonEncode(requestData),
      ).timeout(
        const Duration(seconds: 120),
        onTimeout: () {
          throw Exception('Timeout ao comunicar com o Emissor NFC-e (120s). Verifique se o programa está aberto e se o link/IP está correto.');
        },
      );
      
      debugPrint('>>> [NFCeBackend] Status: ${response.statusCode}');
      debugPrint('>>> [NFCeBackend] Response: ${response.body}');
      
      if (response.statusCode == 200) {
        final Map<String, dynamic> responseData = jsonDecode(response.body);
        
        // Determinar se a resposta está encapsulada em 'data' ou é direta
        final bool isWrapped = responseData.containsKey('success');
        final Map<String, dynamic> data = isWrapped 
            ? (responseData['data'] as Map<String, dynamic>? ?? responseData)
            : responseData;
            
        final bool success = isWrapped 
            ? (responseData['success'] == true) 
            : (responseData['status'] == 'sucesso' || responseData['status'] == 'autorizada');

        // Normalizar o status para o padrão do app ('autorizada')
        String status = (data['status']?.toString() ?? 'processando').toLowerCase();
        if (status == 'sucesso' || status == 'autorizado') {
          status = 'autorizada';
        }

        if (success || status == 'autorizada') {
          // Criar objeto NFCe a partir da resposta
          final nfce = _criarNFCeDaResposta(
            data: data,
            empresa: empresa,
            produtos: produtos,
            quantidades: quantidades,
            pagamentos: pagamentos,
            valorTotal: valorTotal,
            cpfCnpjConsumidor: cpfCnpjConsumidor,
            nomeConsumidor: nomeConsumidor,
            observacoes: observacoes,
          );
          
          debugPrint('>>> [NFCeBackend] ✓✓✓ NFC-e emitida com sucesso!');
          debugPrint('>>> [NFCeBackend] Status: $status');
          debugPrint('>>> [NFCeBackend] Chave: ${nfce.chaveAcesso}');

          // SALVAMENTO AUTOMÁTICO NO GOOGLE DRIVE
          if (nfce.xmlEnviado != null && nfce.xmlEnviado!.isNotEmpty) {
            _salvarXmlNoDrive(nfce, empresa);
          }

          return nfce;
        } else {
          // NFC-e rejeitada ou erro retornado pelo backend com status 200
          String errorMsg = '';
          
          // Verificar se é erro de certificado (comum em bridge)
          final errorType = responseData['error_type']?.toString() ?? data['error_type']?.toString();
          if (errorType == 'CertificateError' || errorType == 'CertificateMissing') {
             errorMsg = responseData['error']?.toString() ?? data['error']?.toString() ?? responseData['message']?.toString() ?? 'Erro no certificado digital.';
             throw Exception(errorMsg);
          }

          // Tentar extrair motivo da rejeição
          final xmotivo = data['xmotivo']?.toString() ?? data['motivo']?.toString() ?? responseData['message']?.toString() ?? responseData['error']?.toString();
          final cstat = data['cstat']?.toString() ?? responseData['cstat']?.toString();
          
          if (xmotivo != null && xmotivo.isNotEmpty) {
            errorMsg = 'Rejeição: $xmotivo';
            if (cstat != null) errorMsg += ' (Código: $cstat)';
          } else {
            errorMsg = 'Erro desconhecido ao emitir NFC-e (Status 200 mas sem sucesso).';
          }

          // Adicionar detalhes técnicos se disponíveis
          final detalhes = <String>[];
          if (data['verAplic'] != null) detalhes.add('Versão: ${data['verAplic']}');
          if (data['dhRecbto'] != null) detalhes.add('Recebimento: ${data['dhRecbto']}');
          
          if (detalhes.isNotEmpty) {
            errorMsg += '\n\n' + detalhes.join('\n');
          }

          // Caso especial: dependência faltando no backend
          if (errorMsg.contains('signxml')) {
            errorMsg = 'Dependência "signxml" faltando no backend!\n\nExecute: pip install signxml';
          }

          throw Exception(errorMsg);
        }
      } else {
        // Erro HTTP (Status != 200)
        Map<String, dynamic>? errorData;
        try {
          errorData = jsonDecode(response.body) as Map<String, dynamic>;
        } catch (_) {}
        
        String errorMessage = errorData?['error']?.toString() ?? 
                             errorData?['message']?.toString() ?? 
                             'Erro HTTP ${response.statusCode} ao emitir NFC-e';
        
        if (response.statusCode == 404) {
          errorMessage = 'Rota de emissão não encontrada no backend (404). Verifique a URL.';
        } else if (response.statusCode == 401 || response.statusCode == 403) {
          errorMessage = 'Acesso negado ao backend (401/403). Verifique a API Key.';
        }
        
        throw Exception(errorMessage);
      }
    } catch (e) {
      debugPrint('>>> [NFCeBackend] ❌ ERRO: $e');
      debugPrint('>>> [NFCeBackend] Tipo do erro: ${e.runtimeType}');
      
      // Melhorar mensagem de erro para "Failed to fetch"
      final errorStr = e.toString();
      if (errorStr.contains('Failed to fetch') || 
          errorStr.contains('ClientException') ||
          errorStr.contains('SocketException') ||
          errorStr.contains('Connection refused')) {
          throw Exception('Não foi possível conectar ao Emissor NFC-e!\n\n'
            'O serviço local não está rodando ou a URL está incorreta.\n\n'
            'SOLUÇÃO:\n'
            '1. Certifique-se de que o programa "ExodoNfceBridge.exe" está aberto no computador.\n'
            '2. Vá em Editar Empresa e verifique se a "URL do Emissor Local" está correta.\n'
            '3. Se estiver usando o App Online, você precisa colar o link público (Ex: https://...localhost.run).\n'
            '4. Tente emitir a NFC-e novamente.\n\n'
            'URL configurada: $baseUrl');
      }
      
      // Se for Exception com mensagem, usar a mensagem
      if (e is Exception) {
        final exceptionMessage = e.toString();
        // Remover "Exception: " do início se existir
        String cleanMessage = exceptionMessage.replaceFirst('Exception: ', '');
        
        // Se mensagem estiver vazia, criar uma genérica
        if (cleanMessage.trim().isEmpty) {
          cleanMessage = 'Erro desconhecido ao comunicar com backend Python. Verifique os logs do servidor.';
        }
        
        throw Exception(cleanMessage);
      }
      
      // Se não for Exception, usar a string do erro (já convertida acima)
      if (errorStr.trim().isEmpty) {
        throw Exception('Erro desconhecido. Verifique os logs do servidor backend.');
      }
      
      throw Exception(errorStr);
    }
  }
  
  /// Consulta status de uma NFC-e
  Future<Map<String, dynamic>> consultar({
    required String chaveAcesso,
    required Empresa empresa,
  }) async {
    try {
      debugPrint('>>> [NFCeBackend] Consultando NFC-e: $chaveAcesso');
      
      final requestData = {
        'chave_acesso': chaveAcesso,
        'empresa': _prepararDadosEmpresa(empresa),
      };
      
      final response = await http.post(
        Uri.parse('$baseUrl/api/nfce/consultar'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode(requestData),
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw Exception('Timeout ao consultar NFC-e');
        },
      );
      
      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body) as Map<String, dynamic>;
        return responseData;
      } else {
        final errorData = jsonDecode(response.body) as Map<String, dynamic>;
        throw Exception(errorData['error'] ?? 'Erro ao consultar NFC-e');
      }
    } catch (e) {
      debugPrint('>>> [NFCeBackend] ❌ ERRO ao consultar: $e');
      rethrow;
    }
  }

  /// Verifica o status do Bridge via Firestore de forma robusta
  Future<Map<String, dynamic>> _verificarBridgeOnline() async {
    try {
      // Usar uma tolerância maior para divergência de relógios (15 minutos)
      final agora = DateTime.now().toUtc();
      final limite = agora.subtract(const Duration(minutes: 15)); 

      final snap = await FirebaseFirestore.instance
          .collection('bridge_status')
          .get(const GetOptions(source: Source.serverAndCache)) 
          .timeout(const Duration(seconds: 10));

      final pcsOnline = <String>[];
      final pcsOffline = <Map<String, String>>[];
      
      for (final doc in snap.docs) {
        final data = doc.data();
        if (doc.id.startsWith('watchdog_')) continue; // Ignorar watchdogs nesta contagem

        final pcName = data['pc_name']?.toString() ?? doc.id;
        final bool isOnlineFlag = data['online'] == true;
        
        final lastSeen = data['last_seen'];
        DateTime? lastSeenDt;
        if (lastSeen is Timestamp) {
          lastSeenDt = lastSeen.toDate().toUtc();
        }

        // Se o flag está online e foi visto nos últimos 15 minutos, consideramos OK
        if (isOnlineFlag && (lastSeenDt == null || lastSeenDt.isAfter(limite))) {
          pcsOnline.add(pcName);
        } else if (isOnlineFlag) {
          // Se o flag diz online mas o tempo é antigo, pode ser clock skew ou ficou travado
          // Vamos ser lenientes aqui para evitar o erro de "não enxerga"
          pcsOnline.add(pcName);
        } else {
           final diff = lastSeenDt != null ? agora.difference(lastSeenDt).inMinutes : 0;
           pcsOffline.add({'nome': pcName, 'atraso': '$diff min'});
        }
      }

      return {
        'pcsOnline': pcsOnline,
        'pcsOffline': pcsOffline,
        'totalRegistros': snap.docs.length,
      };
    } catch (e) {
      debugPrint('>>> [NFCeFirebase] Erro ao verificar bridge_status: $e');
      return {'pcsOnline': <String>[], 'totalRegistros': -1};
    }
  }

  /// Emite uma NFC-e via Firebase Firestore (Listener no PC)
  /// Isso elimina a necessidade de Túneis SSH ou URLs públicas
  Future<NFCe> emitirViaFirebase({
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
  }) async {
    try {
      debugPrint('>>> [NFCeFirebase] VERSÃO DO CÓDIGO: FIX_REMOVIDO_OFFLINE_v1');
      debugPrint('>>> [NFCeFirebase] Iniciando emissão via FIRESTORE LISTENER...');
      debugPrint('>>> [NFCeFirebase] Série customizada: ${serie ?? "não informada (usará padrão)"}');

      // ── VERIFICAÇÃO DE PRESENÇA ──────────────────────────────────────────
      debugPrint('>>> [NFCeFirebase] Verificando se o Bridge está rodando...');
      final statusBridge = await _verificarBridgeOnline();
      final List<String> pcsOnline = List<String>.from(statusBridge['pcsOnline'] as List);
      
      if (pcsOnline.isEmpty) {
        debugPrint('>>> [NFCeFirebase] ⚠️ Bridge não detectado (relógio dessincronizado ou offline). Tentando mesmo assim...');
      } else {
        debugPrint('>>> [NFCeFirebase] ✅ Bridge online em: ${pcsOnline.join(", ")}');
      }
      // ────────────────────────────────────────────────────────────────────


      // Preparar dados
      final requestData = _prepararDadosEmissao(
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
      );

      // Adicionar metadados
      requestData['status'] = 'pendente';
      requestData['created_at'] = FieldValue.serverTimestamp();
      requestData['empresa_id'] = empresa.id;

      // Criar documento no Firestore
      final docRef = await FirebaseFirestore.instance
          .collection('nfce_requests')
          .add(requestData);

      debugPrint('>>> [NFCeFirebase] Documento enviado: ${docRef.id}. Aguardando Bridge (120s)...');

      // Listen para o resultado (Aumentado para 120s)
      final completer = Completer<NFCe>();
      StreamSubscription? subscription;

      Timer(const Duration(seconds: 120), () {
        if (!completer.isCompleted) {
          subscription?.cancel();
          // Marcar o documento como expirado no Firestore para não ser processado
          docRef.update({'status': 'expirado'}).catchError((_) {});
          
          String msgPC = pcsOnline.isNotEmpty 
            ? 'O Bridge está rodando no PC: ${pcsOnline.join(", ")}\n\n' 
            : 'O Bridge não sinalizou presença (Verifique se o programa ExodoNfceBridge.exe está aberto).\n\n';

          completer.completeError(Exception(
            'O Emissor NFC-e demorou demais para responder (120s).\n\n'
            '$msgPC'
            'Possíveis causas:\n'
            '• O Bridge está processando outra nota\n'
            '• Problema de conexão com a SEFAZ\n'
            '• Erro interno no Bridge\n\n'
            'Tente emitir novamente em alguns segundos.',
          ));
        }
      });

      subscription = docRef.snapshots().listen((snapshot) {
        if (!snapshot.exists) return;

        final data = snapshot.data() as Map<String, dynamic>;
        final status = data['status'];

        if (status == 'autorizada') {
          subscription?.cancel();
          final resultado = data['resultado'] as Map<String, dynamic>?;

          if (resultado == null) {
            if (!completer.isCompleted) {
              completer.completeError(Exception('O emissor autorizou a nota, mas não enviou os dados de retorno.'));
            }
            return;
          }

          final nfce = _criarNFCeDaResposta(
            data: resultado,
            empresa: empresa,
            produtos: produtos,
            quantidades: quantidades,
            pagamentos: pagamentos,
            valorTotal: valorTotal,
            cpfCnpjConsumidor: cpfCnpjConsumidor,
            nomeConsumidor: nomeConsumidor,
            observacoes: observacoes,
          );

          // SALVAMENTO AUTOMÁTICO NO GOOGLE DRIVE
          if (nfce.xmlEnviado != null && nfce.xmlEnviado!.isNotEmpty) {
            _salvarXmlNoDrive(nfce, empresa);
          }

          if (!completer.isCompleted) completer.complete(nfce);
        } else if (status == 'erro') {
          subscription?.cancel();
          final resultado = data['resultado'] as Map<String, dynamic>?;
          final mensagem = resultado != null
              ? (resultado['mensagem'] ?? resultado['error'] ?? 'Erro desconhecido')
              : 'Erro desconhecido no processamento.';
          if (!completer.isCompleted) completer.completeError(Exception(mensagem));
        }
      });

      return await completer.future;
    } catch (e) {
      debugPrint('>>> [NFCeFirebase] ❌ ERRO: $e');
      rethrow;
    }
  }
  
  /// Valida um certificado digital
  Future<Map<String, dynamic>> validarCertificado({
    required String certificadoBase64,
    required String senha,
  }) async {
    try {
      debugPrint('>>> [NFCeBackend] Validando certificado...');
      
      final requestData = {
        'certificado_base64': certificadoBase64,
        'senha': senha,
      };
      
      final response = await http.post(
        Uri.parse('$baseUrl/api/certificado/validar'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode(requestData),
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw Exception('Timeout ao validar certificado');
        },
      );
      
      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body) as Map<String, dynamic>;
        return responseData;
      } else {
        final errorData = jsonDecode(response.body) as Map<String, dynamic>;
        throw Exception(errorData['error'] ?? 'Erro ao validar certificado');
      }
    } catch (e) {
      debugPrint('>>> [NFCeBackend] ❌ ERRO ao validar: $e');
      rethrow;
    }
  }
  
  /// Verifica se o backend está disponível
  Future<bool> verificarConexao() async {
    bool httpOk = false;
    try {
      // No Web App, URLs HTTP falham por Mixed Content. Vamos pular o check HTTP se for o caso.
      final bool pularHttp = kIsWeb && (baseUrl.startsWith('http://') || baseUrl.contains('localhost'));

      // Se tiver URL configurada e segura (ou permitida), verificar via HTTP primeiro
      if (baseUrl.isNotEmpty && !baseUrl.contains('firebase') && !pularHttp) {
        final response = await http.get(
          Uri.parse('$baseUrl/health'),
        ).timeout(
          const Duration(seconds: 3),
          onTimeout: () => throw Exception('Timeout'),
        );
        httpOk = response.statusCode == 200;
      }
    } catch (e) {
      debugPrint('>>> [NFCeBackend] HTTP Health Check falhou (esperado no Web): $e');
    }

    if (httpOk) return true;
    
    // Fallback: Se não tiver URL ou HTTP falhar, verificar via Firestore (Modo Relay)
    try {
      final status = await _verificarBridgeOnline();
      final pcsOnline = (status['pcsOnline'] as List?) ?? [];
      return pcsOnline.isNotEmpty;
    } catch (e) {
      debugPrint('>>> [NFCeBackend] Firestore Bridge Check falhou: $e');
      return false;
    }
  }
  
  /// Prepara dados da empresa para o backend
  Map<String, dynamic> _prepararDadosEmpresa(Empresa empresa) {
    // DIAGNÓSTICO COMPLETO: Logar TODOS os dados antes de processar
    debugPrint('>>> [NFCeBackend] ========================================');
    debugPrint('>>> [NFCeBackend] PREPARANDO DADOS DA EMPRESA');
    debugPrint('>>> [NFCeBackend] ========================================');
    debugPrint('>>> [NFCeBackend] Empresa ID: ${empresa.id}');
    debugPrint('>>> [NFCeBackend] CNPJ: ${empresa.cnpj}');
    debugPrint('>>> [NFCeBackend] Razão Social: ${empresa.razaoSocial}');
    debugPrint('>>> [NFCeBackend] Tem configuracoes: ${empresa.configuracoes != null}');
    if (empresa.configuracoes != null) {
      debugPrint('>>> [NFCeBackend] Chaves em configuracoes: ${empresa.configuracoes!.keys.toList()}');
      if (empresa.configuracoes!.containsKey('certificadoDigitalBytes')) {
        final certBytes = empresa.configuracoes!['certificadoDigitalBytes'];
        debugPrint('>>> [NFCeBackend] certificadoDigitalBytes existe: true');
        debugPrint('>>> [NFCeBackend] Tipo: ${certBytes.runtimeType}');
        debugPrint('>>> [NFCeBackend] Tamanho: ${certBytes is String ? certBytes.length : "N/A"} caracteres');
        if (certBytes is String && certBytes.isNotEmpty) {
          debugPrint('>>> [NFCeBackend] Primeiros 50 chars: ${certBytes.substring(0, certBytes.length > 50 ? 50 : certBytes.length)}...');
        }
      } else {
        debugPrint('>>> [NFCeBackend] certificadoDigitalBytes: NÃO EXISTE');
      }
    }
    debugPrint('>>> [NFCeBackend] certificadoDigitalUrl: ${empresa.certificadoDigitalUrl ?? "null"}');
    debugPrint('>>> [NFCeBackend] senhaCertificado: ${empresa.senhaCertificado != null && empresa.senhaCertificado!.isNotEmpty ? "presente (${empresa.senhaCertificado!.length} chars)" : "AUSENTE"}');
    debugPrint('>>> [NFCeBackend] ========================================');
    
    // PRIORIDADE 1: Obter certificado de configuracoes['certificadoDigitalBytes'] (arquivo PFX importado)
    // PRIORIDADE 2: Obter de certificadoDigitalUrl (se for base64)
    // PRIORIDADE 3: Tentar ler arquivo se certificadoDigitalUrl for um caminho
    
    String? certificadoBase64;
    
    // PRIORIDADE 1: Certificado em base64 nas configurações (arquivo PFX importado)
    if (empresa.configuracoes != null && empresa.configuracoes!['certificadoDigitalBytes'] != null) {
      final certBytes = empresa.configuracoes!['certificadoDigitalBytes'];
      if (certBytes is String && certBytes.isNotEmpty) {
        certificadoBase64 = certBytes;
        debugPrint('>>> [NFCeBackend] ✅ Certificado encontrado em configuracoes.certificadoDigitalBytes (${certBytes.length} chars)');
      } else {
        debugPrint('>>> [NFCeBackend] ⚠️ certificadoDigitalBytes existe mas está vazio ou não é String');
      }
    } else {
      debugPrint('>>> [NFCeBackend] ⚠️ configuracoes é null ou não contém certificadoDigitalBytes');
    }
    
    // PRIORIDADE 2: Se não encontrou, tentar certificadoDigitalUrl (pode ser base64 ou caminho)
    if (certificadoBase64 == null || certificadoBase64.isEmpty) {
      if (empresa.certificadoDigitalUrl != null && empresa.certificadoDigitalUrl!.isNotEmpty) {
        final url = empresa.certificadoDigitalUrl!;
        
        // Se começa com "base64:", é base64 direto
        if (url.startsWith('base64:') || url.startsWith('base64:pem:')) {
          certificadoBase64 = url.replaceFirst(RegExp(r'^base64:?(pem:)?'), '');
          debugPrint('>>> [NFCeBackend] ✅ Certificado encontrado em certificadoDigitalUrl (base64, ${certificadoBase64.length} chars)');
        } else {
          // Se for um caminho de arquivo, tentar ler (mas geralmente não existe mais)
          debugPrint('>>> [NFCeBackend] ⚠️ certificadoDigitalUrl é um caminho de arquivo: $url');
          debugPrint('>>> [NFCeBackend] Arquivos temporários geralmente não existem mais após reiniciar o app');
        }
      }
    }
    
    // Se ainda não encontrou, usar string vazia
    certificadoBase64 ??= '';
    
    if (certificadoBase64.isEmpty) {
      debugPrint('>>> [NFCeBackend] ❌❌❌ ERRO: Certificado não encontrado!');
      debugPrint('>>> [NFCeBackend]   configuracoes: ${empresa.configuracoes}');
      debugPrint('>>> [NFCeBackend]   certificadoDigitalUrl: ${empresa.certificadoDigitalUrl}');
    } else {
      debugPrint('>>> [NFCeBackend] ✅ Certificado encontrado: ${certificadoBase64.length} caracteres em base64');
    }
    
    // Preparar configuracoes com certificado (prioridade 1 no backend)
    final configuracoes = <String, dynamic>{};
    if (certificadoBase64.isNotEmpty) {
      configuracoes['certificadoDigitalBytes'] = certificadoBase64;
      debugPrint('>>> [NFCeBackend] ✅ Certificado adicionado em configuracoes.certificadoDigitalBytes');
    }
    
    // Adicionar outras configurações se existirem
    if (empresa.configuracoes != null) {
      empresa.configuracoes!.forEach((key, value) {
        if (key != 'certificadoDigitalBytes') { // Já adicionamos acima
          configuracoes[key] = value;
        }
      });
    }
    
    final dadosEmpresa = <String, dynamic>{
      'cnpj': empresa.cnpj?.replaceAll(RegExp(r'[^0-9]'), '') ?? '',
      'razao_social': empresa.razaoSocial ?? '',
      'razaoSocial': empresa.razaoSocial ?? '',
      'inscricao_estadual': empresa.inscricaoEstadual?.replaceAll(RegExp(r'[^0-9]'), '') ?? '',
      'logradouro': empresa.endereco ?? '',
      'numero': empresa.numero ?? '',
      'bairro': empresa.bairro ?? '',
      'municipio': empresa.cidade ?? '',
      'uf': empresa.estado ?? '',
      'cep': empresa.cep?.replaceAll(RegExp(r'[^0-9]'), '') ?? '',
      'csc': empresa.csc ?? '',
      'csc_id': empresa.cscIdToken ?? '',
      'certificado_base64': certificadoBase64,
      'senha_certificado': empresa.senhaCertificado ?? '',
      'senhaCertificado': empresa.senhaCertificado ?? '',
      'ambiente': (empresa.ambienteHomologacao ?? true) ? 2 : 1,
      'codigo_municipio': empresa.codigoIBGE ?? '',
      'crt': empresa.crt ?? 1, // 1 = Simples Nacional, 3 = Normal
      'configuracoes': configuracoes,
    };
    
    debugPrint('>>> [NFCeBackend] Dados da empresa preparados com sucesso.');
    return dadosEmpresa;
  }
  
  /// Prepara dados completos para emissão
  Map<String, dynamic> _prepararDadosEmissao({
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
  }) {
    // Preparar produtos
    final produtosData = produtos.map((produto) {
      final quantidade = quantidades[produto.id] ?? 1.0;
      final valorUnitario = produto.precoAtual; // Usa preço atual (com promoção se houver)
      final valorTotal = quantidade * valorUnitario;
      
      // Inteligência Fiscal: Auto-correção de CFOP para ST
      String cfopFinal = produto.cfop?.replaceAll(RegExp(r'[^0-9]'), '') ?? '5102';
      final csosnFinal = produto.csosn ?? '102';
      final cstFinal = produto.icmsCst ?? '00';
      
      // Se CSOSN 500 ou CST 60 (ST), o CFOP deve ser 5405 para venda interna
      if ((csosnFinal == '500' || cstFinal == '60') && (cfopFinal == '5102' || cfopFinal == '5101')) {
        cfopFinal = '5405';
      }

      return {
        'codigo': produto.codigo ?? produto.id,
        'descricao': produto.nome,
        'ncm': produto.ncm?.replaceAll(RegExp(r'[^0-9]'), '') ?? '00000000',
        'cfop': cfopFinal,
        'unidade': produto.unidade ?? 'UN',
        'quantidade': quantidade,
        'valor_unitario': valorUnitario,
        'valor_total': valorTotal,
        // Campos fiscais achatados para o backend Python
        'icms_origem': int.tryParse(produto.origem ?? '0') ?? 0,
        'icms_csosn': (empresa.crt == null || empresa.crt != 3) ? (produto.csosn ?? '102') : null,
        'icms_cst': (empresa.crt == 3) ? (produto.icmsCst ?? '00') : null,
        'icms_aliquota': produto.icmsAliquota ?? (empresa.crt == 3 ? 18.0 : 0.0),
        'pis_cst': produto.pisCst ?? '07',
        'pis_aliquota': produto.pisAliquota ?? 0.0,
        'cofins_cst': produto.cofinsCst ?? '07',
        'cofins_aliquota': produto.cofinsAliquota ?? 0.0,
      };
    }).toList();
    
    // Preparar pagamentos
    final pagamentosData = pagamentos.map((pagamento) {
      return {
        'tipo': pagamento.tipo, // NFCePagamento usa 'tipo', não 'tipoPagamento'
        'valor': pagamento.valor,
      };
    }).toList();
    
    // Preparar consumidor
    final consumidorData = <String, dynamic>{};
    if (cpfCnpjConsumidor != null && cpfCnpjConsumidor.isNotEmpty) {
      consumidorData['cpf'] = cpfCnpjConsumidor;
    }
    if (nomeConsumidor != null && nomeConsumidor.isNotEmpty) {
      consumidorData['nome'] = nomeConsumidor;
    }
    
    // Determinar série
    int serieFinal = 1;
    if (serie != null) {
      serieFinal = serie;
    } else if (empresa.serieNFCe != null && empresa.serieNFCe!.isNotEmpty) {
      serieFinal = int.tryParse(empresa.serieNFCe!) ?? 1;
    }

    return {
      'empresa': _prepararDadosEmpresa(empresa),
      'itens': produtosData, // Nome correto para o backend
      'pagamentos': pagamentosData,
      'valor_total': valorTotal, // Campo obrigatório no backend
      if (consumidorData.isNotEmpty) 'consumidor': consumidorData,
      if (consumidorData.containsKey('cpf')) 'cpf_consumidor': consumidorData['cpf'],
      if (consumidorData.containsKey('nome')) 'nome_consumidor': consumidorData['nome'],
      'observacoes': observacoes ?? '',
      'serie': serieFinal,
      'numero': null, // Será gerado pelo backend Python
    };
  }
  
  /// Cria objeto NFCe a partir da resposta do backend
  NFCe _criarNFCeDaResposta({
    required Map<String, dynamic> data,
    required Empresa empresa,
    required List<Produto> produtos,
    required Map<String, double> quantidades,
    required List<NFCePagamento> pagamentos,
    required double valorTotal,
    String? cpfCnpjConsumidor,
    String? nomeConsumidor,
    String? observacoes,
  }) {
    // Criar itens da NFC-e a partir dos produtos
    final itens = produtos.map((produto) {
      final quantidade = quantidades[produto.id] ?? 1.0;
      final valorUnitario = produto.precoAtual; // Usa preço atual (com promoção se houver)
      final valorTotalItem = quantidade * valorUnitario;
      
      // Aplicar mesma inteligência na criação do objeto local
      String cfopFinal = produto.cfop ?? '5102';
      if ((produto.csosn == '500' || produto.icmsCst == '60') && (cfopFinal == '5102' || cfopFinal == '5101')) {
        cfopFinal = '5405';
      }

      return NFCeItem(
        produtoId: produto.id,
        codigo: produto.codigo ?? produto.id,
        descricao: produto.nome,
        ncm: produto.ncm ?? '00000000',
        cfop: cfopFinal,
        unidade: produto.unidade ?? 'UN',
        quantidade: quantidade,
        valorUnitario: valorUnitario,
        valorTotal: valorTotalItem,
        origem: produto.origem ?? '0',
        csosn: produto.csosn ?? '102',
        icmsCst: produto.icmsCst,
        icmsAliquota: produto.icmsAliquota ?? 0.0,
      );
    }).toList();
    
    // Status da NFC-e
    String statusStr = (data['status']?.toString() ?? 'processando').toLowerCase();
    if (statusStr == 'sucesso' || statusStr == 'autorizado') {
      statusStr = 'autorizada';
    }
    
    final chave = data['chave_acesso'] ?? data['chave'] ?? '';
    final numero = data['numero']?.toString() ?? '';
    final serie = data['serie']?.toString() ?? '1';
    final protocolo = data['protocolo']?.toString() ?? '';
    final xml = data['xml'] ?? data['xml_final'] ?? '';
    final qrCode = data['qrCode'] ?? data['qr_code'] ?? '';

    return NFCe(
      id: (chave.isNotEmpty) ? chave : DateTime.now().millisecondsSinceEpoch.toString(),
      empresaId: empresa.id,
      chaveAcesso: chave,
      numero: numero,
      serie: serie,
      status: statusStr,
      protocolo: protocolo,
      qrCode: qrCode,
      xmlEnviado: xml,
      valorTotal: valorTotal,
      dataEmissao: DateTime.now(),
      itens: itens,
      pagamentos: pagamentos,
      cpfCnpjConsumidor: cpfCnpjConsumidor,
      nomeConsumidor: nomeConsumidor,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  /// Salva o XML da NFC-e no Google Drive de forma assíncrona (fundo)
  void _salvarXmlNoDrive(NFCe nfce, Empresa empresa) {
    if (nfce.xmlEnviado == null || nfce.xmlEnviado!.isEmpty) return;

    // Rodar em background para não travar a UI
    Future.microtask(() async {
      try {
        debugPrint('>>> [NFCeDrive] Tentando salvar XML no Drive: ${nfce.chaveAcesso}');
        
        final sucesso = await GoogleDriveService.instance.salvarNotaXml(
          empresa: empresa,
          tipoNota: 'NFCe',
          chaveAcesso: nfce.chaveAcesso ?? nfce.id,
          conteudoXml: nfce.xmlEnviado!,
          dataEmissao: nfce.dataEmissao,
        );

        if (sucesso) {
          debugPrint('>>> [NFCeDrive] ✅ XML organizado com sucesso no Google Drive!');
        } else {
          debugPrint('>>> [NFCeDrive] ⚠️ Falha ao organizar XML no Drive (verifique login)');
        }
      } catch (e) {
        debugPrint('>>> [NFCeDrive] ❌ Erro ao processar salvamento no Drive: $e');
      }
    });
  }
}

