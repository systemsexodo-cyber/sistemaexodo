import 'dart:io';
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:firebase_storage/firebase_storage.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;

/// Serviço genérico para upload de imagens para o Firebase Storage
class ImageUploadService {
  /// Faz upload de uma imagem para o Firebase Storage
  /// 
  /// [localPath] - Caminho local do arquivo ou blob URL (web)
  /// [storagePath] - Caminho no Firebase Storage (ex: 'pets/empresa123/cliente456/foto.jpg')
  /// [onProgress] - Callback opcional para monitorar progresso (0.0 a 1.0)
  /// [metadata] - Metadados customizados opcionais
  /// 
  /// Retorna a URL de download da imagem ou null se falhar
  static Future<String?> uploadImage({
    required String localPath,
    required String storagePath,
    Function(double)? onProgress,
    Map<String, String>? metadata,
  }) async {
    try {
      debugPrint('>>> [ImageUpload] ========================================');
      debugPrint('>>> [ImageUpload] INICIANDO UPLOAD DE IMAGEM');
      debugPrint('>>> [ImageUpload] Caminho local: $localPath');
      debugPrint('>>> [ImageUpload] Caminho storage: $storagePath');
      debugPrint('>>> [ImageUpload] ========================================');

      // Se já é uma URL HTTPS do Firebase, retornar como está
      if (localPath.startsWith('https://')) {
        debugPrint('>>> [ImageUpload] Já é URL do Firebase, retornando: $localPath');
        return localPath;
      }

      if (localPath.isEmpty) {
        debugPrint('>>> [ImageUpload] Caminho vazio');
        return null;
      }

      // Verificar se Firebase Storage está disponível
      FirebaseStorage storage;
      try {
        storage = FirebaseStorage.instance;
        debugPrint('>>> [ImageUpload] ✅ Firebase Storage inicializado');
        debugPrint('>>> [ImageUpload] Storage bucket: ${storage.app.options.storageBucket}');
      } catch (e, stackTrace) {
        debugPrint('>>> [ImageUpload] ❌ ERRO CRÍTICO: Firebase Storage não está disponível');
        debugPrint('>>> [ImageUpload] Erro: $e');
        debugPrint('>>> [ImageUpload] StackTrace: $stackTrace');
        throw Exception('Firebase Storage não está inicializado. Verifique se o Firebase foi inicializado corretamente. Erro: $e');
      }
      Uint8List imageBytes;
      String contentType = 'image/jpeg';
      String extension = '.jpg';

      // Processar imagem baseado na plataforma
      if (kIsWeb && localPath.startsWith('blob:')) {
        // Web: converter blob URL para bytes
        // IMPORTANTE: Blob URLs podem expirar rapidamente no Chrome, então precisamos converter imediatamente
        debugPrint('>>> [ImageUpload] Web: Convertendo blob URL para bytes...');
        debugPrint('>>> [ImageUpload] ⚠️ ATENÇÃO: Blob URLs expiram rapidamente no Chrome!');
        try {
          // Converter blob URL para bytes IMEDIATAMENTE antes que expire
          final response = await http.get(
            Uri.parse(localPath),
            headers: {
              'Cache-Control': 'no-cache',
            },
          ).timeout(
            const Duration(seconds: 5), // Timeout menor para blob URLs
            onTimeout: () {
              debugPrint('>>> [ImageUpload] ⚠️ Timeout ao carregar blob URL - pode ter expirado');
              throw TimeoutException('Timeout ao carregar blob URL (pode ter expirado)');
            },
          );
          
          if (response.statusCode != 200) {
            debugPrint('>>> [ImageUpload] ❌ Falha ao carregar blob URL: Status ${response.statusCode}');
            throw Exception('Falha ao carregar blob URL: ${response.statusCode}');
          }

          imageBytes = response.bodyBytes;
          debugPrint('>>> [ImageUpload] ✅ Blob convertido: ${(imageBytes.length / 1024).toStringAsFixed(2)} KB');
          
          // Verificar se os bytes não estão vazios
          if (imageBytes.isEmpty) {
            throw Exception('Blob URL retornou bytes vazios');
          }

          // Detectar tipo pelo content-type
          final contentTypeHeader = response.headers['content-type'] ?? 'image/jpeg';
          if (contentTypeHeader.contains('png')) {
            extension = '.png';
            contentType = 'image/png';
          } else if (contentTypeHeader.contains('gif')) {
            extension = '.gif';
            contentType = 'image/gif';
          } else if (contentTypeHeader.contains('webp')) {
            extension = '.webp';
            contentType = 'image/webp';
          }
        } catch (e) {
          debugPrint('>>> [ImageUpload] Erro ao converter blob URL: $e');
          return null;
        }
      } else if (!kIsWeb) {
        // Mobile/Desktop: ler arquivo local
        final file = File(localPath);
        if (!await file.exists()) {
          debugPrint('>>> [ImageUpload] Arquivo não existe: $localPath');
          return null;
        }

        debugPrint('>>> [ImageUpload] Lendo arquivo local...');
        imageBytes = await file.readAsBytes().timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            throw TimeoutException('Timeout ao ler arquivo');
          },
        );
        debugPrint('>>> [ImageUpload] Arquivo lido: ${(imageBytes.length / 1024).toStringAsFixed(2)} KB');

        // Detectar extensão e content type
        extension = path.extension(localPath).toLowerCase();
        if (extension.isEmpty || extension == '.') {
          extension = '.jpg';
        }

        if (extension == '.png') {
          contentType = 'image/png';
        } else if (extension == '.gif') {
          contentType = 'image/gif';
        } else if (extension == '.webp') {
          contentType = 'image/webp';
        }
      } else {
        debugPrint('>>> [ImageUpload] Web não suporta upload de arquivos locais');
        return null;
      }

      if (imageBytes.isEmpty) {
        debugPrint('>>> [ImageUpload] Bytes da imagem vazios');
        return null;
      }

      // Garantir que o caminho no storage tenha a extensão correta
      String finalStoragePath = storagePath;
      if (!finalStoragePath.toLowerCase().endsWith(extension.toLowerCase())) {
        finalStoragePath = '$storagePath$extension';
      }

      debugPrint('>>> [ImageUpload] Tamanho: ${(imageBytes.length / 1024).toStringAsFixed(2)} KB');
      debugPrint('>>> [ImageUpload] Content-Type: $contentType');
      debugPrint('>>> [ImageUpload] Caminho final: $finalStoragePath');

      // Criar referência no Firebase Storage
      final ref = storage.ref().child(finalStoragePath);

      // Preparar metadados
      final uploadMetadata = SettableMetadata(
        contentType: contentType,
        customMetadata: metadata ?? {},
      );

      // Criar upload task
      debugPrint('>>> [ImageUpload] Criando upload task...');
      UploadTask uploadTask;
      try {
        uploadTask = ref.putData(imageBytes, uploadMetadata);
        debugPrint('>>> [ImageUpload] ✅ Upload task criado com sucesso');
      } catch (e, stackTrace) {
        debugPrint('>>> [ImageUpload] ❌ ERRO ao criar upload task: $e');
        debugPrint('>>> [ImageUpload] StackTrace: $stackTrace');
        throw Exception('Erro ao criar upload task: $e');
      }

      // Verificar estado inicial
      debugPrint('>>> [ImageUpload] Estado inicial: ${uploadTask.snapshot.state}');
      debugPrint('>>> [ImageUpload] Bytes: ${uploadTask.snapshot.bytesTransferred}/${uploadTask.snapshot.totalBytes}');
      
      // Verificar se o upload task foi criado corretamente
      if (uploadTask.snapshot.state == TaskState.error) {
        debugPrint('>>> [ImageUpload] ❌ Upload task criado com estado de erro');
        throw Exception('Upload task criado com estado de erro');
      }

      // Configurar listener de progresso
      StreamSubscription? progressSubscription;
      if (onProgress != null) {
        progressSubscription = uploadTask.snapshotEvents.listen(
          (snapshot) {
            final state = snapshot.state;
            final bytesTransferred = snapshot.bytesTransferred;
            final totalBytes = snapshot.totalBytes;

            debugPrint('>>> [ImageUpload] 📊 Estado: $state, Bytes: $bytesTransferred/$totalBytes');

            if (totalBytes > 0) {
              final progress = bytesTransferred / totalBytes;
              onProgress(progress);
              debugPrint('>>> [ImageUpload] Progresso: ${(progress * 100).toStringAsFixed(1)}%');
            } else if (bytesTransferred > 0) {
              onProgress(0.1);
            } else {
              onProgress(0.0);
            }

            if (state == TaskState.error) {
              debugPrint('>>> [ImageUpload] ❌ ERRO detectado!');
            } else if (state == TaskState.success) {
              debugPrint('>>> [ImageUpload] ✅ Upload concluído!');
            }
          },
          onError: (error) {
            debugPrint('>>> [ImageUpload] ❌ Erro no stream: $error');
            onProgress(0.0);
          },
          cancelOnError: false,
        );
      }

      // Aguardar conclusão do upload com timeout reduzido e verificação periódica
      debugPrint('>>> [ImageUpload] Aguardando conclusão (timeout: 60s)...');
      TaskSnapshot snapshot;
      try {
        // Verificar periodicamente se o upload está travado
        Timer? verificacaoTimer;
        
        verificacaoTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
          final estado = uploadTask.snapshot.state;
          final bytesTransferred = uploadTask.snapshot.bytesTransferred;
          final totalBytes = uploadTask.snapshot.totalBytes;
          
          debugPrint('>>> [ImageUpload] Verificação periódica - Estado: $estado, Bytes: $bytesTransferred/$totalBytes');
          
          if (estado == TaskState.success) {
            timer.cancel();
          } else if (estado == TaskState.error) {
            debugPrint('>>> [ImageUpload] ❌ Erro detectado na verificação periódica');
            timer.cancel();
          } else if (estado == TaskState.paused) {
            debugPrint('>>> [ImageUpload] ⚠️ Upload pausado - tentando retomar...');
            try {
              uploadTask.resume();
            } catch (e) {
              debugPrint('>>> [ImageUpload] Erro ao retomar: $e');
            }
          }
        });
        
        snapshot = await uploadTask.timeout(
          const Duration(seconds: 60), // Timeout reduzido para 60 segundos
          onTimeout: () {
            final estadoAtual = uploadTask.snapshot.state;
            final bytesAtual = uploadTask.snapshot.bytesTransferred;
            final totalAtual = uploadTask.snapshot.totalBytes;
            debugPrint('>>> [ImageUpload] ⚠️ TIMEOUT após 60 segundos');
            debugPrint('>>> [ImageUpload] Estado: $estadoAtual, Bytes: $bytesAtual/$totalAtual');
            verificacaoTimer?.cancel();
            progressSubscription?.cancel();
            try {
              uploadTask.cancel();
              debugPrint('>>> [ImageUpload] Upload cancelado');
            } catch (e) {
              debugPrint('>>> [ImageUpload] Erro ao cancelar: $e');
            }
            throw TimeoutException('Upload timeout após 60 segundos. Verifique sua conexão com a internet.');
          },
        );
        
        verificacaoTimer.cancel();
        debugPrint('>>> [ImageUpload] ✅ Upload concluído com sucesso!');
      } catch (e, stackTrace) {
        debugPrint('>>> [ImageUpload] ❌ Erro durante upload: $e');
        debugPrint('>>> [ImageUpload] StackTrace: $stackTrace');
        progressSubscription?.cancel();
        rethrow;
      } finally {
        progressSubscription?.cancel();
      }

      // Obter URL de download com retry
      debugPrint('>>> [ImageUpload] Obtendo URL de download...');
      if (onProgress != null) onProgress(1.0);

      String downloadUrl = '';
      int tentativas = 0;
      const maxTentativas = 3;

      while (tentativas < maxTentativas) {
        try {
          downloadUrl = await snapshot.ref.getDownloadURL().timeout(
            const Duration(seconds: 30),
            onTimeout: () {
              throw TimeoutException('Timeout ao obter URL');
            },
          );
          debugPrint('>>> [ImageUpload] ✅ URL obtida na tentativa ${tentativas + 1}');
          break;
        } catch (e) {
          tentativas++;
          if (tentativas >= maxTentativas) {
            debugPrint('>>> [ImageUpload] ❌ Falha após $maxTentativas tentativas: $e');
            rethrow;
          }
          debugPrint('>>> [ImageUpload] ⚠️ Tentativa $tentativas falhou, tentando novamente...');
          await Future.delayed(const Duration(seconds: 1));
        }
      }

      if (downloadUrl.isEmpty) {
        throw Exception('Não foi possível obter URL após $maxTentativas tentativas');
      }

      // Verificar se a URL é válida e acessível
      debugPrint('>>> [ImageUpload] Verificando se URL é acessível...');
      try {
        final testResponse = await http.head(Uri.parse(downloadUrl)).timeout(
          const Duration(seconds: 10),
        );
        if (testResponse.statusCode == 200) {
          debugPrint('>>> [ImageUpload] ✅ URL verificada e acessível (Status: ${testResponse.statusCode})');
        } else {
          debugPrint('>>> [ImageUpload] ⚠️ URL retornou status: ${testResponse.statusCode}');
        }
      } catch (e) {
        debugPrint('>>> [ImageUpload] ⚠️ Não foi possível verificar URL: $e');
        // Continuar mesmo assim, pode ser problema de CORS ou rede
      }

      debugPrint('>>> [ImageUpload] ✅ Upload finalizado com sucesso!');
      debugPrint('>>> [ImageUpload] URL final: $downloadUrl');
      debugPrint('>>> [ImageUpload] ========================================');
      return downloadUrl;
    } catch (e, stackTrace) {
      debugPrint('>>> [ImageUpload] ❌❌❌ ERRO CRÍTICO AO FAZER UPLOAD ❌❌❌');
      debugPrint('>>> [ImageUpload] Erro: $e');
      debugPrint('>>> [ImageUpload] Tipo do erro: ${e.runtimeType}');
      debugPrint('>>> [ImageUpload] StackTrace: $stackTrace');
      debugPrint('>>> [ImageUpload] ========================================');
      
      // Re-throw para que o erro seja tratado no nível superior
      // Isso permite que o código que chama o upload saiba exatamente qual foi o problema
      rethrow;
    }
  }

  /// Faz upload de uma imagem usando bytes diretamente
  /// 
  /// [imageBytes] - Bytes da imagem
  /// [storagePath] - Caminho no Firebase Storage
  /// [contentType] - Tipo MIME da imagem (ex: 'image/jpeg', 'image/png')
  /// [onProgress] - Callback opcional para monitorar progresso
  /// [metadata] - Metadados customizados opcionais
  /// 
  /// Retorna a URL de download da imagem ou null se falhar
  static Future<String?> uploadImageFromBytes({
    required Uint8List imageBytes,
    required String storagePath,
    String contentType = 'image/jpeg',
    Function(double)? onProgress,
    Map<String, String>? metadata,
  }) async {
    try {
      debugPrint('>>> [ImageUpload] Upload de bytes: ${(imageBytes.length / 1024).toStringAsFixed(2)} KB');

      if (imageBytes.isEmpty) {
        debugPrint('>>> [ImageUpload] ❌ Bytes vazios');
        throw Exception('Bytes da imagem estão vazios');
      }

      // Verificar se Firebase Storage está disponível
      FirebaseStorage storage;
      try {
        storage = FirebaseStorage.instance;
        debugPrint('>>> [ImageUpload] ✅ Firebase Storage inicializado');
        debugPrint('>>> [ImageUpload] Storage bucket: ${storage.app.options.storageBucket}');
      } catch (e, stackTrace) {
        debugPrint('>>> [ImageUpload] ❌ ERRO CRÍTICO: Firebase Storage não está disponível');
        debugPrint('>>> [ImageUpload] Erro: $e');
        debugPrint('>>> [ImageUpload] StackTrace: $stackTrace');
        throw Exception('Firebase Storage não está inicializado. Verifique se o Firebase foi inicializado corretamente. Erro: $e');
      }

      final ref = storage.ref().child(storagePath);
      debugPrint('>>> [ImageUpload] Referência criada: $storagePath');

      final uploadMetadata = SettableMetadata(
        contentType: contentType,
        customMetadata: metadata ?? {},
      );

      // Criar upload task
      debugPrint('>>> [ImageUpload] Criando upload task...');
      UploadTask uploadTask;
      try {
        uploadTask = ref.putData(imageBytes, uploadMetadata);
        debugPrint('>>> [ImageUpload] ✅ Upload task criado com sucesso');
      } catch (e, stackTrace) {
        debugPrint('>>> [ImageUpload] ❌ ERRO ao criar upload task: $e');
        debugPrint('>>> [ImageUpload] StackTrace: $stackTrace');
        throw Exception('Erro ao criar upload task: $e');
      }

      // Verificar estado inicial
      debugPrint('>>> [ImageUpload] Estado inicial: ${uploadTask.snapshot.state}');
      debugPrint('>>> [ImageUpload] Bytes: ${uploadTask.snapshot.bytesTransferred}/${uploadTask.snapshot.totalBytes}');
      
      // Verificar se o upload task foi criado corretamente
      if (uploadTask.snapshot.state == TaskState.error) {
        debugPrint('>>> [ImageUpload] ❌ Upload task criado com estado de erro');
        throw Exception('Upload task criado com estado de erro');
      }

      // Listener de progresso
      StreamSubscription? progressSubscription;
      if (onProgress != null) {
        progressSubscription = uploadTask.snapshotEvents.listen(
          (snapshot) {
            if (snapshot.totalBytes > 0) {
              final progress = snapshot.bytesTransferred / snapshot.totalBytes;
              onProgress(progress);
            }
          },
          onError: (error) {
            debugPrint('>>> [ImageUpload] Erro no stream: $error');
            onProgress(0.0);
          },
        );
      }

      // Aguardar upload com timeout e verificação periódica
      debugPrint('>>> [ImageUpload] Aguardando upload (timeout: 30s)...');
      
      // Verificar periodicamente se o upload está travado
      Timer? verificacaoTimer;
      int tentativasSemProgresso = 0;
      int ultimoBytesTransferred = 0;
      bool uploadTravado = false;
      
      verificacaoTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
        if (uploadTravado) {
          timer.cancel();
          return;
        }
        
        final estado = uploadTask.snapshot.state;
        final bytesTransferred = uploadTask.snapshot.bytesTransferred;
        final totalBytes = uploadTask.snapshot.totalBytes;
        
        // Verificar se houve progresso
        if (bytesTransferred == ultimoBytesTransferred && estado == TaskState.running && totalBytes > 0) {
          tentativasSemProgresso++;
          if (tentativasSemProgresso >= 5) {
            debugPrint('>>> [ImageUpload] ⚠️ Upload travado - sem progresso há ${tentativasSemProgresso * 2} segundos');
            debugPrint('>>> [ImageUpload] Cancelando upload travado...');
            uploadTravado = true;
            timer.cancel();
            try {
              uploadTask.cancel();
            } catch (e) {
              debugPrint('>>> [ImageUpload] Erro ao cancelar: $e');
            }
            return;
          }
        } else if (bytesTransferred > ultimoBytesTransferred) {
          tentativasSemProgresso = 0;
          ultimoBytesTransferred = bytesTransferred;
        }
        
        // Log apenas a cada 4 segundos para não poluir o console
        if (tentativasSemProgresso % 2 == 0) {
          debugPrint('>>> [ImageUpload] Estado: $estado, Bytes: $bytesTransferred/$totalBytes');
        }
        
        if (estado == TaskState.success) {
          timer.cancel();
        } else if (estado == TaskState.error) {
          debugPrint('>>> [ImageUpload] ❌ Erro detectado na verificação periódica');
          timer.cancel();
        } else if (estado == TaskState.paused) {
          debugPrint('>>> [ImageUpload] ⚠️ Upload pausado - tentando retomar...');
          try {
            uploadTask.resume();
          } catch (e) {
            debugPrint('>>> [ImageUpload] Erro ao retomar: $e');
          }
        }
      });
      
      // Aguardar o upload com timeout
      TaskSnapshot snapshot;
      try {
        snapshot = await uploadTask.timeout(
          const Duration(seconds: 30),
          onTimeout: () {
            verificacaoTimer?.cancel();
            progressSubscription?.cancel();
            try {
              uploadTask.cancel();
              debugPrint('>>> [ImageUpload] Upload cancelado por timeout');
            } catch (e) {
              debugPrint('>>> [ImageUpload] Erro ao cancelar: $e');
            }
            throw TimeoutException('Upload timeout após 30 segundos. Verifique sua conexão com a internet.');
          },
        );
      } catch (e) {
        verificacaoTimer.cancel();
        progressSubscription?.cancel();
        if (uploadTravado) {
          throw Exception('Upload travado - não houve progresso. Verifique sua conexão e tente novamente.');
        }
        rethrow;
      }
      
      verificacaoTimer.cancel();

      progressSubscription?.cancel();
      if (onProgress != null) onProgress(1.0);

      // Obter URL
      final downloadUrl = await snapshot.ref.getDownloadURL().timeout(
        const Duration(seconds: 30),
      );

      debugPrint('>>> [ImageUpload] ✅ Upload concluído: $downloadUrl');
      debugPrint('>>> [ImageUpload] ========================================');
      return downloadUrl;
    } catch (e, stackTrace) {
      debugPrint('>>> [ImageUpload] ❌❌❌ ERRO CRÍTICO AO FAZER UPLOAD DE BYTES ❌❌❌');
      debugPrint('>>> [ImageUpload] Erro: $e');
      debugPrint('>>> [ImageUpload] Tipo do erro: ${e.runtimeType}');
      debugPrint('>>> [ImageUpload] StackTrace: $stackTrace');
      debugPrint('>>> [ImageUpload] ========================================');
      
      // Re-throw para que o erro seja tratado no nível superior
      rethrow;
    }
  }

  /// Deleta uma imagem do Firebase Storage
  /// 
  /// [storagePath] - Caminho no Firebase Storage
  /// Retorna true se deletado com sucesso, false caso contrário
  static Future<bool> deleteImage(String storagePath) async {
    try {
      debugPrint('>>> [ImageUpload] Deletando: $storagePath');
      final storage = FirebaseStorage.instance;
      final ref = storage.ref().child(storagePath);
      await ref.delete();
      debugPrint('>>> [ImageUpload] ✅ Imagem deletada');
      return true;
    } catch (e) {
      debugPrint('>>> [ImageUpload] ❌ Erro ao deletar: $e');
      return false;
    }
  }
}

