// Este arquivo é Dart puro (sem Flutter) de propósito: assim o mesmo código
// pode ser exercitado por um script de linha de comando
// (`dart run tool/neon_storage_check.dart`), sem subir o app.
// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import 'neon_config.dart';

/// Object Storage do Neon (compatível com S3) por trás da MESMA API que o app
/// já usava com o Supabase Storage.
///
/// Motivo: o código do app chama `storage.from(bucket).uploadBinary(...)`,
/// `storage.createBucket(...)`, `storage.listBuckets()` em ~40 lugares. Em vez
/// de reescrever todos esses pontos, as classes de valor abaixo
/// ([FileOptions], [BucketOptions], [SearchOptions], [FileObject], [Bucket],
/// [SortBy]) replicam exatamente a forma das equivalentes do pacote
/// `storage_client`, e [NeonStorage]/[NeonBucket] replicam os métodos usados.
/// Assim a troca fica no cliente, não em cada chamada.
///
/// Toda a comunicação é S3 sobre HTTPS com assinatura AWS Signature V4
/// (implementada aqui — não há SDK S3 em Dart neste projeto). As credenciais
/// vêm de [NeonConfig] (`.env.neon`).
class NeonStorage {
  NeonStorage._();

  static final NeonStorage instance = NeonStorage._();

  /// Operações de arquivo dentro de um bucket: mesmos nomes/assinaturas do
  /// antigo `storage.from(bucket)`.
  NeonBucket from(String bucketId) => NeonBucket(bucketId);

  /// Cria um bucket. No S3 isso é um `PUT /<bucket>`. O Neon Object Storage
  /// gerencia buckets de forma declarativa (`neon.ts`), então um bucket fora
  /// da declaração pode ser recusado — o erro é propagado como exceção, como
  /// antes.
  Future<String> createBucket(
    String id, [
    BucketOptions bucketOptions = const BucketOptions(public: false),
  ]) async {
    await _requisicao(method: 'PUT', bucket: id);
    if (bucketOptions.public) {
      print(
        '>>> [Neon Storage] ⚠️ Bucket "$id" público não é possível via S3: '
        'declare "access: public_read" em neon.ts e rode "neon deploy".',
      );
    }
    return id;
  }

  /// Lista os buckets existentes (mesma forma do antigo `listBuckets()`).
  Future<List<Bucket>> listBuckets() async {
    final resp = await _requisicao(method: 'GET');
    if (resp.statusCode != 200) {
      throw _erro('listar buckets', resp);
    }
    final criados = DateTime.now().toIso8601String();
    return RegExp(r'<Name>([^<]+)</Name>')
        .allMatches(resp.body)
        .map(
          (m) => Bucket(
            id: m.group(1)!,
            name: m.group(1)!,
            owner: '',
            createdAt: criados,
            updatedAt: criados,
            public: false,
          ),
        )
        .toList();
  }

  /// Existe um bucket com este nome?
  Future<bool> bucketExiste(String id) async {
    final resp = await _requisicao(method: 'HEAD', bucket: id);
    return resp.statusCode == 200;
  }

  /// Remove um bucket (vazio).
  Future<String> deleteBucket(String id) async {
    await _requisicao(method: 'DELETE', bucket: id);
    return '';
  }

  // --------------------------------------------------------------------------
  // Assinatura AWS Signature V4 + transporte
  // --------------------------------------------------------------------------

  /// Executa uma requisição S3 assinada.
  ///
  /// [bucket] vazio = operação na raiz do serviço (listar buckets).
  static Future<http.Response> _requisicao({
    required String method,
    String bucket = '',
    String key = '',
    Map<String, String> query = const {},
    List<int> body = const [],
    String? contentType,
  }) async {
    final endpoint = NeonConfig.storageEndpoint.replaceAll(RegExp(r'/+$'), '');
    final region = NeonConfig.storageRegion;
    final accessKey = NeonConfig.storageAccessKey;
    final secretKey = NeonConfig.storageSecretKey;

    final uri = Uri.parse(endpoint);
    final host = uri.hasPort ? '${uri.host}:${uri.port}' : uri.host;

    // Caminho canônico: /bucket/chave/da/empresa (barras preservadas).
    final segmentos = <String>[
      if (bucket.isNotEmpty) bucket,
      if (key.isNotEmpty) ...key.split('/'),
    ];
    final caminho = segmentos.isEmpty
        ? '/'
        : '/${segmentos.map(_uriEncode).join('/')}';

    // Query canônica: chaves ordenadas, valores URI-encoded.
    final queryCanonica = (query.entries.toList()
          ..sort((a, b) => a.key.compareTo(b.key)))
        .map((e) => '${_uriEncode(e.key)}=${_uriEncode(e.value)}')
        .join('&');

    final agora = DateTime.now().toUtc();
    final dataHora = '${_data(agora)}T${_hora(agora)}Z';
    final data = _data(agora);
    final hashPayload =
        sha256.convert(body.isEmpty ? const <int>[] : body).toString();

    final cabecalhos =
        'host:$host\nx-amz-content-sha256:$hashPayload\nx-amz-date:$dataHora\n';
    const assinados = 'host;x-amz-content-sha256;x-amz-date';

    final requisicaoCanonica = [
      method,
      caminho,
      queryCanonica,
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

    final headers = <String, String>{
      'x-amz-date': dataHora,
      'x-amz-content-sha256': hashPayload,
      'Authorization': 'AWS4-HMAC-SHA256 '
          'Credential=$accessKey/$escopo, '
          'SignedHeaders=$assinados, '
          'Signature=$assinatura',
      if (contentType != null) 'Content-Type': contentType,
    };

    final url = Uri.parse(
      '$endpoint$caminho${queryCanonica.isEmpty ? '' : '?$queryCanonica'}',
    );

    switch (method) {
      case 'GET':
        return http.get(url, headers: headers);
      case 'PUT':
        return http.put(url, headers: headers, body: body);
      case 'DELETE':
        return http.delete(url, headers: headers);
      case 'HEAD':
        return http.head(url, headers: headers);
      default:
        throw ArgumentError('Método S3 não suportado: $method');
    }
  }

  static Exception _erro(String acao, http.Response resp) => Exception(
        'Neon Storage: falha ao $acao (HTTP ${resp.statusCode}) '
        '${resp.body.isEmpty ? '' : resp.body}',
      );

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
          saida.write('%${byte.toRadixString(16).toUpperCase().padLeft(2, '0')}');
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

  static String _dois(int n) => n.toString().padLeft(2, '0');
  static String _data(DateTime d) => '${d.year}${_dois(d.month)}${_dois(d.day)}';
  static String _hora(DateTime d) =>
      '${_dois(d.hour)}${_dois(d.minute)}${_dois(d.second)}';
}

/// Operações de arquivo de UM bucket (equivalente ao antigo
/// `storage.from(bucketId)` do Supabase).
class NeonBucket {
  NeonBucket(this.bucketId);

  final String bucketId;

  /// Faz upload de um arquivo do disco (nativo).
  ///
  /// O parâmetro é `Object` de propósito: evita `dart:io` neste arquivo para
  /// não quebrar a compilação web. Aceita `File` (tem `readAsBytes()`) ou
  /// `Uint8List`.
  Future<String> upload(
    String path,
    Object file, {
    FileOptions fileOptions = const FileOptions(),
  }) async {
    final bytes = await _paraBytes(file);
    return uploadBinary(path, bytes, fileOptions: fileOptions);
  }

  /// Faz upload de bytes (usado no web e em todo o resto do app).
  Future<String> uploadBinary(
    String path,
    Uint8List data, {
    FileOptions fileOptions = const FileOptions(),
  }) async {
    final resp = await NeonStorage._requisicao(
      method: 'PUT',
      bucket: bucketId,
      key: path,
      body: data,
      contentType: fileOptions.contentType ?? 'application/octet-stream',
    );
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw NeonStorage._erro('enviar "$bucketId/$path"', resp);
    }
    print('>>> [Neon Storage] ✅ Upload: $bucketId/$path');
    return path;
  }

  /// Baixa o conteúdo do arquivo.
  Future<Uint8List> download(
    String path, {
    Object? transform,
    Map<String, String>? queryParams,
  }) async {
    final resp = await NeonStorage._requisicao(
      method: 'GET',
      bucket: bucketId,
      key: path,
    );
    if (resp.statusCode != 200) {
      throw NeonStorage._erro('baixar "$bucketId/$path"', resp);
    }
    return resp.bodyBytes;
  }

  /// URL pública do arquivo. Só funciona para buckets declarados com
  /// `access: "public_read"` em `neon.ts`.
  String getPublicUrl(String path, {Object? transform}) {
    final endpoint = NeonConfig.storageEndpoint.replaceAll(RegExp(r'/+$'), '');
    final chave = path.split('/').map(NeonStorage._uriEncode).join('/');
    return '$endpoint/$bucketId/$chave';
  }

  /// Lista os arquivos de uma "pasta" ([path] é o prefixo, como no Supabase).
  ///
  /// `offset`/`limit` do [SearchOptions] são aplicados sobre a lista completa
  /// de filhos imediatos (o S3 pagina por token; aqui as páginas são
  /// consumidas internamente).
  Future<List<FileObject>> list({
    String? path,
    SearchOptions searchOptions = const SearchOptions(),
  }) async {
    var prefixo = path ?? '';
    if (prefixo.isNotEmpty && !prefixo.endsWith('/')) prefixo = '$prefixo/';

    final limite = searchOptions.limit ?? 100;
    final deslocamento = searchOptions.offset ?? 0;
    final quantos = deslocamento + limite;

    final encontrados = <FileObject>[];
    String? token;
    var paginas = 0;
    while (encontrados.length < quantos && paginas < 100) {
      paginas++;
      final query = <String, String>{
        'list-type': '2',
        'delimiter': '/',
        if (prefixo.isNotEmpty) 'prefix': prefixo,
        'max-keys': '1000',
        if (token != null) 'continuation-token': token,
      };
      final resp = await NeonStorage._requisicao(
        method: 'GET',
        bucket: bucketId,
        query: query,
      );
      if (resp.statusCode != 200) {
        throw NeonStorage._erro('listar "$bucketId/$prefixo"', resp);
      }
      encontrados.addAll(_parseListagem(resp.body, prefixo));
      token = _texto(resp.body, 'NextContinuationToken');
      if (token == null) break;
    }

    if (searchOptions.search != null && searchOptions.search!.isNotEmpty) {
      final alvo = searchOptions.search!.toLowerCase();
      encontrados.retainWhere((f) => f.name.toLowerCase().contains(alvo));
    }

    if (deslocamento >= encontrados.length) return const [];
    return encontrados.sublist(
      deslocamento,
      (deslocamento + limite).clamp(deslocamento, encontrados.length),
    );
  }

  /// Remove arquivos (um `DELETE` por chave).
  Future<List<FileObject>> remove(List<String> paths) async {
    final removidos = <FileObject>[];
    for (final caminho in paths) {
      final resp = await NeonStorage._requisicao(
        method: 'DELETE',
        bucket: bucketId,
        key: caminho,
      );
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        removidos.add(FileObject(name: _nomeBase(caminho)));
      } else {
        throw NeonStorage._erro('remover "$bucketId/$caminho"', resp);
      }
    }
    print('>>> [Neon Storage] 🗑️ ${removidos.length} arquivo(s) removido(s) de $bucketId');
    return removidos;
  }

  // --------------------------------------------------------------------------

  static String _nomeBase(String caminho) {
    final partes = caminho.split('/');
    return partes.isEmpty ? caminho : partes.last;
  }

  static Future<Uint8List> _paraBytes(Object file) async {
    if (file is Uint8List) return file;
    if (file is List<int>) return Uint8List.fromList(file);
    final dynamic dinamico = file;
    final lido = await dinamico.readAsBytes();
    return lido as Uint8List;
  }

  /// Converte o XML do `ListObjectsV2` (filhos imediatos) em [FileObject].
  ///
  /// `name` é o nome relativo ao prefixo (como no Supabase Storage), não a
  /// chave completa — os chamadores remontam o caminho com o prefixo.
  static List<FileObject> _parseListagem(String xml, String prefixo) {
    final objetos = <FileObject>[];
    for (final bloco in _blocos(xml, 'Contents')) {
      final chave = _texto(bloco, 'Key');
      if (chave == null || chave == prefixo) continue;
      final nome = chave.startsWith(prefixo)
          ? chave.substring(prefixo.length)
          : _nomeBase(chave);
      final tamanho = int.tryParse(_texto(bloco, 'Size') ?? '') ?? 0;
      final modificado = _texto(bloco, 'LastModified');
      objetos.add(
        FileObject(
          name: nome,
          bucketId: null,
          owner: null,
          id: chave,
          updatedAt: modificado,
          createdAt: modificado,
          metadata: {'size': tamanho, 'lastModified': modificado},
        ),
      );
    }
    for (final bloco in _blocos(xml, 'CommonPrefixes')) {
      final completa = _texto(bloco, 'Prefix');
      if (completa == null) continue;
      var nome = completa.startsWith(prefixo)
          ? completa.substring(prefixo.length)
          : completa;
      if (nome.endsWith('/')) nome = nome.substring(0, nome.length - 1);
      if (nome.isEmpty) continue;
      objetos.add(FileObject(name: nome, bucketId: null, owner: null, id: completa));
    }
    return objetos;
  }

  static List<String> _blocos(String xml, String tag) => RegExp(
        '<$tag>(.*?)</$tag>',
        dotAll: true,
      ).allMatches(xml).map((m) => m.group(1)!).toList();

  static String? _texto(String xml, String tag) =>
      RegExp('<$tag>(.*?)</$tag>', dotAll: true).firstMatch(xml)?.group(1);
}

// ============================================================================
// Tipos de valor — mesma forma das classes equivalentes do `storage_client`,
// para que os chamadores existentes continuem compilando sem alteração.
// ============================================================================

/// Opções de upload (equivalente a `FileOptions` do storage_client).
class FileOptions {
  const FileOptions({
    this.cacheControl,
    this.contentType,
    this.upsert = false,
    this.metadata,
  });

  final String? cacheControl;
  final String? contentType;
  final bool upsert;
  final Map<String, dynamic>? metadata;
}

/// Opções de criação de bucket (equivalente a `BucketOptions`).
class BucketOptions {
  const BucketOptions({
    this.public = false,
    this.fileSizeLimit,
    this.allowedMimeTypes,
  });

  final bool public;
  final int? fileSizeLimit;
  final List<String>? allowedMimeTypes;
}

/// Ordenação de uma listagem (equivalente a `SortBy`).
class SortBy {
  const SortBy({this.column, this.order});

  final String? column;
  final String? order;
}

/// Opções de listagem (equivalente a `SearchOptions`).
class SearchOptions {
  const SearchOptions({
    this.limit = 100,
    this.offset = 0,
    this.sortBy = const SortBy(column: 'name', order: 'asc'),
    this.search,
  });

  final int? limit;
  final int? offset;
  final SortBy? sortBy;
  final String? search;
}

/// Um arquivo listado (equivalente a `FileObject`).
class FileObject {
  const FileObject({
    required this.name,
    this.bucketId,
    this.owner,
    this.id,
    this.updatedAt,
    this.createdAt,
    this.lastAccessedAt,
    this.metadata,
    this.buckets,
  });

  final String name;
  final String? bucketId;
  final String? owner;
  final String? id;
  final String? updatedAt;
  final String? createdAt;
  final String? lastAccessedAt;
  final Map<String, dynamic>? metadata;
  final Bucket? buckets;
}

/// Um bucket (equivalente a `Bucket`).
class Bucket {
  const Bucket({
    required this.id,
    required this.name,
    this.owner = '',
    this.createdAt = '',
    this.updatedAt = '',
    this.public = false,
    this.fileSizeLimit,
    this.allowedMimeTypes,
  });

  final String id;
  final String name;
  final String owner;
  final String createdAt;
  final String updatedAt;
  final bool public;
  final int? fileSizeLimit;
  final List<String>? allowedMimeTypes;
}
