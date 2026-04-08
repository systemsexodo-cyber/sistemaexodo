import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import '../models/agendamento_servico.dart';
import '../models/empresa.dart';

/// Serviço para integração com WhatsApp via Evolution API
class WhatsAppService {
  final String apiUrl;
  final String apiKey;
  final String instanceName;
  final bool isTwilioBridge; // Nova flag

  WhatsAppService({
    required this.apiUrl,
    required this.apiKey,
    required this.instanceName,
    this.isTwilioBridge = false,
  });

  /// Cria uma instância do serviço a partir da empresa
  factory WhatsAppService.fromEmpresa(Empresa empresa) {
    if (empresa.whatsappApiUrl == null || 
        empresa.whatsappApiKey == null || 
        empresa.whatsappInstanceName == null) {
      throw Exception('Configurações de WhatsApp incompletas');
    }
    return WhatsAppService(
      apiUrl: empresa.whatsappApiUrl!,
      apiKey: empresa.whatsappApiKey!,
      instanceName: empresa.whatsappInstanceName ?? '',
      isTwilioBridge: empresa.whatsappTipo == 'twilio' || empresa.whatsappInstanceName == 'twilio-bridge',
    );
  }

  /// Headers padrão para todas as requisições
  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    'apikey': apiKey,
  };

  /// URL base normalizada (sem barra no final)
  String get _baseUrl => apiUrl.endsWith('/') ? apiUrl.substring(0, apiUrl.length - 1) : apiUrl;

  /// Verifica o estado da conexão do WhatsApp
  /// Retorna 'open' se conectado, 'close' se desconectado, ou null em caso de erro
  Future<String?> verificarConexao() async {
    print('>>> [WhatsApp] Verificando conexão para: $instanceName (Tipo: ${isTwilioBridge ? 'Twilio' : 'Evolution'})');
    try {
      if (isTwilioBridge) {
        // Para a ponte no Render, apenas verificamos se o serviço está online
        final response = await http.get(Uri.parse(_baseUrl)).timeout(const Duration(seconds: 15));
        return response.statusCode == 200 ? 'open' : 'close';
      }

      final response = await http.get(
        Uri.parse('$_baseUrl/instance/connectionState/$instanceName'),
        headers: _headers,
      ).timeout(const Duration(seconds: 15));

      print('>>> [WhatsApp] Resposta connectionState: ${response.statusCode} - ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        // Evolution API retorna { "instance": { "state": "open" } }
        if (data['instance'] != null && data['instance']['state'] != null) {
          final state = data['instance']['state'];
          print('>>> [WhatsApp] Estado atual: $state');
          return state;
        }
        // Formato alternativo
        if (data['state'] != null) {
          print('>>> [WhatsApp] Estado atual (alternativo): ${data['state']}');
          return data['state'];
        }
      }
      return null;
    } catch (e) {
      print('>>> [WhatsApp] Erro ao verificar conexão: $e');
      return null;
    }
  }

  /// Verifica se o WhatsApp está conectado
  Future<bool> isConectado() async {
    final state = await verificarConexao();
    return state == 'open';
  }

  /// Obtém o QR Code para conexão (base64)
  Future<String?> obterQRCode() async {
    print('>>> [WhatsApp] Solicitando QR Code para: $instanceName');
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/instance/connect/$instanceName'),
        headers: _headers,
      ).timeout(const Duration(seconds: 30));

      print('>>> [WhatsApp] Resposta obterQRCode: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['base64'] != null) {
          print('>>> [WhatsApp] QR Code (base64) obtido');
          return data['base64'];
        }
        if (data['qrcode'] != null && data['qrcode']['base64'] != null) {
          print('>>> [WhatsApp] QR Code (nested base64) obtido');
          return data['qrcode']['base64'];
        }
        if (data['code'] != null) {
          print('>>> [WhatsApp] QR Code (string) obtido: ${data['code']}');
          return data['code'];
        }
        print('>>> [WhatsApp] Resposta 200 sem QR esperado: ${response.body}');
      } else {
        print('>>> [WhatsApp] Erro ao obter QR Code (${response.statusCode}): ${response.body}');
      }
      return null;
    } catch (e) {
      print('>>> [WhatsApp] Exceção ao obter QR Code: $e');
      return null;
    }
  }

  /// Cria uma nova instância na Evolution API
  Future<bool> criarInstancia() async {
    print('>>> [WhatsApp] Tentando criar instância: $instanceName');
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/instance/create'),
        headers: _headers,
        body: jsonEncode({
          'instanceName': instanceName,
          'token': apiKey,
          'qrcode': true,
          'integration': 'BAILEYS',
        }),
      ).timeout(const Duration(seconds: 30));

      print('>>> [WhatsApp] Resposta criarInstancia: ${response.statusCode}');

      if (response.statusCode == 201 || response.statusCode == 200) {
        print('>>> [WhatsApp] Instância criada ou existente');
        return true;
      } else {
        final data = jsonDecode(response.body);
        final message = data['message']?.toString() ?? data['response']?['message']?.toString() ?? '';
        
        if (message.contains('already exists') || 
            message.contains('already in use') ||
            message.contains('já existe')) {
          print('>>> [WhatsApp] Instância já existe no servidor');
          return true;
        }
        print('>>> [WhatsApp] Erro ao criar: ${response.statusCode} - ${response.body}');
        return false;
      }
    } catch (e) {
      print('>>> [WhatsApp] Erro ao criar instância: $e');
      return false;
    }
  }

  /// Desconecta a instância (Logout)
  Future<bool> desconectar() async {
    print('>>> [WhatsApp] Desconectando: $instanceName');
    try {
      final response = await http.delete(
        Uri.parse('$_baseUrl/instance/logout/$instanceName'),
        headers: _headers,
      ).timeout(const Duration(seconds: 30));

      print('>>> [WhatsApp] Resposta logout: ${response.statusCode}');
      return response.statusCode == 200;
    } catch (e) {
      print('>>> [WhatsApp] Erro ao desconectar: $e');
      return false;
    }
  }

  /// Deleta a instância completamente
  Future<bool> deletarInstancia() async {
    print('>>> [WhatsApp] Deletando instância: $instanceName');
    try {
      final response = await http.delete(
        Uri.parse('$_baseUrl/instance/delete/$instanceName'),
        headers: _headers,
      ).timeout(const Duration(seconds: 30));

      print('>>> [WhatsApp] Resposta delete: ${response.statusCode}');
      return response.statusCode == 200;
    } catch (e) {
      print('>>> [WhatsApp] Erro ao deletar: $e');
      return false;
    }
  }

  /// Formata o número de telefone para o padrão internacional
  String formatarNumero(String numero) {
    String limpo = numero.replaceAll(RegExp(r'[^0-9]'), '');
    if (!limpo.startsWith('55')) {
      if (limpo.startsWith('0')) limpo = limpo.substring(1);
      limpo = '55$limpo';
    }
    return limpo;
  }

  /// Envia uma mensagem de texto (Detecta se é Evolution ou Twilio)
  Future<bool> enviarMensagem(String numero, String mensagem) async {
    try {
      final numFmt = formatarNumero(numero);
      
      if (isTwilioBridge) {
        // Lógica para a nova Ponte no Render (Twilio)
        final response = await http.post(
          Uri.parse('$_baseUrl/send-message'),
          headers: {
            'Content-Type': 'application/json',
            'x-api-key': apiKey,
          },
          body: jsonEncode({
            'to': numFmt,
            'message': mensagem,
          }),
        ).timeout(const Duration(seconds: 30));
        return response.statusCode == 200;
      } else {
        // Lógica para Evolution API
        final response = await http.post(
          Uri.parse('$_baseUrl/message/sendText/$instanceName'),
          headers: _headers,
          body: jsonEncode({
            'number': numFmt,
            'text': mensagem,
          }),
        ).timeout(const Duration(seconds: 30));
        return response.statusCode == 200 || response.statusCode == 201;
      }
    } catch (e) {
      print('>>> [WhatsApp] Erro ao enviar mensagem: $e');
      return false;
    }
  }

  /// Envia mensagem de teste
  Future<bool> enviarMensagemTeste(String numero) async {
    return enviarMensagem(numero, '✅ *Teste de Conexão*\n\nSua integração WhatsApp está OK!');
  }

  // Templates...
  String templateAgendamentoCriado({required AgendamentoServico agendamento, required String nomeEmpresa, String? telefoneEmpresa}) {
    final df = DateFormat('dd/MM/yyyy', 'pt_BR');
    final tf = DateFormat('HH:mm', 'pt_BR');
    return '*Agendamento Confirmado!*\n\nOlá, ${agendamento.cliente?.nome ?? 'Cliente'}!\n\n📅 Data: ${df.format(agendamento.dataAgendamento)}\n🕐 Horário: ${tf.format(agendamento.dataAgendamento)}\n🐕 Pet: ${agendamento.pet?.nome ?? 'Pet'}\n\n📍 $nomeEmpresa';
  }

  String templateStatusAlterado({required AgendamentoServico agendamento, required String nomeEmpresa}) {
    return '*Atualização*\n\nNovo status: *${agendamento.status}*\n🐕 Pet: ${agendamento.pet?.nome ?? 'Pet'}\n\n📍 $nomeEmpresa';
  }

  String templateLembrete({required AgendamentoServico agendamento, required String nomeEmpresa}) {
    final tf = DateFormat('HH:mm', 'pt_BR');
    return '*Lembrete*\n\nVocê tem agendamento amanhã:\n🕐 Horário: ${tf.format(agendamento.dataAgendamento)}\n🐕 Pet: ${agendamento.pet?.nome ?? 'Pet'}\n\n📍 $nomeEmpresa';
  }

  Future<bool> notificarAgendamentoCriado({required AgendamentoServico agendamento, required String nomeEmpresa, String? telefoneEmpresa}) async {
    final tel = agendamento.cliente?.whatsapp ?? agendamento.cliente?.telefone;
    if (tel == null) return false;
    return enviarMensagem(tel, templateAgendamentoCriado(agendamento: agendamento, nomeEmpresa: nomeEmpresa, telefoneEmpresa: telefoneEmpresa));
  }

  Future<bool> notificarStatusAlterado({required AgendamentoServico agendamento, required String nomeEmpresa}) async {
    final tel = agendamento.cliente?.whatsapp ?? agendamento.cliente?.telefone;
    if (tel == null) return false;
    return enviarMensagem(tel, templateStatusAlterado(agendamento: agendamento, nomeEmpresa: nomeEmpresa));
  }
}
