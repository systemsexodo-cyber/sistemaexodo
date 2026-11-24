import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Acesso as rotas de administracao do atendente virtual (o container `evo_bot`,
/// publicado em 127.0.0.1:8097 do computador da loja).
class BotAdminService {
  static const String prefUrl = 'bot_admin_url';
  static const String prefToken = 'bot_admin_token';
  static const String urlPadrao = 'http://127.0.0.1:8097';

  static Future<String> url() async {
    final prefs = await SharedPreferences.getInstance();
    final salva = (prefs.getString(prefUrl) ?? '').trim();
    return salva.isEmpty ? urlPadrao : salva;
  }

  static Future<String> token() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getString(prefToken) ?? '').trim();
  }

  static Future<Map<String, String>> _headers() async {
    final t = await token();
    return {
      'Content-Type': 'application/json',
      if (t.isNotEmpty) 'x-bot-token': t,
    };
  }

  static Future<Uri> _uri(String caminho) async {
    final base = await url();
    final raiz = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    return Uri.parse('$raiz$caminho');
  }

  /// `somenteFalhas`: só o que o bot não soube responder (fallback/erro).
  static Future<Map<String, dynamic>> perguntas({
    bool somenteFalhas = true,
    int limite = 60,
  }) async {
    final uri = (await _uri('/admin/perguntas')).replace(queryParameters: {
      'only': somenteFalhas ? 'falhas' : 'todas',
      'limit': '$limite',
    });
    final resposta = await http
        .get(uri, headers: await _headers())
        .timeout(const Duration(seconds: 20));
    if (resposta.statusCode == 401) {
      throw const BotAdminException(
        'Token recusado. Abra "Conversar com o bot" e informe o BOT_ADMIN_TOKEN da VM.',
        401,
      );
    }
    if (resposta.statusCode != 200) {
      throw BotAdminException(
        'O bot respondeu HTTP ${resposta.statusCode}.',
        resposta.statusCode,
      );
    }
    return jsonDecode(utf8.decode(resposta.bodyBytes)) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> status() async {
    final resposta = await http
        .get(await _uri('/health'))
        .timeout(const Duration(seconds: 10));
    if (resposta.statusCode != 200) {
      throw BotAdminException(
        'O bot respondeu HTTP ${resposta.statusCode}.',
        resposta.statusCode,
      );
    }
    return jsonDecode(utf8.decode(resposta.bodyBytes)) as Map<String, dynamic>;
  }

  /// Nome curto da origem da resposta, para mostrar ao dono da loja.
  static String rotuloOrigem(String? origem) {
    switch (origem) {
      case 'config':
        return 'Do cadastro';
      case 'modelo':
        return 'IA respondeu';
      case 'fallback_preco':
        return 'Não soube o preço';
      case 'fallback_valor':
        return 'Recusou inventar valor';
      case 'fallback_fato':
        return 'Não soube responder';
      case 'erro_ollama':
        return 'IA fora do ar';
      case 'vazio':
        return 'Ficou sem resposta';
      case 'handoff':
        return 'Pediu atendente';
      case 'pedido':
        return 'Perguntou do pedido';
      case 'bloqueio':
        return 'Assunto bloqueado';
      case 'fora_tema':
        return 'Fora do que a loja faz';
      case 'catalogo':
        return 'Do catálogo';
      case 'catalogo_vazio':
        return 'Item não encontrado';
      case 'saude':
        return 'Saúde do pet (equipe)';
      case 'conselho':
        return 'Alimentação (equipe)';
      case 'cuidado':
        return 'Cuidados do pet (equipe)';
      case 'saudacao':
        return 'Saudação';
      default:
        return origem ?? '—';
    }
  }
}

class BotAdminException implements Exception {
  const BotAdminException(this.mensagem, this.codigo);

  final String mensagem;
  final int codigo;

  @override
  String toString() => mensagem;
}
