import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:postgres/postgres.dart';

import 'neon_config.dart';

/// Resultado de um teste de um serviço do Neon.
class NeonResultado {
  const NeonResultado(this.servico, this.ok, this.detalhe);

  final String servico;
  final bool ok;
  final String detalhe;

  @override
  String toString() => '[${ok ? 'OK  ' : 'FALHA'}] $servico\n        $detalhe';
}

/// Camada de acesso aos serviços do Neon, em Dart puro.
///
/// Cobre os quatro serviços provisionados (ver `neon.ts`):
/// Postgres, Auth, Object Storage (S3) e Functions. Todas as credenciais vêm
/// de [NeonConfig] (arquivo `.env.neon` gravado por `neon env pull`).
///
/// Não importa Flutter de propósito, para poder ser exercitada por um script
/// de linha de comando (`dart run tool/neon_e2e.dart`).
class NeonService {
  NeonService._();

  // ==========================================================================
  // Postgres
  // ==========================================================================

  /// Monta o [Endpoint] do driver `postgres` a partir de uma URL
  /// `postgresql://usuario:senha@host:porta/banco?...`.
  static Endpoint endpointDaUrl(String url) {
    final uri = Uri.parse(url);
    final userInfo = uri.userInfo;
    final separador = userInfo.indexOf(':');
    final usuario = Uri.decodeComponent(
      separador == -1 ? userInfo : userInfo.substring(0, separador),
    );
    final senha = separador == -1
        ? ''
        : Uri.decodeComponent(userInfo.substring(separador + 1));
    final banco = uri.pathSegments.isEmpty ? 'neondb' : uri.pathSegments.first;
    return Endpoint(
      host: uri.host,
      port: uri.hasPort ? uri.port : 5432,
      database: banco,
      username: usuario,
      password: senha,
    );
  }

  /// Abre uma conexão com o Postgres do Neon (SSL obrigatório).
  static Future<Connection> abrirConexao({String? url}) {
    final destino = (url ?? NeonConfig.databaseUrl).trim();
    if (destino.isEmpty) {
      throw StateError(
        'Neon: DATABASE_URL não configurada. Rode "neon env pull --file '
        '${NeonConfig.nomeArquivo}".',
      );
    }
    return Connection.open(
      endpointDaUrl(destino),
      settings: const ConnectionSettings(
        sslMode: SslMode.require,
        connectTimeout: Duration(seconds: 25),
      ),
    );
  }

  /// Conecta e devolve um resumo do banco (versão, banco, usuário, nº de
  /// tabelas no schema `public`).
  static Future<NeonResultado> testarPostgres() async {
    if (!NeonConfig.postgresDisponivel) {
      return const NeonResultado(
        'Postgres',
        false,
        'DATABASE_URL ausente em ${NeonConfig.nomeArquivo}',
      );
    }
    Connection? conn;
    try {
      conn = await abrirConexao();
      final versao = (await conn.execute('SELECT version()')).first.first
          as String;
      final info = (await conn.execute(
        'SELECT current_database(), current_user',
      ))
          .first;
      final tabelas = (await conn.execute(
        "SELECT count(*) FROM information_schema.tables "
        "WHERE table_schema = 'public'",
      ))
          .first
          .first;
      return NeonResultado(
        'Postgres',
        true,
        '${versao.split(',').first} | db=${info[0]} user=${info[1]} | '
            'tabelas public=$tabelas',
      );
    } catch (e) {
      return NeonResultado('Postgres', false, '${e.runtimeType}: $e');
    } finally {
      await conn?.close();
    }
  }

  // ==========================================================================
  // Auth
  // ==========================================================================

  /// Confere se o Neon Auth responde e quantas chaves o JWKS publica.
  static Future<NeonResultado> testarAuth() async {
    if (!NeonConfig.authDisponivel) {
      return const NeonResultado(
        'Neon Auth',
        false,
        'NEON_AUTH_BASE_URL ausente',
      );
    }
    try {
      final jwks = await http
          .get(Uri.parse(NeonConfig.authJwksUrl))
          .timeout(const Duration(seconds: 20));
      var chaves = 0;
      if (jwks.statusCode == 200) {
        final json = jsonDecode(jwks.body) as Map<String, dynamic>;
        chaves = (json['keys'] as List?)?.length ?? 0;
      }
      final raiz = await http
          .get(Uri.parse(NeonConfig.authBaseUrl))
          .timeout(const Duration(seconds: 20));
      return NeonResultado(
        'Neon Auth',
        jwks.statusCode == 200 && chaves > 0,
        'base=${NeonConfig.authBaseUrl} (HTTP ${raiz.statusCode}) | '
            'jwks HTTP ${jwks.statusCode} chaves=$chaves',
      );
    } catch (e) {
      return NeonResultado('Neon Auth', false, '${e.runtimeType}: $e');
    }
  }

  // ==========================================================================
  // Functions
  // ==========================================================================

  /// Chama a função `hello` publicada pelo `neon deploy`.
  static Future<NeonResultado> testarFunctions() async {
    if (!NeonConfig.functionsDisponiveis) {
      return const NeonResultado(
        'Neon Functions',
        false,
        'NEON_FUNCTION_HELLO_BASE_URL ausente',
      );
    }
    try {
      final url = NeonConfig.functionsHelloUrl.endsWith('/')
          ? NeonConfig.functionsHelloUrl
          : '${NeonConfig.functionsHelloUrl}/';
      final r = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 30));
      return NeonResultado(
        'Neon Functions',
        r.statusCode == 200,
        'GET $url -> HTTP ${r.statusCode} body=${jsonEncode(r.body)}',
      );
    } catch (e) {
      return NeonResultado('Neon Functions', false, '${e.runtimeType}: $e');
    }
  }

  // ==========================================================================
  // Object Storage (S3)
  // ==========================================================================

  /// Lista os buckets e faz um ciclo put/get/delete no bucket configurado.
  static Future<NeonResultado> testarStorage() async {
    if (!NeonConfig.storageDisponivel) {
      return const NeonResultado(
        'Object Storage (S3)',
        false,
        'credenciais AWS_* ausentes em ${NeonConfig.nomeArquivo}',
      );
    }
    final bucket = NeonConfig.storageBucket;
    const chave = 'e2e/neon-dart.txt';
    const conteudo = 'neon-e2e-ok';
    try {
      final lista = await _s3(method: 'GET', path: '/');
      final buckets = RegExp(r'<Name>([^<]+)</Name>')
          .allMatches(lista.body)
          .map((m) => m.group(1))
          .toList();

      await _s3(
        method: 'PUT',
        path: '/$bucket/$chave',
        body: utf8.encode(conteudo),
        contentType: 'text/plain',
      );
      final lido = await _s3(method: 'GET', path: '/$bucket/$chave');
      await _s3(method: 'DELETE', path: '/$bucket/$chave');

      final ok = lista.statusCode == 200 &&
          lido.statusCode == 200 &&
          lido.body == conteudo;
      return NeonResultado(
        'Object Storage (S3)',
        ok,
        'buckets=$buckets | put/get/delete em "$bucket" '
            '(HTTP ${lista.statusCode}/${lido.statusCode}, '
            'lido=${jsonEncode(lido.body)})',
      );
    } catch (e) {
      return NeonResultado(
        'Object Storage (S3)',
        false,
        '${e.runtimeType}: $e',
      );
    }
  }

  // ==========================================================================
  // Teste completo
  // ==========================================================================

  /// Roda todos os testes na ordem e devolve os resultados.
  static Future<List<NeonResultado>> testarTudo() async {
    return [
      await testarPostgres(),
      await testarAuth(),
      await testarFunctions(),
      await testarStorage(),
    ];
  }

  // --------------------------------------------------------------------------
  // Assinatura AWS Signature V4 (S3), necessária porque o Neon Object Storage
  // é compatível com S3 e não há SDK S3 em Dart neste projeto.
  // --------------------------------------------------------------------------

  static Future<http.Response> _s3({
    required String method,
    required String path,
    List<int> body = const [],
    String? contentType,
  }) async {
    const vazio = <int>[];
    final endpoint = NeonConfig.storageEndpoint.replaceAll(RegExp(r'/$'), '');
    final region = NeonConfig.storageRegion;
    final accessKey = NeonConfig.storageAccessKey;
    final secretKey = NeonConfig.storageSecretKey;

    final uri = Uri.parse(endpoint);
    final host = uri.hasPort ? '${uri.host}:${uri.port}' : uri.host;
    final agora = DateTime.now().toUtc();
    final dataHora = '${_data(agora)}T${_hora(agora)}Z';
    final data = _data(agora);
    final hashPayload = sha256.convert(body.isEmpty ? vazio : body).toString();

    final caminhoCanonico = _uriCanonico(path);
    const cabecalhosCanonicos = '';
    final cabecalhos =
        'host:$host\nx-amz-content-sha256:$hashPayload\nx-amz-date:$dataHora\n';
    const assinados = 'host;x-amz-content-sha256;x-amz-date';

    final requisicaoCanonica = [
      method,
      caminhoCanonico,
      cabecalhosCanonicos,
      cabecalhos,
      assinados,
      hashPayload,
    ].join('\n');

    final escopo = '$data/$region/s3/aws4_request';
    final paraAssinar = [
      'AWS4-HMAC-SHA256',
      dataHora,
      escopo,
      sha256.convert(utf8.encode(requisicaoCanonica)).toString(),
    ].join('\n');

    final assinatura = _hex(
      _hmac(_chaveAssinatura(secretKey, data, region), paraAssinar),
    );

    final autorizacao = 'AWS4-HMAC-SHA256 '
        'Credential=$accessKey/$escopo, '
        'SignedHeaders=$assinados, '
        'Signature=$assinatura';

    final headers = <String, String>{
      'x-amz-date': dataHora,
      'x-amz-content-sha256': hashPayload,
      'Authorization': autorizacao,
      'Content-Type': ?contentType,
    };

    final url = Uri.parse('$endpoint$caminhoCanonico');
    return switch (method) {
      'GET' => http.get(url, headers: headers),
      'PUT' => http.put(url, headers: headers, body: body),
      'DELETE' => http.delete(url, headers: headers),
      'HEAD' => http.head(url, headers: headers),
      _ => throw ArgumentError('Método S3 não suportado: $method'),
    };
  }

  /// Codifica o caminho preservando as barras (convenção canônica do S3).
  static String _uriCanonico(String path) {
    if (path.isEmpty) return '/';
    return path.split('/').map(_uriEncode).join('/');
  }

  static String _uriEncode(String valor) {
    const livres =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.~';
    final saida = StringBuffer();
    for (final rune in valor.runes) {
      final caractere = String.fromCharCode(rune);
      if (livres.contains(caractere)) {
        saida.write(caractere);
      } else {
        for (final byte in utf8.encode(caractere)) {
          saida.write(
            '%${byte.toRadixString(16).toUpperCase().padLeft(2, '0')}',
          );
        }
      }
    }
    return saida.toString();
  }

  static String _hex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  static List<int> _hmac(List<int> chave, String mensagem) =>
      Hmac(sha256, chave).convert(utf8.encode(mensagem)).bytes;

  static List<int> _chaveAssinatura(
    String segredo,
    String data,
    String region,
  ) {
    final kData = _hmac(utf8.encode('AWS4$segredo'), data);
    final kRegion = _hmac(kData, region);
    final kServico = _hmac(kRegion, 's3');
    return _hmac(kServico, 'aws4_request');
  }

  static String _doisDigitos(int n) => n.toString().padLeft(2, '0');
  static String _data(DateTime d) =>
      '${d.year}${_doisDigitos(d.month)}${_doisDigitos(d.day)}';
  static String _hora(DateTime d) =>
      '${_doisDigitos(d.hour)}${_doisDigitos(d.minute)}${_doisDigitos(d.second)}';
}
