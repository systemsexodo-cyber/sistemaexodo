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
  }) async {
    try {
      debugPrint('>>> [NFCeBackend] Iniciando emissão via backend Python (PyNFe)...');
      
      // Se não houver baseUrl válida ou se for solicitado explicitamente, usar Firebase
      final bool usarFirebase = baseUrl.isEmpty || baseUrl.contains('firebase') || (empresa.configuracoes?['usarFirebaseBridge'] == true);
      
      if (usarFirebase) {
        debugPrint('>>> [NFCeBackend] Detectado modo FIREBASE (Sem Link).');
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
        );
      }

      debugPrint('>>> [NFCeBackend] URL: $baseUrl/api/nfce/emitir');
      
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
          nomeConsumidor: nomeConsumidor,
          observacoes: observacoes,
          ambienteHomologacao: ambienteHomologacao,
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
        final responseData = jsonDecode(response.body) as Map<String, dynamic>;
        
        if (responseData['success'] == true) {
          final data = responseData['data'] as Map<String, dynamic>;
          
          // Verificar se foi autorizada
          final status = data['status'] as String? ?? 'processando';
          
          if (status == 'autorizada') {
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
            return nfce;
          } else {
            // NFC-e rejeitada ou denegada - construir mensagem completa com detalhes da SEFAZ
            String motivoCompleto = '';
            
            // Prioridade 1: xmotivo ou motivo
            final xmotivo = data['xmotivo']?.toString();
            final motivo = data['motivo']?.toString();
            final error = data['error']?.toString();
            
            if (xmotivo != null && xmotivo.isNotEmpty) {
              motivoCompleto = xmotivo;
            } else if (motivo != null && motivo.isNotEmpty) {
              motivoCompleto = motivo;
            } else if (error != null && error.isNotEmpty) {
              motivoCompleto = error;
            } else {
              motivoCompleto = 'Erro desconhecido';
            }
            
            // Adicionar informações técnicas da SEFAZ
            final cstat = data['cstat']?.toString();
            final verAplic = data['verAplic']?.toString();
            final cUF = data['cUF']?.toString();
            final dhRecbto = data['dhRecbto']?.toString();
            
            String mensagemErro = 'Rejeição: $motivoCompleto';
            
            // Adicionar detalhes técnicos
            final detalhes = <String>[];
            if (cstat != null) {
              detalhes.add('Código: $cstat');
            }
            if (verAplic != null) {
              detalhes.add('Versão da aplicação SEFAZ: $verAplic');
            }
            if (cUF != null) {
              final ufMap = {
                '35': 'SP', '11': 'RO', '12': 'AC', '13': 'AM', '14': 'RR',
                '15': 'PA', '16': 'AP', '17': 'TO', '21': 'MA', '22': 'PI',
                '23': 'CE', '24': 'RN', '25': 'PB', '26': 'PE', '27': 'AL',
                '28': 'SE', '29': 'BA', '31': 'MG', '32': 'ES', '33': 'RJ',
                '41': 'PR', '42': 'SC', '43': 'RS', '50': 'MS', '51': 'MT',
                '52': 'GO', '53': 'DF'
              };
              final estado = ufMap[cUF] ?? cUF;
              detalhes.add('Estado: $estado');
            }
            if (dhRecbto != null) {
              detalhes.add('Data/hora do recebimento: $dhRecbto');
            }
            
            if (detalhes.isNotEmpty) {
              mensagemErro += '\n\n${detalhes.join('\n')}';
            }
            
            throw Exception(mensagemErro);
          }
        } else {
          // Construir mensagem de erro completa com todos os detalhes da SEFAZ
          String errorMsg = '';
          
          // Verificar se é erro de certificado
          final errorType = responseData['error_type']?.toString();
          if (errorType == 'CertificateError' || errorType == 'CertificateMissing') {
            // Prioridade 1: Mensagem de erro do certificado
            if (responseData['error'] != null && responseData['error'].toString().trim().isNotEmpty) {
              errorMsg = responseData['error'].toString().trim();
            } else if (responseData['message'] != null && responseData['message'].toString().trim().isNotEmpty) {
              errorMsg = responseData['message'].toString().trim();
            } else if (responseData['details'] != null && responseData['details'].toString().trim().isNotEmpty) {
              errorMsg = responseData['details'].toString().trim();
            } else {
              errorMsg = 'Erro ao carregar certificado digital. Verifique se o certificado e a senha estão corretos.';
            }
            
            // Adicionar diagnóstico se disponível
            final diagnostico = responseData['diagnostico'] as Map<String, dynamic>?;
            if (diagnostico != null) {
              final tipoErro = diagnostico['tipo_erro']?.toString();
              if (tipoErro == 'validacao') {
                // Erro de validação (senha ou formato)
                // A mensagem já deve estar clara no error
              } else if (tipoErro == 'arquivo_nao_encontrado') {
                errorMsg += '\n\nO arquivo do certificado não foi encontrado.';
              }
            }
            
            throw Exception(errorMsg);
          }
          
          // Prioridade 1: Mensagem principal (para outros erros)
          if (responseData['message'] != null && responseData['message'].toString().trim().isNotEmpty) {
            errorMsg = responseData['message'].toString().trim();
          } else if (responseData['error'] != null && responseData['error'].toString().trim().isNotEmpty) {
            errorMsg = responseData['error'].toString().trim();
          } else if (responseData['details'] != null && responseData['details'].toString().trim().isNotEmpty) {
            errorMsg = responseData['details'].toString().trim();
          }
          
          // Adicionar detalhes da resposta da SEFAZ se disponíveis
          final cstat = responseData['cstat']?.toString();
          final motivo = responseData['motivo']?.toString();
          final xmotivo = responseData['xmotivo']?.toString();
          final verAplic = responseData['verAplic']?.toString();
          final cUF = responseData['cUF']?.toString();
          final dhRecbto = responseData['dhRecbto']?.toString();
          
          // Construir mensagem detalhada
          if (cstat != null || motivo != null || xmotivo != null) {
            errorMsg = 'Rejeição: ${xmotivo ?? motivo ?? errorMsg}';
            
            // Adicionar informações técnicas
            final detalhes = <String>[];
            if (cstat != null) {
              detalhes.add('Código: $cstat');
            }
            if (verAplic != null) {
              detalhes.add('Versão da aplicação SEFAZ: $verAplic');
            }
            if (cUF != null) {
              final ufMap = {
                '35': 'SP', '11': 'RO', '12': 'AC', '13': 'AM', '14': 'RR',
                '15': 'PA', '16': 'AP', '17': 'TO', '21': 'MA', '22': 'PI',
                '23': 'CE', '24': 'RN', '25': 'PB', '26': 'PE', '27': 'AL',
                '28': 'SE', '29': 'BA', '31': 'MG', '32': 'ES', '33': 'RJ',
                '41': 'PR', '42': 'SC', '43': 'RS', '50': 'MS', '51': 'MT',
                '52': 'GO', '53': 'DF'
              };
              final estado = ufMap[cUF] ?? cUF;
              detalhes.add('Estado: $estado');
            }
            if (dhRecbto != null) {
              detalhes.add('Data/hora do recebimento: $dhRecbto');
            }
            
            if (detalhes.isNotEmpty) {
              errorMsg += '\n\n${detalhes.join('\n')}';
            }
          }
          
          // Se for erro de dependência faltando, dar instruções claras
          if (errorMsg.contains('signxml') || errorMsg.contains('Dependência faltando')) {
            throw Exception('Dependência do PyNFe está faltando!\n\n'
                'SOLUÇÃO:\n'
                '1. Abra um terminal PowerShell\n'
                '2. Execute:\n'
                '   cd "C:\\Users\\USER\\Downloads\\Sistema Exodo\\sistema_exodo_01-12\\backend_pynfe"\n'
                '   .\\venv\\Scripts\\python.exe -m pip install signxml\n'
                '3. REINICIE o servidor backend (Ctrl+C e depois .\\iniciar_simples.bat)\n'
                '4. Tente emitir NFC-e novamente\n\n'
                'Erro original: $errorMsg');
          }
          
          // Garantir que nunca seja vazio
          if (errorMsg.trim().isEmpty) {
            errorMsg = 'Erro desconhecido ao emitir NFC-e';
          }
          
          throw Exception(errorMsg);
        }
      } else {
        // Tentar decodificar JSON
        Map<String, dynamic> errorData;
        try {
          errorData = jsonDecode(response.body) as Map<String, dynamic>;
        } catch (e) {
          // Se não conseguir decodificar, usar o body como mensagem
          final bodyStr = response.body.toString();
          throw Exception('Erro HTTP ${response.statusCode}: ${bodyStr.isNotEmpty ? bodyStr : 'Resposta vazia do servidor'}');
        }
        
        // Construir mensagem de erro detalhada
        String errorMessage = errorData['error']?.toString().trim() ?? '';
        
        // Se mensagem estiver vazia, tentar outras fontes
        if (errorMessage.isEmpty) {
          errorMessage = errorData['message']?.toString().trim() ?? '';
        }
        if (errorMessage.isEmpty) {
          errorMessage = errorData['details']?.toString().trim() ?? '';
        }
        if (errorMessage.isEmpty) {
          // Último recurso: usar tipo de erro ou mensagem genérica
          final errorType = errorData['error_type']?.toString();
          errorMessage = errorType != null 
              ? 'Erro do tipo $errorType ocorreu no servidor'
              : 'Erro desconhecido ao emitir NFC-e (HTTP ${response.statusCode})';
        }
        
        String? errorType = errorData['error_type']?.toString();
        String? details = errorData['details']?.toString();
        List<dynamic>? traceback = errorData['traceback'] as List<dynamic>?;
        
        // Se houver detalhes, incluir na mensagem
        if (details != null && details.isNotEmpty && details != errorMessage) {
          errorMessage += '\n\nDetalhes técnicos:\n$details';
        } else if (traceback != null && traceback.isNotEmpty) {
          errorMessage += '\n\nÚltimas linhas do erro:\n${traceback.join('\n')}';
        }
        
        // Se houver tipo de erro, incluir no início
        if (errorType != null && !errorMessage.startsWith('[$errorType]')) {
          errorMessage = '[$errorType] $errorMessage';
        }
        
        // Garantir que nunca seja vazio
        if (errorMessage.trim().isEmpty) {
          errorMessage = 'Erro desconhecido ao emitir NFC-e (HTTP ${response.statusCode})';
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
  }) async {
    try {
      debugPrint('>>> [NFCeFirebase] Iniciando emissão via FIRESTORE LISTENER...');
      
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
      );
      
      // Adicionar metadados
      requestData['status'] = 'pendente';
      requestData['created_at'] = FieldValue.serverTimestamp();
      requestData['empresa_id'] = empresa.id;
      
      // Criar documento no Firestore
      final docRef = await FirebaseFirestore.instance
          .collection('nfce_requests')
          .add(requestData);
          
      debugPrint('>>> [NFCeFirebase] Documento enviado: ${docRef.id}. Aguardando processamento...');
      
      // Listen para o resultado (Timeout de 60 segundos)
      final completer = Completer<NFCe>();
      StreamSubscription? subscription;
      
      Timer(const Duration(seconds: 120), () {
        if (!completer.isCompleted) {
          subscription?.cancel();
          completer.completeError(Exception(
            'Timeout ao aguardar resposta do Emissor Local via Firebase (120s).\n\n'
            'Verifique se o programa "ExodoNfceBridge.exe" está aberto no seu PC e se ele mostra "Firebase: CONECTADO".'
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
            completer.completeError(Exception('O emissor autorizou a nota, mas não enviou os dados de retorno.'));
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
          
          completer.complete(nfce);
        } else if (status == 'erro') {
          subscription?.cancel();
          final resultado = data['resultado'] as Map<String, dynamic>?;
          final mensagem = resultado != null ? (resultado['mensagem'] ?? resultado['error'] ?? 'Erro desconhecido') : 'Erro desconhecido no processamento.';
          completer.completeError(Exception(mensagem));
        }
      });
      
      return await completer.future;
    } catch (e) {
      debugPrint('>>> [NFCeFirebase] ❌ ERRO: $e');
      rethrow;
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
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/health'),
      ).timeout(
        const Duration(seconds: 5),
        onTimeout: () => throw Exception('Timeout'),
      );
      
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('>>> [NFCeBackend] Backend não disponível: $e');
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
  }) {
    // Preparar produtos
    final produtosData = produtos.map((produto) {
      final quantidade = quantidades[produto.id] ?? 1.0;
      final valorUnitario = produto.precoAtual; // Usa preço atual (com promoção se houver)
      final valorTotal = quantidade * valorUnitario;
      
      return {
        'codigo': produto.codigo ?? produto.id,
        'descricao': produto.nome,
        'ncm': produto.ncm ?? '00000000',
        'cfop': produto.cfop ?? '5102',
        'unidade': produto.unidade ?? 'UN',
        'quantidade': quantidade,
        'valor_unitario': valorUnitario,
        'valor_total': valorTotal,
        'icms': {
          'cst': '00',
          'aliquota': 18.0,
        },
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
    
    return {
      'empresa': _prepararDadosEmpresa(empresa),
      'itens': produtosData, // Nome correto para o backend
      'pagamentos': pagamentosData,
      'valor_total': valorTotal, // Campo obrigatório no backend
      if (consumidorData.isNotEmpty) 'consumidor': consumidorData,
      if (consumidorData.containsKey('cpf')) 'cpf_consumidor': consumidorData['cpf'],
      if (consumidorData.containsKey('nome')) 'nome_consumidor': consumidorData['nome'],
      'observacoes': observacoes ?? '',
      'serie': int.tryParse(empresa.serieNFCe ?? '1') ?? 1,
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
      
      return NFCeItem(
        produtoId: produto.id,
        codigo: produto.codigo ?? produto.id,
        descricao: produto.nome,
        ncm: produto.ncm ?? '00000000',
        cfop: produto.cfop ?? '5102',
        unidade: produto.unidade ?? 'UN',
        quantidade: quantidade,
        valorUnitario: valorUnitario,
        valorTotal: valorTotalItem,
        origem: produto.origem ?? '0',
        csosn: '102', // Simples Nacional sem tributação
        icmsAliquota: 0.0,
      );
    }).toList();
    
    // Status da NFC-e
    final statusStr = data['status'] as String? ?? 'processando';
    
    return NFCe(
      id: data['chave_acesso'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
      empresaId: empresa.id,
      chaveAcesso: data['chave_acesso'] ?? '',
      numero: data['numero']?.toString() ?? '',
      serie: data['serie']?.toString() ?? '1',
      status: statusStr,
      protocolo: data['protocolo']?.toString(),
      qrCode: data['qr_code'] ?? '',
      xmlEnviado: data['xml'] ?? '',
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
}

