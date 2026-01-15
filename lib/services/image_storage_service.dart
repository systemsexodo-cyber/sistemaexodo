import 'dart:convert';
import 'dart:typed_data';
import 'dart:async';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:image/image.dart' as img;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'local_storage_service.dart';

/// Serviço para armazenar imagens de forma GRATUITA
/// Tenta salvar no Firebase Firestore primeiro, se falhar usa localStorage como fallback
/// Salva imagens como base64 diretamente no banco de dados
class ImageStorageService {
  static FirebaseFirestore? _firestore;
  static final LocalStorageService _localStorage = LocalStorageService();
  static const String _collection = 'imagens_sistema';
  static const String _localStorageKey = 'exodo_imagens_sistema';
  static const int _maxSizeBytes = 800 * 1024; // 800KB
  static const int _maxWidth = 1920;
  static const int _maxHeight = 1920;
  static const int _quality = 85;

  /// Obtém instância do Firestore com tratamento de erro
  static FirebaseFirestore? get _firestoreInstance {
    try {
      _firestore ??= FirebaseFirestore.instance;
      return _firestore;
    } catch (e) {
      debugPrint('>>> [ImageStorage] ⚠️ Firestore não disponível: $e');
      return null;
    }
  }

  /// Verifica se Firestore está disponível
  static bool get _firestoreDisponivel {
    try {
      return _firestoreInstance != null;
    } catch (e) {
      return false;
    }
  }

  /// Salva uma imagem (tenta Firebase primeiro, fallback para localStorage)
  /// Com redimensionamento e otimização automática
  static Future<String> salvarImagem({
    required Uint8List imageBytes,
    required String empresaId,
    required String categoria,
    String? nome,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      debugPrint('>>> [ImageStorage] ========================================');
      debugPrint('>>> [ImageStorage] SALVANDO IMAGEM');
      debugPrint('>>> [ImageStorage] Tamanho original: ${(imageBytes.length / 1024).toStringAsFixed(2)} KB');
      debugPrint('>>> [ImageStorage] Categoria: $categoria');
      debugPrint('>>> [ImageStorage] ========================================');

      // Comprimir e converter para base64
      final base64String = await _comprimirEConverterParaBase64(imageBytes);
      debugPrint('>>> [ImageStorage] Tamanho do base64: ${(base64String.length / 1024).toStringAsFixed(2)} KB');

      // Verificar se o base64 não excede o limite (1MB)
      if (base64String.length > 1000 * 1024) {
        throw Exception('Imagem muito grande após compressão (${(base64String.length / 1024).toStringAsFixed(2)} KB). Limite: 1MB');
      }

      final imagemId = DateTime.now().millisecondsSinceEpoch.toString();
      final dados = {
        'id': imagemId,
        'empresaId': empresaId,
        'categoria': categoria,
        'nome': nome ?? 'Imagem $imagemId',
        'base64': base64String,
        'tamanhoBytes': base64String.length,
        'tamanhoOriginalBytes': imageBytes.length,
        'dataUpload': DateTime.now().toIso8601String(),
        'metadata': metadata ?? {},
      };

      // TENTAR SALVAR NO FIREBASE PRIMEIRO
      bool salvoNoFirebase = false;
      if (_firestoreDisponivel) {
        try {
          debugPrint('>>> [ImageStorage] Tentando salvar no Firebase...');
          final docRef = _firestoreInstance!.collection(_collection).doc(imagemId);
          await docRef.set({
            ...dados,
            'dataUpload': FieldValue.serverTimestamp(),
          }).timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              debugPrint('>>> [ImageStorage] ⚠️ Timeout ao salvar no Firebase');
              throw TimeoutException('Timeout ao salvar no Firebase');
            },
          );
          salvoNoFirebase = true;
          debugPrint('>>> [ImageStorage] ✅ Imagem salva no Firebase!');
        } catch (e) {
          debugPrint('>>> [ImageStorage] ⚠️ Erro ao salvar no Firebase: $e');
          debugPrint('>>> [ImageStorage] Usando fallback: localStorage');
        }
      } else {
        debugPrint('>>> [ImageStorage] ⚠️ Firebase não disponível, usando localStorage');
      }

      // SALVAR NO LOCALSTORAGE (sempre, como backup)
      try {
        debugPrint('>>> [ImageStorage] Salvando no localStorage...');
        await _salvarNoLocalStorage(imagemId, dados);
        debugPrint('>>> [ImageStorage] ✅ Imagem salva no localStorage!');
      } catch (e) {
        debugPrint('>>> [ImageStorage] ❌ ERRO ao salvar no localStorage: $e');
        // Se nem Firebase nem localStorage funcionaram, lançar erro
        if (!salvoNoFirebase) {
          throw Exception('Não foi possível salvar a imagem (Firebase e localStorage falharam): $e');
        }
      }

      debugPrint('>>> [ImageStorage] ✅ Imagem salva com sucesso!');
      debugPrint('>>> [ImageStorage] ID: $imagemId');
      debugPrint('>>> [ImageStorage] Firebase: ${salvoNoFirebase ? "SIM" : "NÃO"}');
      debugPrint('>>> [ImageStorage] LocalStorage: SIM');
      debugPrint('>>> [ImageStorage] ========================================');

      return imagemId;
    } catch (e, stackTrace) {
      debugPrint('>>> [ImageStorage] ❌ ERRO ao salvar imagem: $e');
      debugPrint('>>> [ImageStorage] StackTrace: $stackTrace');
      rethrow;
    }
  }

  /// Salva no localStorage do navegador
  static Future<void> _salvarNoLocalStorage(String imagemId, Map<String, dynamic> dados) async {
    try {
      debugPrint('>>> [ImageStorage] ========================================');
      debugPrint('>>> [ImageStorage] SALVANDO NO LOCALSTORAGE');
      debugPrint('>>> [ImageStorage] Imagem ID: $imagemId');
      
      final todasImagens = await _carregarTodasImagens();
      debugPrint('>>> [ImageStorage] Imagens existentes: ${todasImagens.length}');
      
      // Verificar tamanho antes de adicionar
      final tamanhoBase64 = dados['base64'] as String? ?? '';
      final tamanhoBytes = tamanhoBase64.length;
      debugPrint('>>> [ImageStorage] Tamanho da nova imagem: ${(tamanhoBytes / 1024).toStringAsFixed(2)} KB');
      
      // Calcular tamanho total aproximado
      int tamanhoTotal = 0;
      for (var entry in todasImagens.entries) {
        final imgData = entry.value as Map<String, dynamic>? ?? {};
        final base64 = imgData['base64'] as String? ?? '';
        tamanhoTotal += base64.length;
      }
      tamanhoTotal += tamanhoBytes;
      debugPrint('>>> [ImageStorage] Tamanho total aproximado: ${(tamanhoTotal / 1024 / 1024).toStringAsFixed(2)} MB');
      
      // Avisar se estiver próximo do limite (5MB é um limite seguro)
      if (tamanhoTotal > 4 * 1024 * 1024) {
        debugPrint('>>> [ImageStorage] ⚠️ ATENÇÃO: Tamanho total próximo do limite do localStorage (5MB)');
      }
      
      todasImagens[imagemId] = dados;
      debugPrint('>>> [ImageStorage] Total após adicionar: ${todasImagens.length}');
      
      // Salvar no localStorage usando LocalStorageService
      // O LocalStorageService já faz jsonEncode internamente
      try {
        await _localStorage.salvar(_localStorageKey, todasImagens);
        debugPrint('>>> [ImageStorage] ✅ Chamada de salvar concluída');
      } catch (e) {
        // Verificar se é erro de quota excedida
        if (e.toString().contains('quota') || e.toString().contains('QUOTA')) {
          throw Exception('LocalStorage cheio! Tamanho total: ${(tamanhoTotal / 1024 / 1024).toStringAsFixed(2)} MB. Limite: ~5MB');
        }
        rethrow;
      }
      
      // Verificar se foi salvo corretamente
      await Future.delayed(const Duration(milliseconds: 100)); // Pequeno delay para garantir
      final verificar = await _carregarTodasImagens();
      debugPrint('>>> [ImageStorage] Verificação após salvar: ${verificar.length} imagens');
      debugPrint('>>> [ImageStorage] Imagem salva existe? ${verificar.containsKey(imagemId)}');
      
      if (!verificar.containsKey(imagemId)) {
        throw Exception('Imagem não foi salva corretamente no localStorage (verificação falhou)');
      }
      
      // Verificar se os dados estão corretos
      final dadosSalvos = verificar[imagemId] as Map<String, dynamic>?;
      if (dadosSalvos == null) {
        throw Exception('Dados da imagem não foram encontrados após salvar');
      }
      
      final base64Salvo = dadosSalvos['base64'] as String? ?? '';
      if (base64Salvo.isEmpty) {
        throw Exception('Base64 da imagem está vazio após salvar');
      }
      
      debugPrint('>>> [ImageStorage] ✅ Salvo no localStorage com sucesso!');
      debugPrint('>>> [ImageStorage] Total de imagens: ${todasImagens.length}');
      debugPrint('>>> [ImageStorage] Tamanho do base64 salvo: ${base64Salvo.length} caracteres');
      debugPrint('>>> [ImageStorage] ========================================');
    } catch (e, stackTrace) {
      debugPrint('>>> [ImageStorage] ❌ ERRO ao salvar no localStorage: $e');
      debugPrint('>>> [ImageStorage] StackTrace: $stackTrace');
      rethrow;
    }
  }

  /// Carrega todas as imagens do localStorage
  static Future<Map<String, dynamic>> _carregarTodasImagens() async {
    try {
      final dados = await _localStorage.carregar(_localStorageKey);
      
      if (dados == null) {
        debugPrint('>>> [ImageStorage] Nenhuma imagem encontrada no localStorage');
        return <String, dynamic>{};
      }
      
      // Garantir que é um Map e converter para Map<String, dynamic>
      if (dados is Map) {
        final map = Map<String, dynamic>.from(dados);
        debugPrint('>>> [ImageStorage] Carregadas ${map.length} imagens do localStorage');
        return map;
      } else {
        debugPrint('>>> [ImageStorage] ⚠️ Dados não são um Map: ${dados.runtimeType}');
        return <String, dynamic>{};
      }
    } catch (e, stackTrace) {
      debugPrint('>>> [ImageStorage] ❌ Erro ao carregar imagens: $e');
      debugPrint('>>> [ImageStorage] StackTrace: $stackTrace');
      return <String, dynamic>{};
    }
  }

  /// Obtém uma imagem (tenta Firebase primeiro, fallback para localStorage)
  static Future<String?> obterImagem(String imagemId) async {
    try {
      // TENTAR OBTER DO FIREBASE PRIMEIRO
      if (_firestoreDisponivel) {
        try {
          final doc = await _firestoreInstance!
              .collection(_collection)
              .doc(imagemId)
              .get()
              .timeout(const Duration(seconds: 5));

          if (doc.exists) {
            final data = doc.data() ?? <String, dynamic>{};
            final base64 = data['base64'] as String?;
            if (base64 != null && base64.isNotEmpty) {
              debugPrint('>>> [ImageStorage] ✅ Imagem obtida do Firebase: $imagemId');
              return 'data:image/jpeg;base64,$base64';
            }
          }
        } catch (e) {
          debugPrint('>>> [ImageStorage] ⚠️ Erro ao obter do Firebase: $e');
          debugPrint('>>> [ImageStorage] Tentando localStorage...');
        }
      }

      // FALLBACK: OBTER DO LOCALSTORAGE
      try {
        final todasImagens = await _carregarTodasImagens();
        final dados = todasImagens[imagemId] as Map<String, dynamic>?;
        
        if (dados != null) {
          final base64 = dados['base64'] as String?;
          if (base64 != null && base64.isNotEmpty) {
            debugPrint('>>> [ImageStorage] ✅ Imagem obtida do localStorage: $imagemId');
            return 'data:image/jpeg;base64,$base64';
          }
        }
      } catch (e) {
        debugPrint('>>> [ImageStorage] ⚠️ Erro ao obter do localStorage: $e');
      }

      debugPrint('>>> [ImageStorage] ❌ Imagem não encontrada: $imagemId');
      return null;
    } catch (e) {
      debugPrint('>>> [ImageStorage] ❌ ERRO ao obter imagem: $e');
      return null;
    }
  }

  /// Salva uma imagem e retorna a URL direta
  static Future<String?> salvarImagemERetornarUrl({
    required Uint8List imageBytes,
    required String empresaId,
    required String categoria,
    String? nome,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      debugPrint('>>> [ImageStorage] ========================================');
      debugPrint('>>> [ImageStorage] SALVAR E RETORNAR URL');
      debugPrint('>>> [ImageStorage] Empresa ID: $empresaId');
      debugPrint('>>> [ImageStorage] Categoria: $categoria');
      debugPrint('>>> [ImageStorage] ========================================');
      
      final imagemId = await salvarImagem(
        imageBytes: imageBytes,
        empresaId: empresaId,
        categoria: categoria,
        nome: nome,
        metadata: metadata,
      );
      
      debugPrint('>>> [ImageStorage] Imagem salva com ID: $imagemId');
      debugPrint('>>> [ImageStorage] Obtendo imagem para retornar URL...');
      
      // Aguardar um pouco para garantir que foi salvo
      await Future.delayed(const Duration(milliseconds: 200));
      
      final url = await obterImagem(imagemId);
      
      if (url == null || url.isEmpty) {
        debugPrint('>>> [ImageStorage] ❌ ERRO: URL retornada é null ou vazia!');
        debugPrint('>>> [ImageStorage] Imagem ID: $imagemId');
        
        // Tentar obter novamente do localStorage diretamente
        final todasImagens = await _carregarTodasImagens();
        debugPrint('>>> [ImageStorage] Total de imagens no localStorage: ${todasImagens.length}');
        debugPrint('>>> [ImageStorage] Imagem existe no localStorage? ${todasImagens.containsKey(imagemId)}');
        
        if (todasImagens.containsKey(imagemId)) {
          final dados = todasImagens[imagemId] as Map<String, dynamic>?;
          final base64 = dados?['base64'] as String?;
          if (base64 != null && base64.isNotEmpty) {
            debugPrint('>>> [ImageStorage] ✅ Base64 encontrado diretamente, criando URL...');
            return 'data:image/jpeg;base64,$base64';
          } else {
            debugPrint('>>> [ImageStorage] ❌ Base64 está vazio nos dados salvos');
          }
        } else {
          debugPrint('>>> [ImageStorage] ❌ Imagem não encontrada no localStorage após salvar!');
        }
        
        throw Exception('Não foi possível obter a URL da imagem após salvar. ID: $imagemId');
      }
      
      debugPrint('>>> [ImageStorage] ✅ URL obtida com sucesso!');
      debugPrint('>>> [ImageStorage] Tamanho da URL: ${url.length} caracteres');
      debugPrint('>>> [ImageStorage] ========================================');
      
      return url;
    } catch (e, stackTrace) {
      debugPrint('>>> [ImageStorage] ❌ ERRO ao salvar e obter URL: $e');
      debugPrint('>>> [ImageStorage] StackTrace: $stackTrace');
      return null;
    }
  }

  /// Converte e comprime uma imagem para base64
  static Future<String> _comprimirEConverterParaBase64(Uint8List imageBytes) async {
    try {
      debugPrint('>>> [ImageStorage] Iniciando compressão...');
      debugPrint('>>> [ImageStorage] Tamanho original: ${(imageBytes.length / 1024).toStringAsFixed(2)} KB');
      
      // Se a imagem já é pequena, converter direto
      if (imageBytes.length <= _maxSizeBytes) {
        debugPrint('>>> [ImageStorage] Imagem já é pequena, convertendo direto');
        return base64Encode(imageBytes);
      }
      
      // Tentar decodificar e comprimir
      try {
        img.Image? image = img.decodeImage(imageBytes);
        if (image == null) {
          debugPrint('>>> [ImageStorage] ⚠️ Não foi possível decodificar');
          if (imageBytes.length <= 900 * 1024) {
            return base64Encode(imageBytes);
          }
          throw Exception('Imagem muito grande e não foi possível comprimir');
        }

        debugPrint('>>> [ImageStorage] Imagem decodificada: ${image.width}x${image.height}');

        // Redimensionar se necessário (mantendo proporção e usando interpolação de alta qualidade)
        int larguraFinal = image.width;
        int alturaFinal = image.height;
        
        if (image.width > _maxWidth || image.height > _maxHeight) {
          // Calcular novo tamanho mantendo proporção
          double ratio = (image.width / image.height).clamp(0.1, 10.0);
          
          if (image.width > _maxWidth) {
            larguraFinal = _maxWidth;
            alturaFinal = (larguraFinal / ratio).round();
          }
          
          if (alturaFinal > _maxHeight) {
            alturaFinal = _maxHeight;
            larguraFinal = (alturaFinal * ratio).round();
          }
          
          // Usar interpolação cúbica para melhor qualidade no redimensionamento
          image = img.copyResize(
            image,
            width: larguraFinal,
            height: alturaFinal,
            interpolation: img.Interpolation.cubic, // Melhor qualidade
          );
          debugPrint('>>> [ImageStorage] ✅ Imagem redimensionada com alta qualidade: ${image.width}x${image.height}');
        }

        // Aplicar sharpening (nitidez) para melhorar qualidade visual
        // Usando kernel de sharpening padrão (3x3)
        final sharpenKernel = [0, -1, 0, -1, 5, -1, 0, -1, 0];
        image = img.convolution(image, filter: sharpenKernel);
        debugPrint('>>> [ImageStorage] ✅ Nitidez aplicada para melhor qualidade');

        // Comprimir como JPEG com qualidade otimizada
        Uint8List compressedBytes = Uint8List.fromList(
          img.encodeJpg(image, quality: _quality),
        );

        debugPrint('>>> [ImageStorage] Primeira compressão: ${(compressedBytes.length / 1024).toStringAsFixed(2)} KB');

        // Reduzir qualidade gradualmente se necessário (mantendo qualidade visual)
        int qualidadeAtual = _quality;
        int tentativas = 0;
        while (compressedBytes.length > _maxSizeBytes && qualidadeAtual > 30 && tentativas < 10) {
          qualidadeAtual -= 5; // Reduzir em 5% por vez para manter qualidade
          tentativas++;
          
          compressedBytes = Uint8List.fromList(
            img.encodeJpg(image, quality: qualidadeAtual),
          );
          debugPrint('>>> [ImageStorage] Reduzindo qualidade para $qualidadeAtual%: ${(compressedBytes.length / 1024).toStringAsFixed(2)} KB');
        }

        // Converter para base64
        final base64String = base64Encode(compressedBytes);
        debugPrint('>>> [ImageStorage] ✅ Imagem comprimida: ${(compressedBytes.length / 1024).toStringAsFixed(2)} KB');

        return base64String;
      } catch (e) {
        debugPrint('>>> [ImageStorage] ⚠️ Erro ao comprimir: $e');
        if (imageBytes.length <= 900 * 1024) {
          return base64Encode(imageBytes);
        }
        throw Exception('Imagem muito grande (${(imageBytes.length / 1024).toStringAsFixed(2)} KB): $e');
      }
    } catch (e, stackTrace) {
      debugPrint('>>> [ImageStorage] ❌ ERRO CRÍTICO ao comprimir: $e');
      debugPrint('>>> [ImageStorage] StackTrace: $stackTrace');
      rethrow;
    }
  }

  /// Lista todas as imagens de uma empresa (combina Firebase + localStorage)
  static Future<List<Map<String, dynamic>>> listarImagens({
    required String empresaId,
    String? categoria,
  }) async {
    final todasImagens = <String, Map<String, dynamic>>{};

    // CARREGAR DO FIREBASE
    if (_firestoreDisponivel) {
      try {
        Query query = _firestoreInstance!
            .collection(_collection)
            .where('empresaId', isEqualTo: empresaId);

        if (categoria != null && categoria.isNotEmpty) {
          query = query.where('categoria', isEqualTo: categoria);
        }

        final snapshot = await query
            .orderBy('dataUpload', descending: true)
            .get()
            .timeout(const Duration(seconds: 5));

        for (var doc in snapshot.docs) {
          final data = doc.data() as Map<String, dynamic>? ?? {};
          final id = doc.id;
          todasImagens[id] = {
            'id': id,
            'categoria': data['categoria'] as String? ?? '',
            'nome': data['nome'] as String? ?? '',
            'tamanhoBytes': data['tamanhoBytes'] as int? ?? 0,
            'tamanhoOriginalBytes': data['tamanhoOriginalBytes'] as int? ?? 0,
            'dataUpload': (data['dataUpload'] as Timestamp?)?.toDate(),
            'metadata': data['metadata'] as Map<String, dynamic>? ?? {},
            'fonte': 'firebase',
          };
        }
        debugPrint('>>> [ImageStorage] ${snapshot.docs.length} imagens carregadas do Firebase');
      } catch (e) {
        debugPrint('>>> [ImageStorage] ⚠️ Erro ao listar do Firebase: $e');
      }
    }

    // CARREGAR DO LOCALSTORAGE (complementar)
    try {
      final imagensLocais = await _carregarTodasImagens();
      for (var entry in imagensLocais.entries) {
        final dados = entry.value as Map<String, dynamic>? ?? {};
        final id = entry.key;
        final dadosEmpresaId = dados['empresaId'] as String?;
        
        // Filtrar por empresa e categoria
        if (dadosEmpresaId == empresaId) {
          final dadosCategoria = dados['categoria'] as String? ?? '';
          if (categoria == null || categoria.isEmpty || dadosCategoria == categoria) {
            // Só adicionar se não estiver no Firebase (evitar duplicatas)
            if (!todasImagens.containsKey(id)) {
              final dataUploadStr = dados['dataUpload'] as String?;
              todasImagens[id] = {
                'id': id,
                'categoria': dadosCategoria,
                'nome': dados['nome'] as String? ?? '',
                'tamanhoBytes': dados['tamanhoBytes'] as int? ?? 0,
                'tamanhoOriginalBytes': dados['tamanhoOriginalBytes'] as int? ?? 0,
                'dataUpload': dataUploadStr != null ? DateTime.tryParse(dataUploadStr) : null,
                'metadata': dados['metadata'] as Map<String, dynamic>? ?? {},
                'fonte': 'localStorage',
              };
            }
          }
        }
      }
      debugPrint('>>> [ImageStorage] ${imagensLocais.length} imagens verificadas no localStorage');
    } catch (e) {
      debugPrint('>>> [ImageStorage] ⚠️ Erro ao listar do localStorage: $e');
    }

    // Ordenar por data (mais recente primeiro)
    final lista = todasImagens.values.toList();
    lista.sort((a, b) {
      final dataA = a['dataUpload'] as DateTime?;
      final dataB = b['dataUpload'] as DateTime?;
      if (dataA == null && dataB == null) return 0;
      if (dataA == null) return 1;
      if (dataB == null) return -1;
      return dataB.compareTo(dataA);
    });

    debugPrint('>>> [ImageStorage] ✅ Total de ${lista.length} imagens listadas');
    return lista;
  }

  /// Deleta uma imagem (do Firebase e localStorage)
  static Future<bool> deletarImagem(String imagemId) async {
    bool deletado = false;

    // DELETAR DO FIREBASE
    if (_firestoreDisponivel) {
      try {
        await _firestoreInstance!
            .collection(_collection)
            .doc(imagemId)
            .delete()
            .timeout(const Duration(seconds: 5));
        debugPrint('>>> [ImageStorage] ✅ Imagem deletada do Firebase: $imagemId');
        deletado = true;
      } catch (e) {
        debugPrint('>>> [ImageStorage] ⚠️ Erro ao deletar do Firebase: $e');
      }
    }

    // DELETAR DO LOCALSTORAGE
    try {
      final todasImagens = await _carregarTodasImagens();
      if (todasImagens.containsKey(imagemId)) {
        todasImagens.remove(imagemId);
        await _localStorage.salvar(_localStorageKey, todasImagens);
        debugPrint('>>> [ImageStorage] ✅ Imagem deletada do localStorage: $imagemId');
        deletado = true;
      }
    } catch (e) {
      debugPrint('>>> [ImageStorage] ⚠️ Erro ao deletar do localStorage: $e');
    }

    return deletado;
  }

  /// Calcula o tamanho total das imagens (Firebase + localStorage)
  static Future<int> calcularTamanhoTotal(String empresaId) async {
    int total = 0;
    final imagensProcessadas = <String>{};

    // CALCULAR DO FIREBASE
    if (_firestoreDisponivel) {
      try {
        final snapshot = await _firestoreInstance!
            .collection(_collection)
            .where('empresaId', isEqualTo: empresaId)
            .get()
            .timeout(const Duration(seconds: 5));

        for (var doc in snapshot.docs) {
          final data = doc.data() as Map<String, dynamic>? ?? {};
          final id = doc.id;
          if (!imagensProcessadas.contains(id)) {
            imagensProcessadas.add(id);
            total += data['tamanhoBytes'] as int? ?? 0;
          }
        }
      } catch (e) {
        debugPrint('>>> [ImageStorage] ⚠️ Erro ao calcular do Firebase: $e');
      }
    }

    // CALCULAR DO LOCALSTORAGE
    try {
      final todasImagens = await _carregarTodasImagens();
      for (var entry in todasImagens.entries) {
        final id = entry.key;
        final dados = entry.value as Map<String, dynamic>? ?? {};
        if (dados['empresaId'] == empresaId && !imagensProcessadas.contains(id)) {
          imagensProcessadas.add(id);
          total += dados['tamanhoBytes'] as int? ?? 0;
        }
      }
    } catch (e) {
      debugPrint('>>> [ImageStorage] ⚠️ Erro ao calcular do localStorage: $e');
    }

    return total;
  }

  /// Obtém estatísticas de uso (Firebase + localStorage)
  static Future<Map<String, dynamic>> obterEstatisticas(String empresaId) async {
    final imagensProcessadas = <String>{};
    int totalImagens = 0;
    int tamanhoTotal = 0;
    Map<String, int> porCategoria = {};

    // ESTATÍSTICAS DO FIREBASE
    if (_firestoreDisponivel) {
      try {
        final snapshot = await _firestoreInstance!
            .collection(_collection)
            .where('empresaId', isEqualTo: empresaId)
            .get()
            .timeout(const Duration(seconds: 5));

        for (var doc in snapshot.docs) {
          final data = doc.data() as Map<String, dynamic>? ?? {};
          final id = doc.id;
          final tamanho = data['tamanhoBytes'] as int? ?? 0;
          final categoria = data['categoria'] as String? ?? 'outros';
          
          if (!imagensProcessadas.contains(id)) {
            imagensProcessadas.add(id);
            totalImagens++;
            tamanhoTotal += tamanho;
            porCategoria[categoria] = (porCategoria[categoria] ?? 0) + 1;
          }
        }
      } catch (e) {
        debugPrint('>>> [ImageStorage] ⚠️ Erro ao obter estatísticas do Firebase: $e');
      }
    }

    // ESTATÍSTICAS DO LOCALSTORAGE
    try {
      final todasImagens = await _carregarTodasImagens();
      for (var entry in todasImagens.entries) {
        final id = entry.key;
        final dados = entry.value as Map<String, dynamic>? ?? {};
        if (dados['empresaId'] == empresaId && !imagensProcessadas.contains(id)) {
          imagensProcessadas.add(id);
          totalImagens++;
          final tamanho = dados['tamanhoBytes'] as int? ?? 0;
          final categoria = dados['categoria'] as String? ?? 'outros';
          tamanhoTotal += tamanho;
          porCategoria[categoria] = (porCategoria[categoria] ?? 0) + 1;
        }
      }
    } catch (e) {
      debugPrint('>>> [ImageStorage] ⚠️ Erro ao obter estatísticas do localStorage: $e');
    }

    return {
      'totalImagens': totalImagens,
      'tamanhoTotalBytes': tamanhoTotal,
      'tamanhoTotalMB': (tamanhoTotal / (1024 * 1024)).toStringAsFixed(2),
      'porCategoria': porCategoria,
    };
  }
}
