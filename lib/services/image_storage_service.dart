import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'dart:async';
import 'package:flutter/foundation.dart' show debugPrint;
import 'neon_storage.dart';
import 'supabase_service.dart';

/// Serviço para armazenar imagens migrado para Supabase
class ImageStorageService {
  static const String _bucket = 'imagens';

  /// Descobre o formato real pelos bytes. O arquivo era sempre salvo como
  /// `.jpg` com `image/jpeg`, então um PNG ou WebP subia com extensão e MIME
  /// errados (e alguns navegadores se recusavam a exibir).
  static String _extensaoDaImagem(Uint8List bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return 'jpg';
    }
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return 'png';
    }
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return 'webp';
    }
    if (bytes.length >= 3 &&
        bytes[0] == 0x47 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46) {
      return 'gif';
    }
    return 'jpg';
  }

  static bool _erroDeBucketAusente(String? erro) {
    if (erro == null || erro.isEmpty) return false;
    final texto = erro.toLowerCase();
    return texto.contains('404') ||
        texto.contains('not found') ||
        texto.contains('bucket') &&
            (texto.contains('não existe') ||
                texto.contains('does not exist') ||
                texto.contains('missing'));
  }

  /// O erro foi de permissão/RLS (e não de bucket ausente)? O app fala com o
  /// Storage pela chave anônima; sem política no bucket, o RLS recusa a
  /// gravação com 403 "new row violates row-level security policy".
  static bool _erroDePermissao(String? erro) {
    if (erro == null || erro.isEmpty) return false;
    final texto = erro.toLowerCase();
    return texto.contains('row-level security') ||
        texto.contains('accessdenied') ||
        texto.contains('unauthorized') ||
        texto.contains('http 403');
  }

  static String _contentTypeDaExtensao(String extensao) {
    switch (extensao) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      default:
        return 'image/jpeg';
    }
  }

  /// Reduz a imagem antes de subir, para a loja abrir rapido no celular.
  ///
  /// A logo original costumava ir para o storage do jeito que saiu do celular
  /// (4 mil px, alguns MB): o navegador baixava tudo isso so para desenhar um
  /// quadrado de 50 px no cabecalho. Aqui a imagem e redimensionada para no
  /// maximo [maxLado] px no maior lado e recodificada ate caber em
  /// [limiteBytes]. PNG (com transparencia) continua PNG; o resto vira JPEG.
  static Uint8List otimizarLogo(
    Uint8List bytes, {
    int maxLado = 512,
    int limiteBytes = 350 * 1024,
  }) {
    try {
      final decodificada = img.decodeImage(bytes);
      if (decodificada == null) {
        debugPrint(
          '>>> [ImageStorage] ⚠️ Formato nao decodificado; subindo o original',
        );
        return bytes;
      }

      final manterAlfa = _extensaoDaImagem(bytes) != 'jpg';

      img.Image imagem = decodificada;
      final maiorLado =
          imagem.width > imagem.height ? imagem.width : imagem.height;
      if (maiorLado > maxLado) {
        final escala = maxLado / maiorLado;
        imagem = img.copyResize(
          imagem,
          width: (imagem.width * escala).round(),
          height: (imagem.height * escala).round(),
          interpolation: img.Interpolation.average,
        );
      }

      Uint8List codificar(int qualidade) => manterAlfa
          ? img.encodePng(imagem, level: 9)
          : img.encodeJpg(imagem, quality: qualidade);

      var qualidade = 88;
      var saida = codificar(qualidade);

      // Ainda pesado: baixa a qualidade (JPEG) e, se precisar, o tamanho.
      while (saida.length > limiteBytes && qualidade > 60) {
        qualidade -= 10;
        saida = codificar(qualidade);
      }
      while (saida.length > limiteBytes && imagem.width > 160) {
        imagem = img.copyResize(
          imagem,
          width: (imagem.width * 0.8).round(),
          height: (imagem.height * 0.8).round(),
          interpolation: img.Interpolation.average,
        );
        saida = codificar(qualidade);
      }

      debugPrint(
        '>>> [ImageStorage] Logo otimizada: ${bytes.length} -> '
        '${saida.length} bytes (${imagem.width}x${imagem.height})',
      );
      return saida;
    } catch (e) {
      debugPrint('>>> [ImageStorage] ⚠️ Nao foi possivel otimizar: $e');
      return bytes;
    }
  }

  /// Salva uma imagem no Supabase Storage e o metadado no DB
  static Future<String> salvarImagem({
    required Uint8List imageBytes,
    required String empresaId,
    required String categoria,
    String? nome,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      final String finalName = nome != null 
          ? nome.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_') 
          : 'img_$timestamp';
      final String extensao = _extensaoDaImagem(imageBytes);
      
      final String storagePath =
          '$categoria/$empresaId/${finalName}_$timestamp.$extensao';
 
      final String contentType = _contentTypeDaExtensao(extensao);

      debugPrint('>>> [ImageStorage] Salvando imagem no Supabase: $storagePath');

      final problemas = <String>[];

      Future<String?> subirNoBucket(String bucket) =>
          SupabaseService.instance.uploadFile(
            bucket,
            storagePath,
            imageBytes,
            contentType: contentType,
          );

      var url = await subirNoBucket(_bucket);

      // Bucket ausente é a causa mais comum em nuvem nova/recriada. Tenta
      // criar e repetir o upload uma única vez.
      if (url == null && _erroDeBucketAusente(SupabaseService.ultimoErroUpload)) {
        debugPrint('>>> [ImageStorage] Bucket "$_bucket" ausente, tentando criar...');
        try {
          await SupabaseService.instance.client.storage.createBucket(
            _bucket,
            const BucketOptions(public: true),
          );
          url = await subirNoBucket(_bucket);
        } catch (e) {
          debugPrint('>>> [ImageStorage] ⚠️ Não foi possível criar o bucket: $e');
          problemas.add('criar bucket: $e');
        }
      }

      // Ainda sem bucket: usa um bucket público que já existe na nuvem.
      // `atualizacoes` é criado pelo próprio app e liberado para anon pela
      // migração 006; `assets` é o padrão do Neon. Melhor guardar a foto num
      // bucket existente do que o lojista ficar sem subir logo/produto.
      if (url == null && _erroDeBucketAusente(SupabaseService.ultimoErroUpload)) {
        final tentativas = <String>{'atualizacoes'};
        try {
          final buckets =
              await SupabaseService.instance.client.storage.listBuckets();
          // Só buckets públicos servem: a URL pública do Supabase responde
          // 400 em bucket privado e a imagem não apareceria na loja.
          tentativas.addAll(
            buckets.where((b) => b.id != _bucket && b.public).map((b) => b.id),
          );
        } catch (e) {
          debugPrint('>>> [ImageStorage] ⚠️ Não foi possível listar buckets: $e');
          problemas.add('listar buckets: $e');
        }
        for (final bucketId in tentativas) {
          url = await subirNoBucket(bucketId);
          if (url != null) {
            debugPrint('>>> [ImageStorage] ✅ Salvo no bucket alternativo '
                '"$bucketId"');
            break;
          }
        }
        if (url == null) {
          problemas.add('nenhum bucket alternativo aceitou a gravação');
        }
      }
 
      if (url == null) {
        final motivo = SupabaseService.ultimoErroUpload;
        final dica = _erroDeBucketAusente(motivo)
            ? ' (crie o bucket "imagens": aplique '
                'scripts/migrations/016_bucket_imagens.sql no SQL Editor '
                'da nuvem)'
            : _erroDePermissao(motivo) ||
                    problemas.any(_erroDePermissao)
                ? ' (aplique scripts/migrations/017_storage_imagens_nuvem.sql '
                    'no SQL Editor da nuvem: cria o bucket público "imagens" '
                    'e libera a gravação para o papel anon)'
                : '';
        throw Exception(
          'Falha ao subir imagem para o storage'
          '${motivo == null || motivo.isEmpty ? '' : ': $motivo'}'
          '${problemas.isEmpty ? '' : ' | ${problemas.join(' | ')}'}'
          '$dica',
        );
      }
 
      // A imagem JÁ está no storage neste ponto. O metadado é só um índice da
      // galeria: se a tabela `imagens` não existir/estiver bloqueada por RLS,
      // antes isso derrubava o upload inteiro e a foto do produto se perdia.
      try {
        await SupabaseService.instance.insert('imagens', {
          'empresa_id': empresaId,
          'categoria': categoria,
          'nome': nome ?? finalName,
          'url': url,
          'tamanho_bytes': imageBytes.length,
        });
      } catch (e) {
        debugPrint('>>> [ImageStorage] ⚠️ Imagem salva, mas o metadado falhou: $e');
      }
 
      return url; // Retorna a URL pública
    } catch (e) {
      debugPrint('>>> [ImageStorage] ❌ ERRO ao salvar imagem: $e');
      rethrow;
    }
  }
 
  /// Salva e retorna a URL
  static Future<String> salvarImagemERetornarUrl({
    required Uint8List imageBytes,
    required String empresaId,
    required String categoria,
    String? nome,
    Map<String, dynamic>? metadata,
  }) async {
    return await salvarImagem(
      imageBytes: imageBytes,
      empresaId: empresaId,
      categoria: categoria,
      nome: nome,
      metadata: metadata,
    );
  }

  /// Lista imagens de uma empresa/categoria via Supabase
  static Future<List<Map<String, dynamic>>> listarImagens({
    required String empresaId,
    String? categoria,
  }) async {
    try {
      final Map<String, dynamic> filters = {'empresa_id': empresaId};
      if (categoria != null) filters['categoria'] = categoria;

      final results = await SupabaseService.instance.select(
        'imagens',
        filters: filters,
        orderBy: 'created_at',
        descending: true,
      );

      return results.map((item) => {
        'id': item['url'], // Usando URL como ID para deleção fácil
        'nome': item['nome'],
        'url': item['url'],
        'categoria': item['categoria'],
        'tamanhoBytes': item['tamanho_bytes'],
        'dataUpload': item['created_at'] != null ? DateTime.parse(item['created_at']) : null,
      }).toList();
    } catch (e) {
      debugPrint('>>> [ImageStorage] Erro ao listar: $e');
      return [];
    }
  }

  /// Deleta uma imagem do Storage e do Banco
  static Future<bool> deletarImagem(String url) async {
    try {
      // 1. Localiza o caminho dentro do bucket sem depender do domínio do
      //    storage (Supabase, Neon/Tailscale): o segmento é o nome do bucket.
      final pathSegments = Uri.tryParse(url)?.pathSegments ?? const <String>[];
      final indiceBucket = pathSegments.indexOf(_bucket);
      if (indiceBucket != -1 && indiceBucket < pathSegments.length - 1) {
        final storagePath = pathSegments.skip(indiceBucket + 1).join('/');
        await SupabaseService.instance.deleteFile(_bucket, storagePath);
      }

      // 2. Deletar do Banco de Dados (metadado).
      try {
        await SupabaseService.instance.delete('imagens', {'url': url});
      } catch (e) {
        debugPrint('>>> [ImageStorage] Metadado não removido (imagem já apagada): $e');
      }
      return true;
    } catch (e) {
      debugPrint('>>> [ImageStorage] Erro ao deletar imagem: $e');
      return false;
    }
  }

  /// Obtém imagem (Alias para manter compatibilidade)
  static Future<String?> obterImagem(String idOuUrl) async {
    return idOuUrl;
  }
  
  /// Calcula estatísticas de uso via Banco
  static Future<Map<String, dynamic>> obterEstatisticas(String empresaId) async {
    try {
      final results = await SupabaseService.instance.select(
        'imagens',
        filters: {'empresa_id': empresaId},
      );

      int total = results.length;
      int bytes = 0;
      for (var item in results) {
        bytes += (item['tamanho_bytes'] as int? ?? 0);
      }

      return {
        'totalImagens': total,
        'tamanhoTotalMB': (bytes / (1024 * 1024)).toStringAsFixed(2),
      };
    } catch (e) {
      debugPrint('>>> [ImageStorage] Erro nas estatísticas: $e');
      return {'totalImagens': 0, 'tamanhoTotalMB': '0.00'};
    }
  }
}
