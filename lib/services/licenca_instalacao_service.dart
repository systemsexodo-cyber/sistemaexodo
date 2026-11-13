import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'env_config.dart';
import 'licenca_emergencia_service.dart';

/// Licença de INSTALAÇÃO: emitida na hora em que o sistema é instalado, vale
/// 30 dias, é assinada pela chave privada do dono do sistema e fica presa ao
/// computador (MachineGuid). Sem ela (ou vencida) o sistema NÃO abre.
///
/// - Copiar o setup/pasta do sistema para outro PC não copia essa identidade,
///   então a licença não vale lá.
/// - Reinstalar no MESMO computador não gera outros 30 dias: a nuvem só
///   devolve a licença existente. Depois do vencimento, só renova quem pagou a
///   mensalidade (a função da nuvem confere a empresa vinculada).
class LicencaInstalacao {
  final String licenseId;
  final String maquinaId;
  final DateTime emitidaEm;
  final DateTime expiraEm;

  const LicencaInstalacao({
    required this.licenseId,
    required this.maquinaId,
    required this.emitidaEm,
    required this.expiraEm,
  });

  bool get expirada => !expiraEm.isAfter(DateTime.now().toUtc());

  int get diasRestantes {
    final diferenca = expiraEm.difference(DateTime.now().toUtc());
    return diferenca.inDays + (diferenca.inHours % 24 > 0 ? 1 : 0);
  }
}

enum EstadoLicencaInstalacao {
  valida,
  ausente,
  expirada,
  invalida,
  outraMaquina,
  relogioAlterado,
}

class ResultadoLicencaInstalacao {
  final EstadoLicencaInstalacao estado;
  final LicencaInstalacao? licenca;
  final String mensagem;

  const ResultadoLicencaInstalacao({
    required this.estado,
    this.licenca,
    this.mensagem = '',
  });

  bool get podeUsar => estado == EstadoLicencaInstalacao.valida;
}

/// Resposta de ativar/renovar vinda da nuvem.
class RespostaLicencaInstalacao {
  final bool ok;
  final String mensagem;
  final String? codigo;

  const RespostaLicencaInstalacao({
    required this.ok,
    this.mensagem = '',
    this.codigo,
  });
}

class LicencaInstalacaoService {
  static const nomeArquivo = 'licenca_instalacao.json';
  static const _chaveUltimaVerificacao =
      'exodo_licenca_instalacao_ultima_verificacao';
  static const _chaveCodigoOffline = 'exodo_licenca_codigo_offline';
  static const _prazoDias = 30;

  static final http.Client _client = http.Client();

  // --- Código curto de liberação offline (EXO-OFF-XXXXXX-XXXXXX) -----------
  //
  // Contingência para quando a nuvem de licenças está fora do ar: o suporte
  // gera o código em `tools/licencas/gerar_codigo_offline.js`. O código é
  // preso ao ID deste computador, vale no máximo 30 dias e é conferido pelo
  // MAC abaixo. O segredo é compartilhado entre o gerador e o app — por isso
  // o código serve só para liberar a instalação, nunca para renovar cobrança.
  static const _segredoOffline =
      '650f736c0e4bb27c2673aa00ddeff3376fb0ec72e275afdc695b207ac3857d48';
  /// O segredo é guardado em hexadecimal; o MAC usa os bytes crus, como o
  /// gerador em Node (`Buffer.from(hex, 'hex')`).
  static final List<int> _chaveOffline = [
    for (var i = 0; i < _segredoOffline.length; i += 2)
      int.parse(_segredoOffline.substring(i, i + 2), radix: 16),
  ];
  static const _prefixoCodigoOffline = 'EXO-OFF';
  static const _alfabetoOffline = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
  static final DateTime _epocaOffline = DateTime.utc(2020, 1, 1);

  static List<int> _macOffline(String maquinaId, int dia) =>
      Hmac(sha256, _chaveOffline)
          .convert(utf8.encode('EXODO-OFFLINE-V1|$maquinaId|$dia'))
          .bytes
          .take(5)
          .toList();

  /// Reduz o que o cliente digitou (maiúsculas, sem separadores) aos 12
  /// caracteres do corpo do código. Devolve null quando não é um código.
  static String? _corpoCodigoOffline(String entrada) {
    var texto = entrada.toUpperCase().replaceAll(
      RegExp(r'[^A-Z0-9]'),
      '',
    );
    final prefixo = _prefixoCodigoOffline.replaceAll('-', '');
    if (!texto.startsWith(prefixo)) return null;
    texto = texto.substring(prefixo.length);
    // Erros comuns de digitação: o alfabeto não usa O, I, L nem U.
    texto = texto
        .replaceAll('O', '0')
        .replaceAll('I', '1')
        .replaceAll('L', '1');
    return texto.length == 12 ? texto : null;
  }

  /// Validade que o código concede neste computador, ou null se o código não
  /// confere (adulterado, de outro PC ou fora do formato).
  static DateTime? _expiraCodigoOffline(String entrada, String maquinaId) {
    final texto = _corpoCodigoOffline(entrada);
    if (texto == null) return null;

    var valor = BigInt.zero;
    for (final caractere in texto.split('')) {
      final indice = _alfabetoOffline.indexOf(caractere);
      if (indice < 0) return null;
      valor = (valor << 5) | BigInt.from(indice);
    }

    final dia = (valor >> 40).toInt();
    final esperado = _macOffline(maquinaId, dia);
    var confere = true;
    for (var i = 0; i < 5; i++) {
      final byte = ((valor >> (8 * (4 - i))) & BigInt.from(0xFF)).toInt();
      if (byte != esperado[i]) confere = false;
    }
    if (!confere) return null;

    // O dia gravado é inclusivo: o código vale até o fim dele.
    return _epocaOffline.add(Duration(days: dia + 1));
  }

  static Future<void> _salvarCodigoOffline(String codigo) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _chaveCodigoOffline,
      codigo.trim().toUpperCase(),
    );
  }

  /// Licença concedida por um código offline ainda válido, se houver.
  static Future<LicencaInstalacao?> _lerCodigoOffline() async {
    final prefs = await SharedPreferences.getInstance();
    final codigo = prefs.getString(_chaveCodigoOffline);
    if (codigo == null || codigo.isEmpty) return null;

    final maquina = await identificadorMaquina();
    final expira = _expiraCodigoOffline(codigo, maquina);
    if (expira == null || !expira.isAfter(DateTime.now().toUtc())) return null;

    return LicencaInstalacao(
      licenseId: 'offline-codigo',
      maquinaId: maquina,
      emitidaEm: expira.subtract(const Duration(days: _prazoDias)),
      expiraEm: expira,
    );
  }

  /// Aplica o código curto de liberação offline neste computador.
  static Future<RespostaLicencaInstalacao> aplicarCodigoOffline(
    String codigo,
  ) async {
    final maquinaAtual = await identificadorMaquina();
    final expira = _expiraCodigoOffline(codigo, maquinaAtual);
    if (expira == null) {
      return const RespostaLicencaInstalacao(
        ok: false,
        mensagem:
            'Código de liberação offline inválido para este computador. Confira os caracteres e tente novamente.',
      );
    }

    final agora = DateTime.now().toUtc();
    if (!expira.isAfter(agora)) {
      return const RespostaLicencaInstalacao(
        ok: false,
        mensagem:
            'Este código de liberação offline já venceu. Peça um novo ao suporte.',
      );
    }
    if (expira.difference(agora) > const Duration(days: _prazoDias + 1)) {
      return const RespostaLicencaInstalacao(
        ok: false,
        mensagem:
            'Este código de liberação tem validade acima do permitido. Peça um novo ao suporte.',
      );
    }

    await _salvarCodigoOffline(codigo);
    return RespostaLicencaInstalacao(
      ok: true,
      mensagem:
          'Código offline aplicado. Sistema liberado até ${_formatarData(expira)}.',
    );
  }

  /// Expõe a conferência do código para testes, sem gravar nada.
  @visibleForTesting
  static DateTime? validarCodigoOffline(String codigo, String maquinaId) =>
      _expiraCodigoOffline(codigo, maquinaId);

  static Future<String> identificadorMaquina() =>
      LicencaEmergenciaService.identificadorMaquina();

  /// Pastas onde a licença pode estar: ao lado do executável (onde o instalador
  /// grava) e na pasta de suporte do app (onde a renovação grava).
  static Future<List<Directory>> _pastas() async {
    final pastas = <Directory>[];
    if (!kIsWeb) {
      try {
        pastas.add(File(Platform.resolvedExecutable).parent);
      } catch (_) {}
      try {
        pastas.add(await getApplicationSupportDirectory());
      } catch (_) {}
    }
    return pastas;
  }

  /// Lê TODOS os arquivos de licença encontrados e devolve o documento válido
  /// com o vencimento mais distante (o instalador grava junto do exe e a
  /// renovação na pasta de suporte; o mais novo sempre ganha).
  static Future<_Documento?> _lerDocumento() async {
    _Documento? melhor;
    var achouArquivo = false;

    for (final pasta in await _pastas()) {
      final arquivo = File(p.join(pasta.path, nomeArquivo));
      if (!await arquivo.exists()) continue;
      achouArquivo = true;

      try {
        final bruto = await arquivo.readAsString();
        final doc = _decodificar(bruto);
        if (doc == null) continue;
        if (melhor == null || doc.licenca.expiraEm.isAfter(melhor.licenca.expiraEm)) {
          melhor = doc;
        }
      } catch (e) {
        debugPrint('>>> [LicencaInstalacao] Arquivo ilegível em ${arquivo.path}: $e');
      }
    }

    _ultimoArquivoEncontrado = achouArquivo;
    return melhor;
  }

  /// Se existe arquivo de licença no disco (mesmo inválido). Serve para
  /// distinguir "nunca ativado" de "licença adulterada".
  static bool _ultimoArquivoEncontrado = false;

  static _Documento? _decodificar(String texto) {
    try {
      final decoded = jsonDecode(texto);
      if (decoded is! Map) return null;

      final payloadRaw = decoded['payload'];
      final assinatura = decoded['assinatura']?.toString() ?? '';
      if (payloadRaw is! Map || assinatura.isEmpty) return null;

      // A ORDEM das chaves faz parte do documento assinado.
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

      if (payload['version'] != 1 || payload['type'] != 'instalacao') {
        return null;
      }
      final maquinaId = payload['machine_id']?.toString() ?? '';
      final licenseId = payload['license_id']?.toString() ?? '';
      if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(maquinaId) || licenseId.isEmpty) {
        return null;
      }

      final emitida = DateTime.tryParse(payload['issued_at']?.toString() ?? '');
      final expira = DateTime.tryParse(payload['expires_at']?.toString() ?? '');
      if (emitida == null || expira == null) return null;
      if (expira.difference(emitida) > const Duration(days: _prazoDias, hours: 1)) {
        return null;
      }

      final assinado = utf8.encode(jsonEncode(payload));
      if (!LicencaEmergenciaService.verificarAssinatura(assinado, assinatura)) {
        return null;
      }

      return _Documento(
        licenca: LicencaInstalacao(
          licenseId: licenseId,
          maquinaId: maquinaId,
          emitidaEm: emitida.toUtc(),
          expiraEm: expira.toUtc(),
        ),
      );
    } catch (e) {
      debugPrint('>>> [LicencaInstalacao] Documento recusado: $e');
      return null;
    }
  }

  /// Estado da licença deste computador. É o que trava (ou libera) o boot.
  static Future<ResultadoLicencaInstalacao> verificar() async {
    final maquinaAtual = await identificadorMaquina();

    // Relógio atrasado: se a última verificação foi "no futuro", a data do
    // computador foi mexida para burlar o vencimento.
    final prefs = await SharedPreferences.getInstance();
    final ultimaStr = prefs.getString(_chaveUltimaVerificacao);
    final agora = DateTime.now().toUtc();
    final ultima = ultimaStr != null ? DateTime.tryParse(ultimaStr)?.toUtc() : null;
    if (ultima != null && agora.isBefore(ultima.subtract(const Duration(minutes: 5)))) {
      return const ResultadoLicencaInstalacao(
        estado: EstadoLicencaInstalacao.relogioAlterado,
        mensagem:
            'A data do computador está atrasada em relação à última execução. Ajuste o relógio para continuar.',
      );
    }

    // Registra a verificação SEMPRE (inclusive vencida): é o que impede que
    // atrasar o relógio "ressuscite" uma licença vencida.
    await _registrarVerificacao(prefs, agora, ultima);

    final doc = await _lerDocumento();
    // Código curto de contingência: vale quando a nuvem não respondeu.
    final codigoOffline = await _lerCodigoOffline();

    if (doc == null) {
      if (codigoOffline != null) {
        return ResultadoLicencaInstalacao(
          estado: EstadoLicencaInstalacao.valida,
          licenca: codigoOffline,
        );
      }
      return ResultadoLicencaInstalacao(
        estado: _ultimoArquivoEncontrado
            ? EstadoLicencaInstalacao.invalida
            : EstadoLicencaInstalacao.ausente,
        mensagem: _ultimoArquivoEncontrado
            ? 'A licença deste computador não é válida. Ative ou renove para continuar.'
            : 'Este computador ainda não foi ativado.',
      );
    }

    if (doc.licenca.maquinaId != maquinaAtual) {
      if (codigoOffline != null) {
        return ResultadoLicencaInstalacao(
          estado: EstadoLicencaInstalacao.valida,
          licenca: codigoOffline,
        );
      }
      return const ResultadoLicencaInstalacao(
        estado: EstadoLicencaInstalacao.outraMaquina,
        mensagem:
            'Esta licença pertence a outro computador. Cada instalação precisa da própria licença.',
      );
    }

    if (doc.licenca.expirada) {
      if (codigoOffline != null) {
        return ResultadoLicencaInstalacao(
          estado: EstadoLicencaInstalacao.valida,
          licenca: codigoOffline,
        );
      }
      return ResultadoLicencaInstalacao(
        estado: EstadoLicencaInstalacao.expirada,
        licenca: doc.licenca,
        mensagem:
            'A licença de instalação venceu. Renove a mensalidade para liberar o sistema.',
      );
    }

    return ResultadoLicencaInstalacao(
      estado: EstadoLicencaInstalacao.valida,
      licenca: doc.licenca,
    );
  }

  static Future<void> _registrarVerificacao(
    SharedPreferences prefs,
    DateTime agora,
    DateTime? ultima,
  ) async {
    // Nunca anda para trás: guarda o maior instante já visto. Assim, voltar a
    // data do computador é detectado na próxima abertura.
    if (ultima != null && !agora.isAfter(ultima)) return;
    try {
      await prefs.setString(_chaveUltimaVerificacao, agora.toIso8601String());
    } catch (e) {
      debugPrint('>>> [LicencaInstalacao] Não registrou verificação: $e');
    }
  }

  /// Ativa este computador na nuvem e guarda a licença de 30 dias.
  ///
  /// [codigoAtivacao] é o código de venda (uso único): sem ele a ativação de
  /// um computador novo não é liberada, então uma cópia do setup entregue a
  /// outra pessoa não ativa.
  static Future<RespostaLicencaInstalacao> ativar({
    required String codigoAtivacao,
  }) {
    // Código curto de contingência: libera sem falar com a nuvem.
    if (_corpoCodigoOffline(codigoAtivacao) != null) {
      return aplicarCodigoOffline(codigoAtivacao);
    }
    return _chamarNuvem('ativar', codigoAtivacao: codigoAtivacao);
  }

  /// Ativa este computador SEM internet, a partir do documento JSON assinado
  /// pelo painel local do suporte (`tools/licencas/painel_emergencia.js`).
  ///
  /// É contingência: a licença offline não consulta mensalidade nem código de
  /// venda. Quem assina é a chave privada do suporte, e o prazo continua
  /// limitado a 30 dias pelo validador.
  static Future<RespostaLicencaInstalacao> ativarOffline(
    String documentoJson,
  ) async {
    // O mesmo campo aceita o código curto EXO-OFF-... além do JSON assinado.
    if (_corpoCodigoOffline(documentoJson) != null) {
      return aplicarCodigoOffline(documentoJson);
    }

    final texto = documentoJson.trim();
    if (texto.isEmpty) {
      return const RespostaLicencaInstalacao(
        ok: false,
        mensagem: 'Cole o conteúdo do arquivo de licença enviado pelo suporte.',
      );
    }

    final doc = _decodificar(texto);
    if (doc == null) {
      return const RespostaLicencaInstalacao(
        ok: false,
        mensagem:
            'Licença offline inválida. Confira se copiou o arquivo JSON inteiro.',
      );
    }

    final maquinaAtual = await identificadorMaquina();
    if (doc.licenca.maquinaId != maquinaAtual) {
      return const RespostaLicencaInstalacao(
        ok: false,
        mensagem: 'Esta licença offline foi emitida para outro computador.',
      );
    }
    if (doc.licenca.expirada) {
      return const RespostaLicencaInstalacao(
        ok: false,
        mensagem: 'Esta licença offline já venceu. Peça uma nova ao suporte.',
      );
    }

    final decodificado = jsonDecode(texto);
    if (decodificado is! Map) {
      return const RespostaLicencaInstalacao(
        ok: false,
        mensagem: 'Licença offline inválida.',
      );
    }
    await _salvarDocumento(Map<String, dynamic>.from(decodificado));

    return RespostaLicencaInstalacao(
      ok: true,
      mensagem:
          'Licença offline aplicada até ${_formatarData(doc.licenca.expiraEm)}.',
    );
  }

  /// Pede +30 dias. A nuvem só libera com a mensalidade da competência paga.
  static Future<RespostaLicencaInstalacao> renovar() =>
      _chamarNuvem('renovar');

  /// Liga este computador à empresa logada (usado na renovação, para a nuvem
  /// conferir o pagamento da empresa certa). Falha em silêncio: não pode
  /// atrapalhar o uso do sistema.
  static String? _empresaVinculada;
  static final Set<String> _vinculando = <String>{};

  static Future<void> vincularEmpresa(String empresaId) async {
    final id = empresaId.trim();
    if (kIsWeb || id.isEmpty) return;
    // Chamado no build do AuthWrapper: só vale uma vez por empresa na sessão.
    if (_empresaVinculada == id || _vinculando.contains(id)) return;

    _vinculando.add(id);
    try {
      final resultado = await verificar();
      if (!resultado.podeUsar) return;
      final resposta = await _post({'action': 'vincular', 'empresa_id': id});
      if (resposta.statusCode >= 200 && resposta.statusCode < 300) {
        _empresaVinculada = id;
      }
    } catch (e) {
      debugPrint('>>> [LicencaInstalacao] Não foi possível vincular empresa: $e');
    } finally {
      _vinculando.remove(id);
    }
  }

  static Future<RespostaLicencaInstalacao> _chamarNuvem(
    String acao, {
    String? codigoAtivacao,
  }) async {
    try {
      final machineId = await identificadorMaquina();
      final machineName = kIsWeb ? '' : Platform.localHostname;
      final resposta = await _post({
        'action': acao,
        'machine_id': machineId,
        'machine_name': machineName,
        if (codigoAtivacao != null && codigoAtivacao.trim().isNotEmpty)
          'codigo_ativacao': codigoAtivacao.trim(),
      });

      final status = resposta.statusCode;
      final corpo = resposta.corpo;

      if (status >= 200 && status < 300) {
        final documento = corpo['documento'];
        if (documento is! Map) {
          return const RespostaLicencaInstalacao(
            ok: false,
            mensagem: 'A nuvem respondeu sem a licença. Tente novamente.',
          );
        }
        await _salvarDocumento(Map<String, dynamic>.from(documento));

        final licenca = _decodificar(jsonEncode(documento))?.licenca;
        if (licenca == null) {
          return const RespostaLicencaInstalacao(
            ok: false,
            mensagem: 'A licença recebida não pôde ser validada.',
          );
        }
        return RespostaLicencaInstalacao(
          ok: true,
          mensagem: acao == 'renovar'
              ? 'Licença renovada até ${_formatarData(licenca.expiraEm)}.'
              : 'Computador ativado até ${_formatarData(licenca.expiraEm)}.',
        );
      }

      return RespostaLicencaInstalacao(
        ok: false,
        mensagem: (corpo['erro'] ?? 'Não foi possível liberar a licença.')
            .toString(),
        codigo: corpo['codigo']?.toString(),
      );
    } catch (e) {
      debugPrint('>>> [LicencaInstalacao] Falha ao falar com a nuvem: $e');
      return const RespostaLicencaInstalacao(
        ok: false,
        mensagem:
            'Sem conexão com a nuvem de licenças. Verifique a internet e tente novamente.',
      );
    }
  }

  static Future<_RespostaHttp> _post(Map<String, dynamic> corpo) async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };
    final anon = EnvConfig.env['SUPABASE_ANON_KEY']?.trim() ?? '';
    if (anon.isNotEmpty) {
      headers['apikey'] = anon;
      headers['Authorization'] = 'Bearer $anon';
    }
    final chaveSetup = EnvConfig.env['EXODO_LICENSE_SETUP_KEY']?.trim() ?? '';
    if (chaveSetup.isNotEmpty) {
      headers['x-exodo-setup-key'] = chaveSetup;
    }

    final corpoJson = jsonEncode(corpo);
    final urls = _urls();

    Object? ultimoErro;
    for (var i = 0; i < urls.length; i++) {
      final url = urls[i];
      try {
        final resposta = await _postEm(url, corpoJson, headers);
        // 404 = a função não existe NESTE endereço: vale tentar o próximo.
        if (resposta.statusCode == 404 && i < urls.length - 1) {
          debugPrint('>>> [LicencaInstalacao] Função ausente em $url; '
              'tentando o próximo endereço.');
          continue;
        }
        return resposta;
      } catch (e) {
        ultimoErro = e;
        debugPrint('>>> [LicencaInstalacao] $url não respondeu: $e');
      }
    }

    throw ultimoErro ??
        Exception('Nenhum endereço da nuvem de licenças respondeu.');
  }

  static Future<_RespostaHttp> _postEm(
    Uri url,
    String corpoJson,
    Map<String, String> headers,
  ) async {
    final resposta = await _client
        .post(url, headers: headers, body: corpoJson)
        .timeout(const Duration(seconds: 20));

    Map<String, dynamic> json = const {};
    try {
      final decoded = jsonDecode(resposta.body);
      if (decoded is Map) json = Map<String, dynamic>.from(decoded);
    } catch (_) {}

    return _RespostaHttp(statusCode: resposta.statusCode, corpo: json);
  }

  /// Endereços da função de licenciamento, na ordem em que serão tentados.
  ///
  /// Uma instalação feita com o `.env` antigo traz `SUPABASE_URL` apontando
  /// para o projeto Supabase que foi desativado (`febffvlpvxtiihvnfuts`):
  /// hoje esse domínio nem resolve, e a chamada caía no aviso "Sem conexão
  /// com a nuvem de licenças" mesmo com internet funcionando. Por isso o app
  /// percorre os endereços e usa o primeiro que responder, deixando a nuvem
  /// atual (Funnel, o mesmo endereço do resto do sistema) como alternativa
  /// final. `EXODO_LICENSE_URL` permite fixar o endereço da licença.
  static List<Uri> _urls() {
    const sufixo = '/functions/v1/licenca-instalacao';
    const padrao = 'https://exodosystems.tail9b4943.ts.net$sufixo';

    final urls = <Uri>[];
    final vistos = <String>{};

    void adicionar(String? valor) {
      var base = (valor ?? '').trim().replaceAll(RegExp(r'/+$'), '');
      if (base.isEmpty) return;
      // Aceita tanto a raiz da nuvem quanto uma URL de outra função.
      base = base
          .replaceFirst(RegExp(r'/functions/v1/[^/]+$'), '')
          .replaceAll(RegExp(r'/+$'), '');
      final url = '$base$sufixo';
      if (vistos.add(url)) urls.add(Uri.parse(url));
    }

    adicionar(EnvConfig.env['EXODO_LICENSE_URL']);
    adicionar(EnvConfig.env['SUPABASE_URL']);
    adicionar(EnvConfig.env['SUPABASE_FUNCTIONS_URL']);
    adicionar(padrao);
    return urls;
  }

  static Future<void> _salvarDocumento(Map<String, dynamic> documento) async {
    final texto = const JsonEncoder.withIndent('  ').convert(documento);
    final pastas = await _pastas();
    for (final pasta in pastas) {
      try {
        await pasta.create(recursive: true);
        final arquivo = File(p.join(pasta.path, nomeArquivo));
        await arquivo.writeAsString(texto, flush: true);
        return;
      } catch (e) {
        debugPrint('>>> [LicencaInstalacao] Não gravou em ${pasta.path}: $e');
      }
    }
    throw Exception('Não foi possível gravar a licença neste computador.');
  }

  static String _formatarData(DateTime data) {
    final local = data.toLocal();
    String dois(int valor) => valor.toString().padLeft(2, '0');
    return '${dois(local.day)}/${dois(local.month)}/${local.year}';
  }
}

class _Documento {
  final LicencaInstalacao licenca;
  const _Documento({required this.licenca});
}

class _RespostaHttp {
  final int statusCode;
  final Map<String, dynamic> corpo;
  const _RespostaHttp({required this.statusCode, required this.corpo});
}
