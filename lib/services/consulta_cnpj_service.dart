import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Dados retornados pela consulta de CNPJ
class CnpjDados {
  final String cnpj;
  final String razaoSocial;
  final String? nomeFantasia;
  final String? situacaoCadastral;
  final String? cep;
  final String? tipoLogradouro; // 'Rua' ou 'Avenida'
  final String? logradouro;
  final String? numero;
  final String? complemento;
  final String? bairro;
  final String? municipio;
  final String? uf;
  final String? telefone;
  final String? telefone2;
  final String? email;
  final String? cnaePrincipalCodigo;
  final String? cnaePrincipalDescricao;
  final String? dataAbertura;
  final String fonte;

  CnpjDados({
    required this.cnpj,
    required this.razaoSocial,
    this.nomeFantasia,
    this.situacaoCadastral,
    this.cep,
    this.tipoLogradouro,
    this.logradouro,
    this.numero,
    this.complemento,
    this.bairro,
    this.municipio,
    this.uf,
    this.telefone,
    this.telefone2,
    this.email,
    this.cnaePrincipalCodigo,
    this.cnaePrincipalDescricao,
    this.dataAbertura,
    required this.fonte,
  });

  /// Converte texto para Title Case amigável (ex: "SAO PAULO" -> "São Paulo")
  static String titleCase(String text) {
    if (text.isEmpty) return text;
    final lowerWords = {'de', 'da', 'do', 'das', 'dos', 'e', 'em'};
    return text.toLowerCase().split(' ').map((word) {
      if (word.isEmpty) return '';
      if (lowerWords.contains(word)) return word;
      return word[0].toUpperCase() + word.substring(1);
    }).join(' ');
  }

  /// Formata telefone com DDD: (11) 98888-7777 ou (11) 3333-4444
  static String formatarTelefone(String raw) {
    final digitos = raw.replaceAll(RegExp(r'\D'), '');
    if (digitos.length == 11) {
      return '(${digitos.substring(0, 2)}) ${digitos.substring(2, 7)}-${digitos.substring(7)}';
    } else if (digitos.length == 10) {
      return '(${digitos.substring(0, 2)}) ${digitos.substring(2, 6)}-${digitos.substring(6)}';
    }
    return raw.trim();
  }

  /// Limpa e formata CEP para 00000-000 ou 00000000
  static String formatarCep(String raw) {
    final digitos = raw.replaceAll(RegExp(r'\D'), '');
    return digitos;
  }
}

/// Serviço responsável por consultar dados de CNPJ em bases públicas (BrasilAPI com fallback ReceitaWS)
class ConsultaCnpjService {
  /// Consulta dados cadastrais completos a partir do CNPJ (com ou sem formatação)
  static Future<CnpjDados> consultar(String cnpjRaw) async {
    final cnpj = cnpjRaw.replaceAll(RegExp(r'\D'), '');
    if (cnpj.length != 14) {
      throw Exception('CNPJ inválido. Digite os 14 números.');
    }

    // 1. Tentar BrasilAPI (gratuita, rápida e sem limite de requisição estrito)
    try {
      final dados = await _consultarBrasilApi(cnpj).timeout(
        const Duration(seconds: 8),
      );
      if (dados != null) return dados;
    } catch (e) {
      debugPrint('[ConsultaCnpjService] BrasilAPI falhou: $e. Tentando ReceitaWS...');
    }

    // 2. Fallback: ReceitaWS
    try {
      final dadosFallback = await _consultarReceitaWs(cnpj).timeout(
        const Duration(seconds: 8),
      );
      if (dadosFallback != null) return dadosFallback;
    } catch (e) {
      debugPrint('[ConsultaCnpjService] ReceitaWS falhou: $e');
      throw Exception('Não foi possível obter dados do CNPJ. Verifique a conexão ou se o CNPJ está correto.');
    }

    throw Exception('CNPJ não encontrado ou serviço da Receita temporariamente indisponível.');
  }

  /// Consulta via BrasilAPI
  static Future<CnpjDados?> _consultarBrasilApi(String cnpj) async {
    final url = Uri.parse('https://brasilapi.com.br/api/cnpj/v1/$cnpj');
    final response = await http.get(url, headers: {
      'Accept': 'application/json',
      'User-Agent': 'SistemaExodo/1.0',
    });

    if (response.statusCode == 200) {
      final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;

      final razao = (data['razao_social'] ?? data['nome'] ?? '').toString().trim();
      final fantasia = (data['nome_fantasia'] ?? '').toString().trim();
      final situacao = (data['descricao_situacao_cadastral'] ?? '').toString().trim();

      // Tipo logradouro e logradouro
      String tipoLogradouro = 'Rua';
      final rawTipo = (data['descricao_tipo_de_logradouro'] ?? '').toString().toUpperCase();
      if (rawTipo.contains('AVENIDA') || rawTipo.contains('AV.')) {
        tipoLogradouro = 'Avenida';
      }

      String logradouro = (data['logradouro'] ?? '').toString().trim();
      // Se o logradouro começar com "RUA " ou "AVENIDA ", remover para manter compatibilidade com o seletor do sistema
      final logUpper = logradouro.toUpperCase();
      if (logUpper.startsWith('AVENIDA ')) {
        tipoLogradouro = 'Avenida';
        logradouro = logradouro.substring(8).trim();
      } else if (logUpper.startsWith('AV. ')) {
        tipoLogradouro = 'Avenida';
        logradouro = logradouro.substring(4).trim();
      } else if (logUpper.startsWith('RUA ')) {
        tipoLogradouro = 'Rua';
        logradouro = logradouro.substring(4).trim();
      } else if (logUpper.startsWith('R. ')) {
        tipoLogradouro = 'Rua';
        logradouro = logradouro.substring(3).trim();
      }

      // Telefone
      String? telefone;
      final tel1 = (data['ddd_telefone_1'] ?? '').toString().trim();
      if (tel1.isNotEmpty) {
        telefone = CnpjDados.formatarTelefone(tel1);
      }

      String? telefone2;
      final tel2 = (data['ddd_telefone_2'] ?? '').toString().trim();
      if (tel2.isNotEmpty) {
        telefone2 = CnpjDados.formatarTelefone(tel2);
      }

      final cep = CnpjDados.formatarCep((data['cep'] ?? '').toString());
      final email = (data['email'] ?? '').toString().trim().toLowerCase();

      return CnpjDados(
        cnpj: cnpj,
        razaoSocial: razao,
        nomeFantasia: fantasia.isNotEmpty ? fantasia : null,
        situacaoCadastral: situacao.isNotEmpty ? situacao : null,
        cep: cep.isNotEmpty ? cep : null,
        tipoLogradouro: tipoLogradouro,
        logradouro: logradouro.isNotEmpty ? logradouro : null,
        numero: (data['numero'] ?? '').toString().trim(),
        complemento: (data['complemento'] ?? '').toString().trim(),
        bairro: (data['bairro'] ?? '').toString().trim(),
        municipio: (data['municipio'] ?? '').toString().trim(),
        uf: (data['uf'] ?? '').toString().trim().toUpperCase(),
        telefone: telefone,
        telefone2: telefone2,
        email: email.isNotEmpty ? email : null,
        cnaePrincipalCodigo: data['cnae_fiscal']?.toString(),
        cnaePrincipalDescricao: data['cnae_fiscal_descricao']?.toString(),
        dataAbertura: data['data_inicio_atividade']?.toString(),
        fonte: 'BrasilAPI',
      );
    } else if (response.statusCode == 404) {
      throw Exception('CNPJ não encontrado na base de dados.');
    }
    return null;
  }

  /// Consulta via ReceitaWS (Fallback)
  static Future<CnpjDados?> _consultarReceitaWs(String cnpj) async {
    final url = Uri.parse('https://receitaws.com.br/v1/cnpj/$cnpj');
    final response = await http.get(url, headers: {
      'Accept': 'application/json',
      'User-Agent': 'SistemaExodo/1.0',
    });

    if (response.statusCode == 200) {
      final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;

      if (data['status'] == 'ERROR') {
        throw Exception(data['message'] ?? 'CNPJ não encontrado');
      }

      final razao = (data['nome'] ?? '').toString().trim();
      final fantasia = (data['fantasia'] ?? '').toString().trim();
      final situacao = (data['situacao'] ?? '').toString().trim();

      String tipoLogradouro = 'Rua';
      String logradouro = (data['logradouro'] ?? '').toString().trim();
      final logUpper = logradouro.toUpperCase();
      if (logUpper.startsWith('AVENIDA ')) {
        tipoLogradouro = 'Avenida';
        logradouro = logradouro.substring(8).trim();
      } else if (logUpper.startsWith('AV. ')) {
        tipoLogradouro = 'Avenida';
        logradouro = logradouro.substring(4).trim();
      } else if (logUpper.startsWith('RUA ')) {
        tipoLogradouro = 'Rua';
        logradouro = logradouro.substring(4).trim();
      } else if (logUpper.startsWith('R. ')) {
        tipoLogradouro = 'Rua';
        logradouro = logradouro.substring(3).trim();
      }

      final rawTel = (data['telefone'] ?? '').toString().trim();
      String? telefone;
      if (rawTel.isNotEmpty) {
        // Pode vir múltiplos telefones separados por barra '/'
        final splitTel = rawTel.split('/');
        telefone = CnpjDados.formatarTelefone(splitTel.first);
      }

      final cep = CnpjDados.formatarCep((data['cep'] ?? '').toString());
      final email = (data['email'] ?? '').toString().trim().toLowerCase();

      return CnpjDados(
        cnpj: cnpj,
        razaoSocial: razao,
        nomeFantasia: fantasia.isNotEmpty ? fantasia : null,
        situacaoCadastral: situacao.isNotEmpty ? situacao : null,
        cep: cep.isNotEmpty ? cep : null,
        tipoLogradouro: tipoLogradouro,
        logradouro: logradouro.isNotEmpty ? logradouro : null,
        numero: (data['numero'] ?? '').toString().trim(),
        complemento: (data['complemento'] ?? '').toString().trim(),
        bairro: (data['bairro'] ?? '').toString().trim(),
        municipio: (data['municipio'] ?? '').toString().trim(),
        uf: (data['uf'] ?? '').toString().trim().toUpperCase(),
        telefone: telefone,
        email: email.isNotEmpty ? email : null,
        dataAbertura: data['abertura']?.toString(),
        fonte: 'ReceitaWS',
      );
    }
    return null;
  }
}
