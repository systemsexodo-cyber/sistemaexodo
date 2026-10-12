import 'dart:convert';
import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:supabase_flutter/supabase_flutter.dart'
    show FileOptions, BucketOptions, SearchOptions;
import 'package:sistema_exodo_novo/services/supabase_service.dart';
import 'package:sistema_exodo_novo/services/win32_process_helper.dart';

/// Uma versão publicada na nuvem (uma linha da `bridge_config`).
///
/// `app_latest` vale para TODOS os clientes; `app_update_<empresaId>` vale só
/// para os computadores daquela empresa (é o "atualizar uma empresa").
class PublicacaoVersao {
  final String id;
  final String? empresaId; // null = todos os clientes
  final String versao; // sem o '!' de forçada
  final bool forcada; // publicada com '!' (atualiza mesmo se já for mais nova)
  final String url;
  final DateTime? atualizadoEm;

  const PublicacaoVersao({
    required this.id,
    required this.empresaId,
    required this.versao,
    required this.forcada,
    required this.url,
    this.atualizadoEm,
  });

  bool get global => empresaId == null;

  /// Registro da versão que vale para todos os clientes.
  static const String idGlobal = 'app_latest';

  /// Prefixo dos registros direcionados a uma empresa.
  static const String prefixoEmpresa = 'app_update_';

  /// Converte uma linha da `bridge_config` em publicação.
  ///
  /// Devolve `null` para os ids que não são de atualização do app
  /// (ex: `latest`, `sync_latest`, que são do bridge/sincronizador).
  static PublicacaoVersao? daLinha(Map<String, dynamic> linha) {
    final id = (linha['id'] ?? '').toString();
    if (id != idGlobal && !id.startsWith(prefixoEmpresa)) return null;
    final bruta = (linha['version'] ?? '').toString().trim();
    final forcada = bruta.startsWith('!');
    return PublicacaoVersao(
      id: id,
      empresaId: id == idGlobal ? null : id.substring(prefixoEmpresa.length),
      versao: forcada ? bruta.substring(1) : bruta,
      forcada: forcada,
      url: (linha['download_url'] ?? '').toString(),
      atualizadoEm: _data(linha['updated_at']),
    );
  }

  static DateTime? _data(dynamic valor) {
    if (valor == null) return null;
    if (valor is DateTime) return valor;
    return DateTime.tryParse(valor.toString());
  }
}

/// O pacote `.zip` que sobe para a nuvem e é aplicado nos clientes.
class PacoteAtualizacao {
  final String caminho;
  final int bytes;
  final DateTime modificadoEm;

  /// O que entrou no pacote (ex: `data/app.so`, `sistema_exodo_novo.exe`).
  final List<String> conteudo;

  const PacoteAtualizacao({
    required this.caminho,
    required this.bytes,
    required this.modificadoEm,
    required this.conteudo,
  });

  String get tamanhoLegivel =>
      '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
}

/// Um pacote de versão que JÁ está na nuvem e pode ser reaproveitado.
///
/// É o que permite apontar uma empresa para uma versão que subiu antes (voltar
/// atrás de uma versão com problema, ou repetir a mesma em outra empresa) SEM
/// compilar e SEM enviar arquivo de novo: só o direcionamento na `bridge_config`
/// muda. Cada versão fica num arquivo próprio
/// (`sistema_exodo_novo_<versao>.zip`), então nada é sobrescrito.
class VersaoNaNuvem {
  final String versao;
  final int bytes;
  final DateTime? enviadoEm;

  const VersaoNaNuvem({
    required this.versao,
    this.bytes = 0,
    this.enviadoEm,
  });

  String get tamanhoLegivel => bytes <= 0
      ? 'tamanho não informado'
      : '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';

  /// "22/09 09:12" no horário DESTA máquina (o Storage responde em UTC).
  String get quandoLegivel {
    final quando = enviadoEm?.toLocal();
    if (quando == null) return 'data não informada';
    String dois(int n) => n.toString().padLeft(2, '0');
    return '${dois(quando.day)}/${dois(quando.month)} '
        '${dois(quando.hour)}:${dois(quando.minute)}';
  }

  @override
  String toString() => '$versao • $tamanhoLegivel • $quandoLegivel';
}

class AppUpdateService {
  static const String currentAppVersion = "1.0.53";

  /// Verifica se há uma nova versão do aplicativo no Supabase (Direcionada por Empresa ou Global)
  static Future<Map<String, dynamic>?> verificarAtualizacao({
    String? empresaId,
    Map<String, dynamic>? configsEmpresa,
  }) async {
    if (kIsWeb) return null; // Web não se auto-atualiza via arquivo local
    if (!Platform.isWindows) return null; // Apenas Windows por enquanto

    try {
      // 1. PRIMEIRO: Checar no Supabase se há atualização direcionada para esta empresa
      if (empresaId != null && empresaId.isNotEmpty) {
        final respEmpresa = await SupabaseService.instance.select(
          'bridge_config',
          filters: {'id': 'app_update_$empresaId'},
        ).timeout(const Duration(seconds: 3));

        if (respEmpresa.isNotEmpty) {
          final config = respEmpresa.first;
          final String vRemota = config['version'] ?? '';
          final String downloadUrl = config['download_url'] ?? '';
          final bool ativa = config['ativo'] ?? true;

          if (ativa && vRemota.isNotEmpty && downloadUrl.isNotEmpty) {
            if (_deveAtualizar(currentAppVersion, vRemota)) {
              return {
                'version': _limparVersao(vRemota),
                'download_url': downloadUrl,
                'is_direcionada': true,
              };
            }
          }
        }
      }

      // 2. SEGUNDO: Checar nas configurações da empresa local
      if (configsEmpresa != null && configsEmpresa['atualizacao_ativa'] == true) {
        final String vRemota = configsEmpresa['versao_alvo'] ?? '';
        final String downloadUrl = configsEmpresa['update_download_url'] ?? '';

        if (vRemota.isNotEmpty && downloadUrl.isNotEmpty) {
          if (_deveAtualizar(currentAppVersion, vRemota)) {
            return {
              'version': _limparVersao(vRemota),
              'download_url': downloadUrl,
              'is_direcionada': true,
            };
          }
        }
      }

      // 3. TERCEIRO: Fallback para versão global no Supabase se a empresa permitir atualização global
      final bool bloqueiaAtualizacaoGlobal = configsEmpresa?['bloquear_atualizacao_global'] == true;
      if (!bloqueiaAtualizacaoGlobal) {
        final response = await SupabaseService.instance.select(
          'bridge_config',
          filters: {'id': 'app_latest'},
        ).timeout(const Duration(seconds: 3));

        if (response.isNotEmpty) {
          final config = response.first;
          final String nuverVersion = config['version'] ?? '';
          final String downloadUrl = config['download_url'] ?? '';

          if (nuverVersion.isNotEmpty && downloadUrl.isNotEmpty) {
            if (_deveAtualizar(currentAppVersion, nuverVersion)) {
              return {
                'version': _limparVersao(nuverVersion),
                'download_url': downloadUrl,
                'is_direcionada': false,
              };
            }
          }
        }
      }
    } catch (e) {
      debugPrint('>>> [AppUpdateService] Erro ao verificar atualização: $e');
    }
    return null;
  }

  /// Remove o prefixo de força '!' da versão, se presente
  static String _limparVersao(String v) => v.startsWith('!') ? v.substring(1) : v;

  /// Compara se a versão remota é maior que a versão local
  /// Se a versão remota começar com '!', força a atualização (suporta downgrade)
  static bool _deveAtualizar(String local, String remota) {
    try {
      // Verificar se é atualização forçada (downgrade prefixado com '!')
      final bool isForced = remota.startsWith('!');
      if (isForced) {
        remota = remota.substring(1); // Remove o prefixo '!'
        return true; // Força a atualização independente da versão
      }

      final localParts = local.split('.').map((e) => int.tryParse(e) ?? 0).toList();
      final remotaParts = remota.split('.').map((e) => int.tryParse(e) ?? 0).toList();

      for (int i = 0; i < localParts.length && i < remotaParts.length; i++) {
        if (remotaParts[i] > localParts[i]) return true;
        if (remotaParts[i] < localParts[i]) return false;
      }
      // Se forem iguais nas partes comuns, mas a remota tiver mais segmentos (ex: 1.0.8 vs 1.0.8.1)
      if (remotaParts.length > localParts.length) {
        for (int i = localParts.length; i < remotaParts.length; i++) {
          if (remotaParts[i] > 0) return true;
        }
      }
    } catch (e) {
      debugPrint('>>> [AppUpdateService] Erro na comparação de versão: $e');
    }
    return false;
  }

  /// Comparação de versões, exposta para os testes (`_deveAtualizar`).
  @visibleForTesting
  static bool deveAtualizar(String local, String remota) =>
      _deveAtualizar(local, remota);

  /// Faz o download e aplica a atualização.
  ///
  /// Pacote `.zip` (formato novo): o zip é VALIDADO, extraído para uma pasta de
  /// espera e o script que roda depois do app fechar só copia os arquivos por
  /// cima da instalação (guardando antes uma cópia do que havia) e reabre o
  /// programa.
  ///
  /// `.exe` (formato antigo, ainda aceito): troca só o executável.
  ///
  /// Publicar apenas o executável NÃO atualiza o programa: ele tem ~85 KB e é
  /// igual em todas as versões — o código de verdade fica no `data/app.so`, que
  /// é o que o pacote leva.
  /// Retorna (ok, motivo): quando devolve `ok`, o programa já está sendo
  /// trocado e o app fecha em seguida — só um motivo diferente de vazio chega
  /// ao chamador. Um pacote recusado NUNCA é aplicado por cima da instalação.
  static Future<(bool, String)> baixarEAplicarAtualizacao(
      String downloadUrl, Function(double) onProgress) async {
    try {
      final currentExePath = Platform.resolvedExecutable;
      final exeDir = p.dirname(currentExePath);
      final ehPacote = downloadUrl.toLowerCase().contains('.zip');
      final baixado = p.join(exeDir,
          ehPacote ? 'atualizacao_pendente.zip' : 'sistema_exodo_novo.exe.new');
      final staging = p.join(exeDir, 'atualizacao_pendente');
      final batPath = p.join(exeDir, 'self_update_app.bat');

      debugPrint('>>> [AppUpdateService] Baixando de: $downloadUrl');
      debugPrint('>>> [AppUpdateService] Destino: $baixado');

      // Fazer download em chunks para notificar o progresso
      final client = http.Client();
      final request = http.Request('GET', Uri.parse(downloadUrl));
      final response = await client.send(request);

      if (response.statusCode != 200) {
        throw Exception('Erro HTTP ao baixar arquivo: ${response.statusCode}');
      }

      final contentLength = response.contentLength ?? 0;
      int downloaded = 0;
      final file = File(baixado);
      final sink = file.openWrite();

      await for (final chunk in response.stream) {
        sink.add(chunk);
        downloaded += chunk.length;
        if (contentLength > 0) {
          final progress = downloaded / contentLength;
          onProgress(progress);
        }
      }

      await sink.close();
      client.close();

      final bat = <String>[
        '@echo off',
        'title Atualizando Sistema Exodo',
        'echo Aguardando o aplicativo fechar...',
        'ping -n 3 127.0.0.1 >nul',
        'taskkill /F /IM sistema_exodo_novo.exe >nul 2>&1',
        'ping -n 2 127.0.0.1 >nul',
      ];

      if (ehPacote) {
        // Confere o pacote ANTES de encostar na instalação.
        final (ok, mensagem) = await prepararPacoteBaixado(baixado, staging);
        if (!ok) {
          debugPrint('>>> [AppUpdateService] ⚠️ Atualização recusada: $mensagem');
          try {
            File(baixado).deleteSync();
          } catch (_) {}
          return (false, mensagem);
        }
        debugPrint('>>> [AppUpdateService] ✅ $mensagem');
        bat.addAll([
          // Cópia do que está instalado, para voltar atrás se a nova versão não abrir
          'if not exist "$exeDir\\_backup_atualizacao" mkdir "$exeDir\\_backup_atualizacao"',
          'copy /Y "$exeDir\\data\\app.so" "$exeDir\\_backup_atualizacao\\app.so" >nul 2>&1',
          'copy /Y "$currentExePath" "$exeDir\\_backup_atualizacao\\sistema_exodo_novo.exe" >nul 2>&1',
          'xcopy /Y /E /I "$staging\\*" "$exeDir\\" >nul',
          'rmdir /S /Q "$staging" >nul 2>&1',
          'del "$baixado" >nul 2>&1',
        ]);
      } else {
        bat.add('move /Y "$baixado" "$currentExePath"');
      }

      bat.addAll([
        'echo Iniciando nova versao...',
        'start "" "$currentExePath"',
        'del "%~f0"',
      ]);

      // O BAT precisa de CRLF de verdade — cmd.exe não entende '\n' sozinho.
      await File(batPath).writeAsString('${bat.join('\r\n')}\r\n');

      debugPrint('>>> [AppUpdateService] Executando script de troca e fechando...');
      // Disparar o BAT sem janela CMD
      // (CreateProcessW + CREATE_NO_WINDOW: o app é GUI, então um cmd.exe comum
      // abriria uma janela de console visível)
      final pid = Win32ProcessHelper.startProcessHidden(
        'cmd.exe',
        arguments: ['/c', batPath],
      );
      if (pid == null) {
        debugPrint('>>> [AppUpdateService] ⚠️ Falha ao executar o BAT de atualização');
        return (false,
            'não consegui iniciar o aplicativo que faz a troca dos arquivos');
      }
      // Fechar a si mesmo imediatamente
      exit(0);
    } catch (e) {
      debugPrint('>>> [AppUpdateService] Erro ao aplicar atualização: $e');
      return (false, 'erro ao aplicar a atualização: $e');
    }
  }

  /// Valida o `.zip` baixado e extrai para [stagingDir].
  ///
  /// Recusa pacote que não é zip, que está cortado/incompleto ou que não traz o
  /// `data/app.so` — assim um download pela metade (ou uma página de erro salva
  /// como se fosse o arquivo) nunca é aplicado por cima da instalação.
  /// Retorna (ok, mensagem).
  static Future<(bool, String)> prepararPacoteBaixado(
      String zipPath, String stagingDir) async {
    try {
      final bytes = await File(zipPath).readAsBytes();
      if (bytes.length < 1024 * 1024) {
        return (false,
            'pacote baixado tem só ${(bytes.length / 1024).toStringAsFixed(0)} KB — download incompleto');
      }
      if (!pacotePareceZip(bytes)) {
        return (false, 'o arquivo baixado não é um pacote .zip (não vou aplicar)');
      }
      final archive = ZipDecoder().decodeBytes(bytes);
      final nomes = archive.files.map((f) => f.name).toList();
      if (!nomes.contains('data/app.so')) {
        return (false,
            'o pacote não traz o data/app.so (o programa em si) — não vou aplicar');
      }
      final staging = Directory(stagingDir);
      if (staging.existsSync()) staging.deleteSync(recursive: true);
      staging.createSync(recursive: true);
      // Tem que esperar: a extração é assíncrona e o script que aplica a
      // atualização só roda depois — se voltasse antes, copiaria pasta vazia.
      await extractArchiveToDisk(archive, stagingDir);
      return (true, '${nomes.length} arquivo(s) prontos para aplicar');
    } catch (e) {
      return (false, 'não consegui abrir o pacote baixado: $e');
    }
  }

  /// Confere se os bytes são mesmo um ZIP (assinatura "PK").
  @visibleForTesting
  static bool pacotePareceZip(List<int> bytes) {
    if (bytes.length < 4) return false;
    return bytes[0] == 0x50 &&
        bytes[1] == 0x4B &&
        (bytes[2] == 0x03 || bytes[2] == 0x05 || bytes[2] == 0x07);
  }

  /// Publica uma atualização no Supabase (global ou por empresa).
  ///
  /// Sobe o PACOTE da versão (`.zip` com `data/app.so`, `data/flutter_assets`
  /// e o executável) para o Storage e grava a versão na `bridge_config`.
  ///
  /// Publicar apenas o `sistema_exodo_novo.exe` não atualiza o programa: ele
  /// tem ~85 KB e é igual em todas as versões — o código de verdade fica no
  /// `data/app.so`, que é o que o pacote leva.
  ///
  /// [empresaIds] publica a MESMA build para uma ou várias empresas de uma vez;
  /// sem destino, publica para TODOS os clientes (`app_latest`).
  /// [force] publica com um '!' na frente: os clientes baixam mesmo que já
  /// estejam numa versão mais nova (é assim que se volta atrás uma versão).
  /// [pacote] permite reaproveitar um pacote já montado.
  /// [usarPacoteDaNuvem] NÃO monta nem envia nada: aponta o destino para o
  /// pacote que JÁ está na nuvem desta versão (voltar atrás de uma versão, ou
  /// repetir a mesma versão em outra empresa).
  /// [notas] são os DETALHES da atualização — vão para a nuvem ao lado do
  /// pacote e aparecem para o cliente na tela de atualização.
  /// Retorna (sucesso, mensagem).
  static Future<(bool, String)> publicarAtualizacao({
    required String versao,
    String? empresaId, // null = global
    List<String>? empresaIds, // uma ou várias empresas
    bool force = false,
    PacoteAtualizacao? pacote,
    bool usarPacoteDaNuvem = false,
    String notas = '',
    void Function(String etapa)? onEtapa,
  }) async {
    try {
      final versaoLimpa = versao.trim().replaceAll('!', '');
      if (versaoLimpa.isEmpty) {
        return (false, 'Informe a versão (ex: $currentAppVersion).');
      }
      final dbVersion = force ? '!$versaoLimpa' : versaoLimpa;

      // Sem destino = global (app_latest).
      final destinos = <String>[
        if (empresaIds != null && empresaIds.isNotEmpty)
          ...empresaIds
        else if (empresaId != null && empresaId.isNotEmpty)
          empresaId,
      ];
      final isGlobal = destinos.isEmpty;

      debugPrint('>>> [AppUpdateService] 📦 Publicando versão $dbVersion '
          '(${isGlobal ? "GLOBAL" : "EMPRESA(S): ${destinos.join(", ")}"})');

      // 1. De onde vem o pacote desta versão:
      //    - `usarPacoteDaNuvem`: reaproveita o que já está publicado (não
      //      compila, não empacota e não sobe arquivo nenhum);
      //    - senão: monta o pacote nesta máquina e envia.
      final bucketName = bucketAtualizacoes;
      final fileName = nomePacoteDaVersao(versaoLimpa);
      PacoteAtualizacao? arquivo;
      late final String downloadUrl;

      if (usarPacoteDaNuvem) {
        onEtapa?.call('Procurando o pacote da versão $versaoLimpa na nuvem...');
        final jaNaNuvem = await listarVersoesNaNuvem();
        final existente =
            jaNaNuvem.where((v) => v.versao == versaoLimpa).toList();
        if (existente.isEmpty) {
          final disponiveis = jaNaNuvem.isEmpty
              ? 'não há nenhum pacote publicado'
              : 'disponíveis: '
                  '${jaNaNuvem.take(8).map((v) => v.versao).join(", ")}';
          return (false,
              'A versão $versaoLimpa não tem pacote na nuvem ($disponiveis).\n\n'
              'Para enviar esta versão, gere e compile o pacote antes '
              '(assistente "Gerar versão" ou a opção de pacote desta máquina).');
        }
        downloadUrl = SupabaseService.instance.client.storage
            .from(bucketName)
            .getPublicUrl(fileName);
        debugPrint('>>> [AppUpdateService] ♻️ Reaproveitando o pacote já '
            'publicado da versão $versaoLimpa '
            '(${existente.first.tamanhoLegivel})');
      } else {
        onEtapa?.call('Montando o pacote do programa...');
        arquivo = pacote ?? await empacotarAtualizacao();
        if (arquivo == null) {
          return (false,
              'Não encontrei o programa compilado para empacotar.\n'
              'Compile antes com:\n'
              '  flutter build windows --release\n\n'
              'Procurei nestas pastas:\n'
              '${pastasDoProgramaCompilado().map((c) => "  - $c").join("\n")}');
        }
        debugPrint('>>> [AppUpdateService] 📏 ${arquivo.caminho} — '
            '${arquivo.tamanhoLegivel} (${arquivo.conteudo.join(", ")})');

        // 2. Upload. Um arquivo POR VERSÃO: cada publicação fica imutável (sem
        //    cache servindo versão velha) e publicar para uma empresa não troca
        //    o arquivo que outra já baixou.
        onEtapa?.call('Enviando ${arquivo.tamanhoLegivel} para a nuvem...');
        final fileBytes = await File(arquivo.caminho).readAsBytes();
        try {
          await SupabaseService.instance.client.storage
              .from(bucketName)
              .uploadBinary(fileName, fileBytes,
                  fileOptions: const FileOptions(upsert: true));
        } catch (e) {
          debugPrint('>>> [AppUpdateService] ⚠️ Erro no upload: $e');
          // Criar o bucket só ajuda se ele realmente não existir — e o app
          // (papel `anon`) não tem esse poder. Se a recusa foi de permissão, o
          // problema está na política do bucket, e é isso que a mensagem diz.
          if (recusaPorPermissao(e)) {
            return (
              false,
              'Erro ao enviar o pacote:\n${_curto(e)}'
                  '${dicaDePermissao(e, 'o bucket "$bucketName"')}'
            );
          }
          try {
            await SupabaseService.instance.client.storage.createBucket(
              bucketName,
              const BucketOptions(public: true),
            );
            await SupabaseService.instance.client.storage
                .from(bucketName)
                .uploadBinary(fileName, fileBytes,
                    fileOptions: const FileOptions(upsert: true));
          } catch (e2) {
            return (
              false,
              'Erro ao enviar o pacote:\n${_curto(e2)}'
                  '${dicaDePermissao(e2, 'o bucket "$bucketName"')}'
            );
          }
        }
        downloadUrl = SupabaseService.instance.client.storage
            .from(bucketName)
            .getPublicUrl(fileName);
        debugPrint('>>> [AppUpdateService] ✅ Upload concluído: $downloadUrl');
      }

      // 2b. Detalhes da versão, ao lado do pacote (é o que o cliente lê na
      //     tela de atualização). Falhar aqui não impede a atualização.
      final detalhes = notas.trim();
      var detalhesPublicados = false;
      if (detalhes.isNotEmpty) {
        onEtapa?.call('Enviando os detalhes da versão...');
        try {
          await SupabaseService.instance.client.storage
              .from(bucketName)
              .uploadBinary(nomeNotasDaVersao(versaoLimpa),
                  utf8.encode('$detalhes\n'),
                  fileOptions: const FileOptions(upsert: true));
          detalhesPublicados = true;
        } catch (e) {
          debugPrint('>>> [AppUpdateService] ⚠️ Não subi os detalhes: $e');
        }
      }

      // 3. Gravar a versão de cada destino.
      onEtapa?.call('Gravando a versão na nuvem...');
      final publicados = <String>[];
      final falhas = <String>[];
      final alvos = destinos.isEmpty ? <String?>[null] : destinos;
      for (final destino in alvos) {
        final configId = idConfigDoDestino(destino);
        try {
          await SupabaseService.instance.client.from('bridge_config').upsert(
                registroDaPublicacao(
                  configId: configId,
                  versao: dbVersion,
                  url: downloadUrl,
                ),
                onConflict: 'id',
              );
          final check = await SupabaseService.instance.client
              .from('bridge_config')
              .select()
              .eq('id', configId)
              .maybeSingle();
          if (check == null) {
            falhas.add('$configId (registro não confirmado)');
          } else {
            publicados.add(configId);
            debugPrint('>>> [AppUpdateService] ✅ $configId → $dbVersion');
          }
        } catch (e) {
          debugPrint('>>> [AppUpdateService] ❌ Erro ao salvar $configId: $e');
          falhas.add('$configId (${_curto(e)})'
              '${dicaDePermissao(e, 'bridge_config')}');
        }
      }

      if (publicados.isEmpty) {
        return (false,
            'O pacote subiu, mas nenhuma versão foi gravada:\n${falhas.join('\n')}');
      }

      final linhas = <String>[
        if (isGlobal)
          '✅ Versão $versaoLimpa publicada para TODOS os clientes.'
        else
          '✅ Versão $versaoLimpa publicada para ${publicados.length} empresa(s).',
        if (usarPacoteDaNuvem)
          '♻️ Nada foi enviado: o pacote desta versão já estava na nuvem '
              '($fileName).'
        else
          '📤 Pacote enviado agora: ${p.basename(arquivo!.caminho)} '
              '(${arquivo.tamanhoLegivel})',
        if (arquivo != null) 'Conteúdo: ${arquivo.conteudo.join(', ')}',
        'Link: $downloadUrl',
        if (detalhes.isEmpty)
          'Detalhes da versão: não informados'
        else if (detalhesPublicados)
          'Detalhes da versão: enviados (o cliente lê na tela de atualização)'
        else
          '⚠️ Os detalhes não subiram (a atualização foi publicada assim mesmo)',
      ];
      if (force) {
        linhas
          ..add('')
          ..add('⚠️ Publicada como FORÇADA: quem já estiver numa versão mais '
              'nova também vai baixar esta.');
      }
      if (falhas.isNotEmpty) {
        linhas
          ..add('')
          ..add('⚠️ Falharam:')
          ..addAll(falhas.map((f) => '   • $f'));
      }
      final msg = linhas.join('\n');
      debugPrint('>>> [AppUpdateService] $msg');
      return (falhas.isEmpty, msg);
    } catch (e) {
      debugPrint('>>> [AppUpdateService] ❌ Erro ao publicar: $e');
      return (false, 'Erro inesperado: $e');
    }
  }

  /// Pastas onde procurar o programa compilado, da mais provável à menos.
  static List<String> pastasDoProgramaCompilado() {
    final exeDir = p.dirname(Platform.resolvedExecutable);
    final home =
        Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'] ?? '';
    return <String>[
      // Build Release do repositório (quando o publicador roda do projeto)
      p.join(exeDir, '..', '..', '..', '..', 'build', 'windows', 'x64',
          'runner', 'Release'),
      // Pasta de onde o app está rodando agora
      exeDir,
      // Instalações conhecidas
      'C:\\SistemaExodo',
      p.join(home, 'SistemaExodo'),
    ].map((c) => p.normalize(c)).toList();
  }

  /// Monta o pacote `.zip` com o programa que será publicado.
  ///
  /// Leva o que REALMENTE muda o programa: `data/app.so` (o código compilado),
  /// `data/flutter_assets` (telas, fontes, imagens) e o `sistema_exodo_novo.exe`.
  /// Só o `.exe` (como era antes) não atualiza nada: ele é o runner do Flutter,
  /// igualzinho em todas as versões.
  static Future<PacoteAtualizacao?> empacotarAtualizacao({String? pasta}) async {
    Directory? origem;
    final candidatas =
        pasta != null ? <String>[pasta] : pastasDoProgramaCompilado();
    for (final candidata in candidatas) {
      final dir = Directory(candidata);
      final temCodigo = File(p.join(dir.path, 'data', 'app.so')).existsSync();
      final temExe =
          File(p.join(dir.path, 'sistema_exodo_novo.exe')).existsSync();
      if (temCodigo && temExe) {
        origem = dir;
        break;
      }
    }
    if (origem == null) return null;

    final zip = File(p.join(Directory.systemTemp.path,
        'exodo_pacote_${DateTime.now().millisecondsSinceEpoch}.zip'));
    final conteudo = <String>[];
    final encoder = ZipFileEncoder();
    try {
      encoder.create(zip.path);
      await encoder.addFile(
          File(p.join(origem.path, 'data', 'app.so')), 'data/app.so');
      conteudo.add('data/app.so');

      final assets = Directory(p.join(origem.path, 'data', 'flutter_assets'));
      if (assets.existsSync()) {
        final raiz = assets.path;
        for (final item in assets.listSync(recursive: true)) {
          if (item is! File) continue;
          final rel = p.relative(item.path, from: raiz).replaceAll('\\', '/');
          await encoder.addFile(item, 'data/flutter_assets/$rel');
        }
        conteudo.add('data/flutter_assets');
      }

      await encoder.addFile(File(p.join(origem.path, 'sistema_exodo_novo.exe')),
          'sistema_exodo_novo.exe');
      conteudo.add('sistema_exodo_novo.exe');
      await encoder.close();
    } catch (e) {
      debugPrint('>>> [AppUpdateService] ❌ Erro ao montar o pacote: $e');
      return null;
    }

    final stat = zip.statSync();
    return PacoteAtualizacao(
      caminho: zip.path,
      bytes: stat.size,
      modificadoEm: stat.modified,
      conteudo: conteudo,
    );
  }

  /// Lê as versões publicadas na nuvem (a global e as direcionadas por empresa).
  static Future<List<PublicacaoVersao>> listarPublicacoes() async {
    try {
      if (!SupabaseService.isAvailable) return [];
      final linhas = await SupabaseService.instance
          .select('bridge_config')
          .timeout(const Duration(seconds: 15));
      return interpretarPublicacoes(linhas);
    } catch (e) {
      debugPrint('>>> [AppUpdateService] ❌ Erro ao listar publicações: $e');
      return [];
    }
  }

  /// Tira o direcionamento de uma empresa (ela volta a seguir a versão global).
  /// Com [empresaId] nulo, remove a versão global (ninguém mais se atualiza).
  static Future<(bool, String)> removerPublicacao(String? empresaId) async {
    final configId = idConfigDoDestino(empresaId);
    try {
      await SupabaseService.instance.client
          .from('bridge_config')
          .delete()
          .eq('id', configId);
      final confirma = await SupabaseService.instance.client
          .from('bridge_config')
          .select()
          .eq('id', configId)
          .maybeSingle();
      if (confirma != null) {
        return (false, 'O registro $configId continua na nuvem.');
      }
      final onde = configId == PublicacaoVersao.idGlobal
          ? 'a versão de TODOS os clientes'
          : 'o direcionamento desta empresa';
      return (true, 'Removido: $onde ($configId).');
    } catch (e) {
      return (false, 'Erro ao remover $configId: ${_curto(e)}');
    }
  }

  /// Nome do pacote na nuvem: um por versão (nunca sobrescreve outra versão).
  @visibleForTesting
  static String nomePacoteDaVersao(String versao) {
    final limpa = versao.replaceAll('!', '').trim();
    final segura = limpa.isEmpty
        ? 'sem_versao'
        : limpa.replaceAll(RegExp(r'[^0-9A-Za-z._-]'), '_');
    return 'sistema_exodo_novo_$segura.zip';
  }

  /// Bucket onde ficam os pacotes por versão (e as notas de cada uma).
  static const String bucketAtualizacoes = 'atualizacoes';

  /// Nome de arquivo do pacote → versão. Devolve `null` para o que NÃO é
  /// pacote — o `..._1.0.37.notas.txt` é ignorado de propósito.
  @visibleForTesting
  static String? versaoDoNomeDoPacote(String nome) {
    final achado = _nomeDoPacoteNaNuvem.firstMatch(nome.trim());
    return achado?.group(1);
  }

  static final RegExp _nomeDoPacoteNaNuvem =
      RegExp(r'^sistema_exodo_novo_(\d+(?:\.\d+){1,3})\.zip$');

  /// Compara duas versões pelo NÚMERO (1.0.10 é maior que 1.0.9, o que
  /// comparar texto erraria). Devolve <0, 0 ou >0.
  @visibleForTesting
  static int compararVersoes(String a, String b) {
    List<int> partes(String v) => v
        .trim()
        .replaceAll('!', '')
        .split('.')
        .map((p) => int.tryParse(p) ?? 0)
        .toList();
    final pa = partes(a);
    final pb = partes(b);
    final tamanho = pa.length > pb.length ? pa.length : pb.length;
    for (var i = 0; i < tamanho; i++) {
      final va = i < pa.length ? pa[i] : 0;
      final vb = i < pb.length ? pb[i] : 0;
      if (va != vb) return va < vb ? -1 : 1;
    }
    return 0;
  }

  /// A maior versão de uma lista ('' quando não há nenhuma).
  ///
  /// Serve para a numeração automática nunca repetir um número que já foi
  /// publicado — mesmo que o código esteja atrás da nuvem.
  @visibleForTesting
  static String maiorVersao(Iterable<String> versoes) {
    var maior = '';
    for (final versao in versoes) {
      final limpa = versao.trim().replaceAll('!', '');
      if (limpa.isEmpty) continue;
      if (maior.isEmpty || compararVersoes(limpa, maior) > 0) maior = limpa;
    }
    return maior;
  }

  /// Lê a resposta do Storage (`list()`) e separa o que é PACOTE de versão,
  /// da mais nova para a mais antiga.
  @visibleForTesting
  static List<VersaoNaNuvem> interpretarVersoesNaNuvem(
      Iterable<Map<String, dynamic>> objetos) {
    final porVersao = <String, VersaoNaNuvem>{};
    for (final objeto in objetos) {
      final versao = versaoDoNomeDoPacote((objeto['name'] ?? '').toString());
      if (versao == null) continue;
      final meta = objeto['metadata'];
      final bytes = meta is Map && meta['size'] is num
          ? (meta['size'] as num).toInt()
          : 0;
      final quando = DateTime.tryParse(
          (objeto['updated_at'] ?? objeto['created_at'] ?? '').toString());
      final atual = porVersao[versao];
      if (atual == null ||
          (quando != null &&
              (atual.enviadoEm == null || quando.isAfter(atual.enviadoEm!)))) {
        porVersao[versao] = VersaoNaNuvem(
          versao: versao,
          bytes: bytes,
          enviadoEm: quando,
        );
      }
    }
    return porVersao.values.toList()
      ..sort((a, b) => compararVersoes(b.versao, a.versao));
  }

  /// Versões cujo pacote já está na nuvem (da mais nova para a mais antiga).
  ///
  /// É a lista que a publicação mostra para reaproveitar um pacote: escolher
  /// uma delas não compila nada e não sobe arquivo nenhum.
  static Future<List<VersaoNaNuvem>> listarVersoesNaNuvem() async {
    try {
      if (!SupabaseService.isAvailable) return [];
      final objetos = await SupabaseService.instance.client.storage
          .from(bucketAtualizacoes)
          .list(searchOptions: const SearchOptions(limit: 1000))
          .timeout(const Duration(seconds: 20));
      return interpretarVersoesNaNuvem(objetos.map<Map<String, dynamic>>((o) => {
        'name': o.name,
        'metadata': o.metadata,
        'updated_at': o.updatedAt,
        'created_at': o.createdAt,
      }));
    } catch (e) {
      debugPrint('>>> [AppUpdateService] ❌ Erro ao listar versões da nuvem: $e');
      return [];
    }
  }

  /// O pacote desta versão já está na nuvem?
  static Future<bool> pacoteNaNuvem({required String versao}) async {
    final limpa = versao.trim().replaceAll('!', '');
    final versoes = await listarVersoesNaNuvem();
    return versoes.any((v) => v.versao == limpa);
  }

  /// Id do registro na `bridge_config` para um destino (null/vazio = global).
  @visibleForTesting
  static String idConfigDoDestino(String? empresaId) =>
      (empresaId == null || empresaId.isEmpty)
          ? PublicacaoVersao.idGlobal
          : '${PublicacaoVersao.prefixoEmpresa}$empresaId';

  /// Registro que vai para a `bridge_config`: SOMENTE colunas que existem lá
  /// (id, version, download_url). Mandar coluna a mais (ex: 'ativo') faz o
  /// PostgREST recusar o registro inteiro (PGRST204) e a publicação não
  /// acontece — era exatamente isso que impedia publicar pelo app.
  @visibleForTesting
  static Map<String, dynamic> registroDaPublicacao({
    required String configId,
    required String versao,
    required String url,
  }) =>
      {'id': configId, 'version': versao, 'download_url': url};

  @visibleForTesting
  static List<PublicacaoVersao> interpretarPublicacoes(
      List<Map<String, dynamic>> linhas) {
    final lista = <PublicacaoVersao>[];
    for (final linha in linhas) {
      final publicacao = PublicacaoVersao.daLinha(linha);
      if (publicacao != null) lista.add(publicacao);
    }
    lista.sort((a, b) {
      if (a.global != b.global) return a.global ? -1 : 1;
      return a.id.compareTo(b.id);
    });
    return lista;
  }

  static String _curto(Object erro) {
    final texto = erro.toString();
    return texto.length > 200 ? '${texto.substring(0, 200)}…' : texto;
  }

  /// A nuvem recusou a operação por **permissão** (RLS/403)?
  ///
  /// É o erro que já apareceu duas vezes aqui: bucket de arquivos sem política
  /// (`Erro ao enviar o pacote: ... row-level security policy ... 403`) e
  /// `bridge_config` sem escrita para o papel que o app usa.
  @visibleForTesting
  static bool recusaPorPermissao(Object erro) {
    final texto = erro.toString().toLowerCase();
    return texto.contains('row-level security') ||
        texto.contains('unauthorized') ||
        texto.contains('permission denied') ||
        texto.contains('403');
  }

  /// O que fazer quando a nuvem recusa por permissão.
  ///
  /// O erro cru do Supabase não diz onde mexer; esta frase diz. Vazio quando o
  /// erro não é de permissão.
  @visibleForTesting
  static String dicaDePermissao(Object erro, String recurso) {
    if (!recusaPorPermissao(erro)) return '';
    return '\n\nA nuvem recusou gravar em $recurso por permissão (RLS). '
        'O app fala com a nuvem como "anon", que só grava onde existe política. '
        'Rode as migrações de supabase/migrations (a 006 libera os buckets de '
        'arquivos e a 007 a publicação de versões).';
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Gerar uma versão nova: numeração, código, compilação e detalhes
  // ───────────────────────────────────────────────────────────────────────────

  /// Onde está o código-fonte do projeto (o `pubspec.yaml` + o serviço de
  /// atualização). É de lá que sai a versão nova, então o assistente precisa
  /// achar essa pasta — ela não existe na máquina de quem só usa o sistema.
  static String? pastaDoProjeto() {
    final candidatas = <String>[];
    var pasta = p.dirname(Platform.resolvedExecutable);
    for (var i = 0; i < 6; i++) {
      candidatas.add(pasta);
      final pai = p.dirname(pasta);
      if (pai == pasta) break;
      pasta = pai;
    }
    final home =
        Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'] ?? '';
    if (home.isNotEmpty) {
      // Projetos guardados em ~/.antigravity/<nome>
      final antigravity = Directory(p.join(home, '.antigravity'));
      if (antigravity.existsSync()) {
        for (final item in antigravity.listSync()) {
          if (item is Directory) candidatas.add(item.path);
        }
      }
      candidatas.add(p.join(home, 'sistema_exodo'));
      candidatas.addAll(['C:\\sistema_exodo', 'C:\\SistemaExodo\\codigo']);
    }

    for (final candidata in candidatas) {
      final temProjeto = File(p.join(candidata, 'pubspec.yaml')).existsSync() &&
          File(p.join(candidata, 'lib', 'services', 'app_update_service.dart'))
              .existsSync();
      if (temProjeto) return p.normalize(candidata);
    }
    return null;
  }

  /// Caminho do arquivo que guarda a versão compilada no programa.
  static String arquivoDaVersao(String pasta) =>
      p.join(pasta, 'lib', 'services', 'app_update_service.dart');

  /// Lê do CÓDIGO a versão atual (`currentAppVersion`).
  ///
  /// É essa que vale para os clientes: a versão do app rodando é a compilada,
  /// e pode estar atrás do código.
  static Future<String?> lerVersaoDoCodigo(String pasta) async {
    try {
      final arquivo = File(arquivoDaVersao(pasta));
      if (!await arquivo.exists()) return null;
      final conteudo = await arquivo.readAsString();
      final achado = _versaoNoCodigo.firstMatch(conteudo);
      return achado?.group(1);
    } catch (e) {
      debugPrint('>>> [AppUpdateService] Erro ao ler a versão do código: $e');
      return null;
    }
  }

  static final RegExp _versaoNoCodigo =
      RegExp(r'currentAppVersion\s*=\s*"([^"]+)"');

  /// Grava a versão nova no código (é isso que faz o cliente enxergar a versão).
  /// Retorna (ok, mensagem).
  static Future<(bool, String)> gravarVersaoNoCodigo(
      String pasta, String versao) async {
    final limpa = versao.trim().replaceAll('!', '');
    if (!RegExp(r'^\d+\.\d+\.\d+(\.\d+)?$').hasMatch(limpa)) {
      return (false, 'Versão inválida: "$versao". Use o formato 1.0.37.');
    }
    try {
      final arquivo = File(arquivoDaVersao(pasta));
      if (!await arquivo.exists()) {
        return (false, 'Não achei ${arquivo.path}');
      }
      final conteudo = await arquivo.readAsString();
      if (!_versaoNoCodigo.hasMatch(conteudo)) {
        return (false,
            'Não achei a linha currentAppVersion em ${arquivo.path} — não vou mexer no arquivo.');
      }
      final novo = conteudo.replaceFirstMapped(
          _versaoNoCodigo, (m) => 'currentAppVersion = "$limpa"');
      await arquivo.writeAsString(novo);
      return (true, 'Código agora está na versão $limpa.');
    } catch (e) {
      return (false, 'Erro ao gravar a versão no código: $e');
    }
  }

  /// Próximo número de versão a partir do atual.
  ///
  /// - [TipoIncrementoVersao.correcao]: 1.0.36 → 1.0.37
  /// - [TipoIncrementoVersao.versaoNova]: 1.0.36 → 1.1.0
  /// - [TipoIncrementoVersao.versaoGrande]: 1.0.36 → 2.0.0
  @visibleForTesting
  static String proximaVersao(String atual, TipoIncrementoVersao tipo) {
    final partes = atual
        .trim()
        .replaceAll('!', '')
        .split('.')
        .map((p) => int.tryParse(p) ?? 0)
        .toList();
    while (partes.length < 3) {
      partes.add(0);
    }
    final maior = partes[0];
    final menor = partes[1];
    final correcao = partes[2];
    switch (tipo) {
      case TipoIncrementoVersao.correcao:
        return '$maior.$menor.${correcao + 1}';
      case TipoIncrementoVersao.versaoNova:
        return '$maior.${menor + 1}.0';
      case TipoIncrementoVersao.versaoGrande:
        return '${maior + 1}.0.0';
    }
  }

  /// Nome do arquivo de DETALHES da versão na nuvem (fica ao lado do pacote).
  @visibleForTesting
  static String nomeNotasDaVersao(String versao) =>
      nomePacoteDaVersao(versao).replaceAll('.zip', '.notas.txt');

  /// Endereço dos detalhes a partir do endereço do pacote (`...zip`).
  /// Devolve `null` se o link não for de pacote `.zip`.
  @visibleForTesting
  static String? urlDasNotas(String urlDoPacote) {
    final url = urlDoPacote.trim();
    if (url.isEmpty) return null;
    final minusculo = url.toLowerCase();
    if (!minusculo.contains('.zip')) return null;
    final posicao = minusculo.lastIndexOf('.zip');
    return '${url.substring(0, posicao)}.notas.txt';
  }

  /// Baixa os detalhes da versão publicada ("novidades") — o cliente mostra
  /// isso na tela de atualização. Silencioso: sem detalhes, devolve null.
  static Future<String?> buscarNotas(String downloadUrl) async {
    final url = urlDasNotas(downloadUrl);
    if (url == null) return null;
    try {
      final resposta = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 5));
      if (resposta.statusCode != 200) return null;
      final texto =
          utf8.decode(resposta.bodyBytes, allowMalformed: true).trim();
      return texto.isEmpty ? null : texto;
    } catch (e) {
      debugPrint('>>> [AppUpdateService] Sem detalhes da versão: $e');
      return null;
    }
  }

  /// Endereço PÚBLICO do pacote de uma versão que já está no bucket.
  ///
  /// É o mesmo link que a publicação grava na `bridge_config`. Serve para o
  /// app montar o endereço das NOVIDADES da versão que ELE está rodando: o
  /// `..._<versao>.notas.txt` fica sempre ao lado do pacote.
  static String urlPublicaDaVersao(String versao) =>
      SupabaseService.instance.client.storage
          .from(bucketAtualizacoes)
          .getPublicUrl(nomePacoteDaVersao(versao));

  /// As novidades JÁ PUBLICADAS de uma versão (o `..._<versao>.notas.txt` do
  /// bucket). Sem detalhes publicados, devolve `null`.
  static Future<String?> notasDaVersao(String versao) =>
      buscarNotas(urlPublicaDaVersao(versao));

  /// Linha do histórico de versões (`HISTORICO_VERSOES.md`), guardado junto do
  /// código: o que foi publicado, quando, para quem e o que mudou.
  @visibleForTesting
  static String entradaDoHistorico({
    required String versao,
    required String detalhes,
    required String destino,
    DateTime? quando,
  }) {
    final data = quando ?? DateTime.now();
    String dois(int n) => n.toString().padLeft(2, '0');
    final carimbo =
        '${dois(data.day)}/${dois(data.month)}/${data.year} ${dois(data.hour)}:${dois(data.minute)}';
    final textoDetalhes =
        detalhes.trim().isEmpty ? '(sem detalhes informados)' : detalhes.trim();
    final linhas = <String>['', '## $versao — $carimbo', '- destino: $destino'];
    for (final linha in textoDetalhes.split('\n')) {
      linhas.add('- ${linha.trim()}');
    }
    return '${linhas.join('\n')}\n';
  }

  /// Acrescenta a entrada no histórico, criando o arquivo na primeira vez.
  static Future<bool> registrarNoHistorico({
    required String versao,
    required String detalhes,
    required String destino,
  }) async {
    try {
      final pasta = pastaDoProjeto();
      if (pasta == null) return false;
      final arquivo = File(p.join(pasta, 'HISTORICO_VERSOES.md'));
      if (!await arquivo.exists()) {
        await arquivo.writeAsString(
            '# Histórico de versões publicadas\n\n'
            'Cada entrada é escrita quando você publica uma versão pelo sistema.\n');
      }
      await arquivo.writeAsString(
        entradaDoHistorico(
            versao: versao, detalhes: detalhes, destino: destino),
        mode: FileMode.append,
      );
      return true;
    } catch (e) {
      debugPrint('>>> [AppUpdateService] Não consegui escrever o histórico: $e');
      return false;
    }
  }

  /// Compila o programa (`flutter build windows --release`) na pasta do projeto,
  /// devolvendo as linhas do compilador em [onLinha] (a tela mostra ao vivo).
  /// Retorna (ok, mensagem).
  static Future<(bool, String)> compilarProjeto({
    required String pasta,
    void Function(String linha)? onLinha,
    Duration limite = const Duration(minutes: 12),
  }) async {
    try {
      final processo = await Process.start(
        'flutter',
        ['build', 'windows', '--release'],
        workingDirectory: pasta,
        runInShell: true,
      );
      final linhas = <String>[];
      void guardar(String linha) {
        if (linha.trim().isEmpty) return;
        linhas.add(linha.trimRight());
        onLinha?.call(linha.trimRight());
      }

      final saida = processo.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(guardar);
      final erros = processo.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(guardar);

      final codigo = await processo.exitCode.timeout(limite, onTimeout: () {
        processo.kill();
        return -1;
      });
      await saida.cancel();
      await erros.cancel();

      if (codigo == 0) {
        return (true, 'Programa compilado (${linhas.length} linha(s) de saída).');
      }
      final fim = linhas.length > 8
          ? linhas.sublist(linhas.length - 8).join('\n')
          : linhas.join('\n');
      return (false, codigo == -1
          ? 'A compilação passou de ${limite.inMinutes} minutos e foi cancelada.\n$fim'
          : 'A compilação falhou (código $codigo).\n$fim');
    } on ProcessException catch (e) {
      return (false,
          'Não consegui rodar o "flutter" (${e.message}).\n'
          'Confira se o Flutter está instalado e no PATH.');
    } catch (e) {
      return (false, 'Erro ao compilar: $e');
    }
  }

  // ──────────────────────── progresso da geração ────────────────────────

  /// Percentual da barra dentro da etapa atual.
  ///
  /// O `flutter build windows --release` **não informa percentual**: ele só
  /// imprime marcos (CMake, MSBuild, "Built ..."). Então a barra combina dois
  /// sinais: os marcos ([etapaDaLinhaDeCompilacao]) mudam a etapa, e o tempo
  /// decorrido na etapa faz a barra andar dentro da faixa dela — devagar, cada
  /// vez menos, para não bater no teto e ficar plantada enquanto a compilação
  /// termina. Só concluir a etapa (`empacotando`, `pronta`) chega ao fim dela.
  static double percentualDaEtapa(
    EtapaGeracaoVersao etapa,
    Duration naEtapa,
  ) {
    // Etapa instantânea (a versão pronta): a barra cheia é o próprio valor.
    if (etapa.fim <= etapa.inicio) return etapa.fim;
    final estimativa = etapa.estimativa.inMilliseconds;
    if (estimativa <= 0) return etapa.fim;

    final andado = naEtapa.inMilliseconds / estimativa;
    final tempo = andado <= 0 ? 0.0 : andado;
    // Curva que desacelera sem parar: 1/3 do previsto → 49% da faixa; o
    // previsto → 74%; o dobro → 85%. A barra sempre anda, nunca "trava" no fim.
    final suave = tempo / (tempo + 0.35);
    final alvo = etapa.inicio + (etapa.fim - etapa.inicio) * suave;
    return alvo.clamp(etapa.inicio, etapa.teto);
  }

  /// Em que etapa da barra a linha de saída do compilador coloca a geração.
  ///
  /// Reconhece os marcos que o Flutter/MSBuild imprimem; devolve `null` para o
  /// resto (o tempo cuida de avançar quando o compilador fica mudo).
  static EtapaGeracaoVersao? etapaDaLinhaDeCompilacao(String linha) {
    final texto = linha.toLowerCase();
    if (texto.contains('building windows application') ||
        texto.contains('running cmake') ||
        texto.contains('running "cmake"') ||
        texto.contains('cmake configure')) {
      return EtapaGeracaoVersao.preparandoCompilacao;
    }
    if (texto.contains('gen_snapshot') ||
        texto.contains('building aot') ||
        texto.contains('app.so') ||
        texto.contains('build engine version') ||
        texto.contains('vcxproj') ||
        texto.contains('compiling c++') ||
        texto.contains('compilando c++')) {
      return EtapaGeracaoVersao.compilando;
    }
    return null;
  }

  /// Se a saída do compilador não trouxer nenhum marco conhecido — o que muda
  /// conforme a versão do Flutter e do MSBuild — a etapa precisa avançar
  /// sozinha, senão a barra fica plantada na primeira faixa por toda a
  /// compilação. Só a passagem "preparando → compilando" é feita por tempo
  /// (a partir daí quem manda é o fim real de cada passo).
  static EtapaGeracaoVersao? proximaEtapaPorTempo(
    EtapaGeracaoVersao etapa,
    Duration naEtapa,
  ) {
    const esperaDoCmake = Duration(seconds: 60);
    if (etapa == EtapaGeracaoVersao.preparandoCompilacao &&
        naEtapa >= esperaDoCmake) {
      return EtapaGeracaoVersao.compilando;
    }
    return null;
  }
}

/// Etapas da geração de uma versão, com a faixa da barra de progresso que cada
/// uma ocupa.
///
/// A faixa larga da compilação é de propósito: é ali que passam os minutos. As
/// etapas seguem a ordem real do trabalho — gravar o número no código, compilar
/// (`flutter build windows --release`) e montar o pacote da atualização.
enum EtapaGeracaoVersao {
  gravandoCodigo(0.00, 0.05, Duration(seconds: 3),
      'Gravando o número da versão no código...'),
  preparandoCompilacao(0.05, 0.15, Duration(minutes: 1),
      'Preparando a compilação (CMake)...'),
  compilando(0.15, 0.80, Duration(minutes: 4),
      'Compilando o programa (esta é a parte demorada)...'),
  empacotando(0.80, 0.95, Duration(seconds: 20),
      'Montando o pacote (.exe, app.so e dados)...'),
  pronta(1.00, 1.00, Duration.zero, 'Versão pronta.');

  const EtapaGeracaoVersao(this.inicio, this.fim, this.estimativa, this.rotulo);

  /// Onde a etapa começa na barra (0 = nada, 1 = pronto).
  final double inicio;

  /// Onde a etapa termina na barra.
  final double fim;

  /// Quanto tempo esta etapa costuma levar — é o que dá ritmo à barra enquanto
  /// o compilador está mudo. Não é um limite: a barra só desacelera perto do
  /// teto, nunca "acaba" antes do trabalho.
  final Duration estimativa;

  /// A frase mostrada ao lado da barra.
  final String rotulo;

  /// Quantas etapas existem antes de a versão estar pronta (para o "etapa 2 de
  /// 4" da tela — [pronta] não conta como trabalho).
  static const int totalDeTrabalho = 4;

  /// O número da etapa para mostrar ao usuário (1 = primeira).
  int get numero => index + 1;

  /// Maior percentual que o **tempo** consegue atingir nesta etapa. Deixa uma
  /// folga de 1% para o fim da faixa, que fica reservado para quando a etapa
  /// realmente termina — assim a barra nunca "chega em 100%" e espera.
  double get teto => fim >= 1.0 ? fim : fim - 0.01;
}

/// Que tipo de número novo a versão vai receber.
enum TipoIncrementoVersao {
  correcao, // 1.0.36 → 1.0.37
  versaoNova, // 1.0.36 → 1.1.0
  versaoGrande, // 1.0.36 → 2.0.0
}
