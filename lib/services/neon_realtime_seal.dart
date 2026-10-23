import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart';

import 'neon_config.dart';

/// Credencial assinada ("selo") de uma live query do Neon Realtime.
///
/// O Realtime não aceita SQL direto do cliente: o cliente manda um token
/// opaco (o *capability*) que carrega a consulta cifrada. Este arquivo é a
/// implementação Dart dessa emissão — o mesmo formato do SDK oficial
/// (`@neon/realtime`), que é o único publicado (JS/TS).
///
/// Formato, conferido contra `dist/server/capability/issuer.js` do SDK:
///   * `NEON_REALTIME_SECRET` = prefixo `nrt_live_1` + base64url de 32 bytes;
///   * JWE Compact (5 partes: header, "", iv, ciphertext, tag);
///   * header JSON `{"alg":"dir","enc":"A256GCM","v":1}` em base64url;
///   * AES-256-GCM com IV de 12 bytes, tag de 16 bytes e AAD = o próprio
///     header em base64url;
///   * dentro do ciphertext vai `{v, aud, database, error_details,
///     query_fingerprint, sql, parameters, iat, exp}`;
///   * o selo EXPIRA em 60 s → quem assina precisa renovar (`renew`).
///
/// É Dart puro (sem Flutter) de propósito: o mesmo código roda no app e num
/// script de linha de comando (`dart run tool/neon_realtime_probe.dart`).
class NeonRealtimeSelo {
  /// Prefixo do segredo emitido pelo Neon.
  static const String prefixoSegredo = 'nrt_live_1';

  /// Domínio do SHA-256 do fingerprint da consulta (NUL no fim, igual ao SDK).
  static const String dominioFingerprint = 'neon-live-query-fingerprint-v1\u0000';

  /// Quanto tempo o selo vale (o SDK usa 60 s e renova antes de vencer).
  static const Duration validade = Duration(seconds: 60);

  static const int _bytesChave = 32;
  static const int _bytesIv = 12;
  static const int _bytesTag = 16;

  /// Base64url sem `=` (formato usado em todas as partes do token).
  static String base64UrlSemPadding(Uint8List dados) =>
      base64UrlEncode(dados).replaceAll('=', '');

  static Uint8List _decodificarBase64Url(String texto) {
    final comPadding = texto.padRight((texto.length + 3) & ~3, '=');
    return Uint8List.fromList(base64Url.decode(comPadding));
  }

  /// Extrai a chave AES-256 do segredo (falha cedo quando o segredo é inválido).
  static Uint8List chaveDoSegredo(String segredo) {
    final texto = segredo.trim();
    if (!texto.startsWith(prefixoSegredo)) {
      throw ArgumentError(
        'NEON_REALTIME_SECRET inválido: falta o prefixo "$prefixoSegredo".',
      );
    }
    final chave = _decodificarBase64Url(texto.substring(prefixoSegredo.length));
    if (chave.length != _bytesChave) {
      throw ArgumentError(
        'NEON_REALTIME_SECRET inválido: a chave tem ${chave.length} bytes '
        '(esperado $_bytesChave).',
      );
    }
    return chave;
  }

  /// SHA-256 do fingerprint canônico da consulta, como o serviço confere.
  ///
  /// O JSON precisa sair byte a byte igual ao do SDK (`JSON.stringify`), por
  /// isso as chaves vão nesta ordem e sem espaços.
  static String fingerprint(String sql, List<Map<String, Object?>> parametros) {
    final canonico = jsonEncode({'sql': sql, 'parameters': parametros});
    final digest = sha256.convert(<int>[
      ...utf8.encode(dominioFingerprint),
      ...utf8.encode(canonico),
    ]);
    return digest.toString();
  }

  /// Parâmetro de texto (`type_oid` 25 = `text`) para a consulta assinada.
  ///
  /// O valor vai em base64 de UTF-8, igual ao SDK.
  static Map<String, Object?> parametroTexto(String valor) => <String, Object?>{
        'type_oid': 25,
        'value': base64.encode(utf8.encode(valor)),
      };

  /// Assina a consulta e devolve o token pronto para o `subscribe`.
  static NeonRealtimeCapability selar({
    required String sql,
    required String segredo,
    String? banco,
    List<Map<String, Object?>> parametros = const <Map<String, Object?>>[],
    DateTime? agora,
  }) {
    final chave = chaveDoSegredo(segredo);
    final consulta = sql.trim();
    if (consulta.isEmpty) {
      throw ArgumentError('Consulta vazia: não há o que assinar.');
    }
    final versao = DateTime.now();
    final momento = agora ?? versao;
    final emitidoEm = momento.millisecondsSinceEpoch ~/ 1000;
    final expiraEm = emitidoEm + validade.inSeconds;

    final paraFingerprint = parametros
        .map((p) => <String, Object?>{
              'type_oid': p['type_oid'],
              'value': p['value'],
            })
        .toList(growable: false);
    final fingerprintConsulta = fingerprint(consulta, paraFingerprint);

    final header =
        jsonEncode(<String, Object>{'alg': 'dir', 'enc': 'A256GCM', 'v': 1});
    final headerB64 =
        base64UrlSemPadding(Uint8List.fromList(utf8.encode(header)));

    final claims = jsonEncode(<String, Object?>{
      'v': 1,
      'aud': 'realtime-proxy',
      'database': (banco ?? NeonConfig.realtimeDatabase),
      'error_details': 'safe',
      'query_fingerprint': fingerprintConsulta,
      'sql': consulta,
      'parameters': paraFingerprint,
      'iat': emitidoEm,
      'exp': expiraEm,
    });

    final iv = _aleatorio(_bytesIv);
    final gcm = GCMBlockCipher(AESEngine())
      ..init(
        true,
        AEADParameters(
          KeyParameter(chave),
          128,
          iv,
          Uint8List.fromList(utf8.encode(headerB64)),
        ),
      );
    final cifrado = gcm.process(Uint8List.fromList(utf8.encode(claims)));
    final tag = cifrado.sublist(cifrado.length - _bytesTag);
    final corpo = cifrado.sublist(0, cifrado.length - _bytesTag);

    final token = <String>[
      headerB64,
      '',
      base64UrlSemPadding(iv),
      base64UrlSemPadding(corpo),
      base64UrlSemPadding(tag),
    ].join('.');

    return NeonRealtimeCapability(
      capability: token,
      fingerprint: fingerprintConsulta,
      expiraEm: DateTime.fromMillisecondsSinceEpoch(expiraEm * 1000),
    );
  }

  static Uint8List _aleatorio(int bytes) {
    final sorteio = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(bytes, (_) => sorteio.nextInt(256)),
    );
  }
}

/// Selo pronto: o token que vai no `subscribe`, o fingerprint da consulta e
/// quando ele vence (o SDK renova antes disso).
class NeonRealtimeCapability {
  const NeonRealtimeCapability({
    required this.capability,
    required this.fingerprint,
    required this.expiraEm,
  });

  final String capability;
  final String fingerprint;
  final DateTime expiraEm;

  bool vencido({Duration folga = const Duration(seconds: 10)}) =>
      DateTime.now().add(folga).isAfter(expiraEm);

  @override
  String toString() =>
      'capability(fingerprint=${fingerprint.substring(0, 8)}…, '
      'expira=${expiraEm.toIso8601String()})';
}
