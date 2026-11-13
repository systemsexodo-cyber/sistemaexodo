import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:pointycastle/api.dart';
import 'package:flutter/foundation.dart';
import 'package:pointycastle/asymmetric/api.dart';
import 'package:pointycastle/digests/sha256.dart';
import 'package:pointycastle/signers/rsa_signer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Licenca emergencial assinada digitalmente. O aplicativo contém somente a
/// chave publica; a chave privada fica fora do projeto, no computador do dono.
class LicencaEmergencial {
  final String empresaId;
  final String maquinaId;
  final String maquinaNome;
  final DateTime emitidaEm;
  final DateTime expiraEm;
  final String id;

  const LicencaEmergencial({
    required this.empresaId,
    required this.maquinaId,
    required this.maquinaNome,
    required this.emitidaEm,
    required this.expiraEm,
    required this.id,
  });
}

class LicencaEmergenciaService {
  static const _chavePrefs = 'exodo_machine_fallback_id';

  // Chave publica RSA-3072. A chave privada NUNCA deve ser incluida no app.
  static const _modulus =
      'zak4Ceo_RyvgaPho0MubDZpFRqpK7KqqboLfwZ69MfORkN1KFBeWmxT5gXpDkdutc8WYLz2TNm9CRk20MPexbV2jJwZUgUeuPG9GMd237vfG0Koy_H3YbvkyV-Eerw1RYkcJsgJZTDUJXa16ozqrbN9M3tZorIU_ryonJNX6VV4kHmhWkjdpTVjXe2-WLCqoSK1G9qKD_QrjNsGQM7pVRiHEfxo1v7b4Z0XGwfDlNh7p51NRf9jhzMM7W9dv5OhEWq76sP_a0CESWaPBosRXnFDfVSCuKPF8vn54BQE2AVfY8tRRaViOwqX93sEm7jYNXv6Zpiu-Pxta2M5NBItQ58kv5MpHj6exWKvSMaDUP_4exZzNPLcTv1Xo_OnXjZyjumkibImo8PkZLTeXrJNuSpnS5dtAWNDHjPyONoX7pfQVmVetl4nf20U2EjPuuKQFkXUluaDTwD3Zr9T8j_QG0pXuE7Sh3wGUXgwtZKGT_-qvc1_rBw7lJ5f99cCqY_0h';
  static const _exponent = 'AQAB';

  static BigInt _bigIntFromBase64Url(String value) {
    final normalizado = base64Url.normalize(value);
    final bytes = base64Url.decode(normalizado);
    return bytes.fold<BigInt>(
      BigInt.zero,
      (atual, byte) => (atual << 8) | BigInt.from(byte),
    );
  }

  static RSAPublicKey get _publicKey => RSAPublicKey(
    _bigIntFromBase64Url(_modulus),
    _bigIntFromBase64Url(_exponent),
  );

  /// Usa o MachineGuid do Windows: copiar apenas a pasta do programa para
  /// outro PC não copia essa identidade. Fallback local para outros ambientes.
  static Future<String> identificadorMaquina() async {
    if (!kIsWeb && Platform.isWindows) {
      try {
        final resultado = await Process.run('reg', const [
          'query',
          r'HKLM\SOFTWARE\Microsoft\Cryptography',
          '/v',
          'MachineGuid',
        ], runInShell: false).timeout(const Duration(seconds: 5));
        final texto = '${resultado.stdout}\n${resultado.stderr}';
        final match = RegExp(
          r'MachineGuid\s+REG_SZ\s+([^\s]+)',
          caseSensitive: false,
        ).firstMatch(texto);
        final guid = match?.group(1)?.trim();
        if (resultado.exitCode == 0 && guid != null && guid.isNotEmpty) {
          return sha256
              .convert(utf8.encode('EXODO-MACHINE-V1|${guid.toLowerCase()}'))
              .toString();
        }
      } catch (_) {
        // Usa identificador local se a consulta ao registro estiver bloqueada.
      }
    }

    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_chavePrefs);
    if (id == null || id.isEmpty) {
      id = const Uuid().v4();
      await prefs.setString(_chavePrefs, id);
    }
    return sha256
        .convert(utf8.encode('EXODO-FALLBACK-V1|${id.toLowerCase()}'))
        .toString();
  }

  /// Confere a assinatura RSA-SHA256 de um documento (payload + assinatura em
  /// base64). Usado também pela licença de instalação, que é assinada pela
  /// mesma chave privada do dono do sistema.
  static bool verificarAssinatura(
    List<int> bytesAssinados,
    String assinaturaBase64,
  ) {
    try {
      final assinatura = RSASignature(base64Decode(assinaturaBase64));
      final verificador = RSASigner(SHA256Digest(), '0609608648016503040201')
        ..init(false, PublicKeyParameter<RSAPublicKey>(_publicKey));
      return verificador.verifySignature(
        Uint8List.fromList(bytesAssinados),
        assinatura,
      );
    } catch (e) {
      debugPrint('>>> [Licenca] Falha ao conferir assinatura: $e');
      return false;
    }
  }

  /// Valida assinatura, empresa, computador e prazo. Não aceita licença
  /// alterada, expirada, emitida no futuro ou com prazo superior a 30 dias.
  static Future<LicencaEmergencial?> validar(
    String documento, {
    String? empresaIdEsperada,
  }) async {
    try {
      final decoded = jsonDecode(documento);
      if (decoded is! Map) return null;
      final payloadRaw = decoded['payload'];
      final assinaturaTexto = decoded['assinatura']?.toString() ?? '';
      if (payloadRaw is! Map || assinaturaTexto.isEmpty) return null;

      final payload = <String, dynamic>{
        'version': payloadRaw['version'],
        'type': payloadRaw['type'],
        'company_id': payloadRaw['company_id'],
        'machine_id': payloadRaw['machine_id'],
        'machine_name': payloadRaw['machine_name'],
        'issued_at': payloadRaw['issued_at'],
        'expires_at': payloadRaw['expires_at'],
        'license_id': payloadRaw['license_id'],
      };

      if (payload['version'] != 1 || payload['type'] != 'emergencial') {
        return null;
      }
      final empresaId = payload['company_id']?.toString() ?? '';
      final maquinaId = payload['machine_id']?.toString() ?? '';
      final id = payload['license_id']?.toString() ?? '';
      if (empresaId.isEmpty || maquinaId.isEmpty || id.isEmpty) return null;
      if (empresaIdEsperada != null && empresaId != empresaIdEsperada) {
        return null;
      }

      final maquinaAtual = await identificadorMaquina();
      if (maquinaId != maquinaAtual) return null;

      final emitida = DateTime.tryParse(payload['issued_at']?.toString() ?? '');
      final expira = DateTime.tryParse(payload['expires_at']?.toString() ?? '');
      if (emitida == null || expira == null) return null;
      final agora = DateTime.now().toUtc();
      if (emitida.isAfter(agora.add(const Duration(minutes: 5)))) return null;
      if (!expira.isAfter(agora)) return null;
      if (expira.difference(emitida) > const Duration(days: 30, hours: 1)) {
        return null;
      }

      final bytesAssinados = Uint8List.fromList(
        utf8.encode(jsonEncode(payload)),
      );
      if (!verificarAssinatura(bytesAssinados, assinaturaTexto)) {
        return null;
      }

      return LicencaEmergencial(
        empresaId: empresaId,
        maquinaId: maquinaId,
        maquinaNome: payload['machine_name']?.toString() ?? '',
        emitidaEm: emitida.toUtc(),
        expiraEm: expira.toUtc(),
        id: id,
      );
    } catch (e) {
      debugPrint('>>> [Licenca] Documento emergencial recusado: $e');
      return null;
    }
  }
}
