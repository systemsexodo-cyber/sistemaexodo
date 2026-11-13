import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/produto.dart';
import 'local_storage_service.dart';
import 'process_utils.dart';

class BalancaService {
  static final BalancaService _instance = BalancaService._internal();
  factory BalancaService() => _instance;
  BalancaService._internal();

  static const String _keyBalancaConfig = 'exodo_balanca_config';
  final LocalStorageService _storage = LocalStorageService();

  // Configurações Padrão
  final Map<String, dynamic> _configPadrao = {
    'ativo': false,
    'porta': 'COM1',
    'baudRate': 9600,
    'dataBits': 8,
    'paridade': 'None', // None, Even, Odd, Mark, Space
    'stopBits': 1,
    // Protocolo de pesagem: como a balança responde pela serial.
    //   auto     = pede o peso (ENQ) e reconhece todos os quadros abaixo;
    //   prt2     = Toledo PRT2: [STX][PPPPP][ETX], 5 dígitos sem separador,
    //              não transmite com a balança em zero;
    //   prt3     = Toledo PRT3: igual ao PRT2, mas marca instável/negativo/
    //              sobrecarga com [STX][IIIII|NNNNN|SSSSS][ETX];
    //   toledo_a = Toledo Protocolo A (porta de impressão dos Prix II/III):
    //              [STX][status][peso 6][status2][tara 6][unidade 6][CR][CS];
    //   filizola = Filizola: [STX][PPPPP][ETX];
    //   generico = balança que já manda o peso em texto ("1,540 kg"),
    //              sem pedido (envio contínuo).
    'protocolo': 'auto',
    // Casas decimais do campo quando a balança manda só dígitos (gramas):
    // 1540 com 3 casas = 1,540 kg.
    'casasDecimais': 3,
    // Quanto tempo esperar o quadro de peso depois do pedido (ms).
    'tempoLeituraMs': 1200,
    // ENQ (0x05) é o "manda o peso" das balanças Toledo e Filizola. Sem ele
    // essas balanças não respondem nada e a leitura volta vazia/lixo.
    'enviarEnq': true,
    // DTR/RTS ligados: várias balanças USB-serial só transmitem com os dois
    // sinais ativos.
    'dtrRts': true,
    // Simulador DESLIGADO por padrão: o peso fictício só aparece quando
    // alguém liga "Modo Simulador" de propósito. Com isso uma configuração
    // ausente/ilegível nunca faz o PDV devolver peso inventado no lugar da
    // balança física.
    'usarMock': false,
    'pesoMock': 1.500,
    'diretorioToledo': '',
    'deptoToledo': '01',
    'validadeToledoDias': 0,
  };

  /// Carrega as configurações da balança
  Future<Map<String, dynamic>> obterConfiguracao() async {
    try {
      final configSalva = await _storage.carregar(_keyBalancaConfig);
      if (configSalva != null && configSalva is Map) {
        // Fazer merge das chaves para garantir compatibilidade
        final Map<String, dynamic> config = {};
        _configPadrao.forEach((key, value) {
          config[key] = configSalva.containsKey(key) ? configSalva[key] : value;
        });
        return config;
      }
    } catch (e) {
      debugPrint('Erro ao obter configuração da balança: $e');
    }
    return Map<String, dynamic>.from(_configPadrao);
  }

  /// Salva as configurações da balança.
  ///
  /// Relê o que ficou gravado e devolve `false` quando o valor não pegou —
  /// assim o PDV avisa o operador em vez de anunciar "salvo" e continuar
  /// devolvendo o peso simulado na pesagem seguinte.
  Future<bool> salvarConfiguracao(Map<String, dynamic> novaConfig) async {
    try {
      await _storage.salvar(_keyBalancaConfig, novaConfig);
      final lido = await _storage.carregar(_keyBalancaConfig);
      final gravou =
          lido is Map &&
          (lido['usarMock'] == true) == (novaConfig['usarMock'] == true) &&
          (lido['ativo'] == true) == (novaConfig['ativo'] == true);
      if (!gravou) {
        debugPrint(
          'Configuração da balança NÃO gravou. '
          'Enviado: $novaConfig | Lido: $lido',
        );
        return false;
      }
      debugPrint('Configuração da balança salva com sucesso: $novaConfig');
      return true;
    } catch (e) {
      debugPrint('Erro ao salvar configuração da balança: $e');
      return false;
    }
  }

  /// Obtém o diretório padrão para exportar os itens do Toledo (geralmente área de trabalho)
  Future<String> obterDiretorioToledoPadrao() async {
    // No navegador não existe diretório local/Platform: retorna vazio para o
    // diálogo de configurações abrir normalmente.
    if (kIsWeb) return '';
    try {
      if (Platform.isWindows) {
        final home = Platform.environment['USERPROFILE'];
        if (home != null) {
          final desktop = p.join(home, 'Desktop');
          if (await Directory(desktop).exists()) {
            return desktop;
          }
        }
      }
      final appDir = await getApplicationDocumentsDirectory();
      return appDir.path;
    } catch (e) {
      return '';
    }
  }

  /// Lista as portas COM disponíveis no Windows usando PowerShell
  Future<List<String>> listarPortasCOM() async {
    final List<String> portas = [];
    // kIsWeb ANTES de Platform: no Flutter Web, acessar Platform lança
    // "Unsupported operation" e travava o diálogo de configurações do PDV.
    if (kIsWeb || !Platform.isWindows) {
      return ['MOCK_PORT'];
    }
    try {
      // Executa comando powershell para listar as portas seriais registradas
      final result = await runProcessHidden(
        'powershell',
        ['-NoProfile', '-Command', '[System.IO.Ports.SerialPort]::getportnames()'],
      );

      if (result.exitCode == 0) {
        final lines = result.stdout.toString().split('\n');
        for (var line in lines) {
          final clean = line.trim();
          if (clean.isNotEmpty && !portas.contains(clean)) {
            portas.add(clean);
          }
        }
      }
    } catch (e) {
      debugPrint('Erro ao listar portas COM via PowerShell: $e');
    }

    // Se nenhuma porta foi encontrada ou deu erro, retorna lista básica
    if (portas.isEmpty) {
      portas.addAll(['COM1', 'COM2', 'COM3', 'COM4', 'COM5']);
    }
    return portas;
  }

  /// Lê o peso da balança.
  ///
  /// Retorna um Map contendo:
  /// - 'peso': double (peso lido, em kg)
  /// - 'simulado': bool (se o peso é fictício/mocked)
  /// - 'erro': String? (mensagem de erro caso ocorra)
  /// - 'bruto': String (quadro recebido em hexadecimal — só para diagnóstico)
  /// - 'ms': int (quanto a leitura levou, em milissegundos)
  ///
  /// O protocolo de pesagem é respeitado: nas Toledo/Filizola é enviado o ENQ
  /// (0x05) e o quadro STX…ETX é lido em BYTES (não como texto), porque essas
  /// balanças falam em gramas e não devolvem quebra de linha — ler como texto
  /// devolvia lixo ("sem quadro válido").
  Future<Map<String, dynamic>> lerPeso() async {
    final config = await obterConfiguracao();
    // Só simula com pedido explícito (true salvo). Qualquer outro valor cai
    // na leitura real da porta serial.
    final bool usarMock = config['usarMock'] == true;
    final double pesoMock = (config['pesoMock'] ?? 1.500).toDouble();
    final String porta = (config['porta'] ?? 'COM1').toString();
    final int baudRate = (config['baudRate'] as num?)?.toInt() ?? 9600;
    final String protocolo = _protocoloNormalizado(
      (config['protocolo'] ?? 'auto').toString(),
    );
    final int casasDecimais = (config['casasDecimais'] as num?)?.toInt() ?? 3;
    final int tempoLeituraMs =
        (config['tempoLeituraMs'] as num?)?.toInt() ?? 1200;
    final String paridade = (config['paridade'] ?? 'None').toString();
    final int dataBits = (config['dataBits'] as num?)?.toInt() ?? 8;
    final int stopBitsQtde = (config['stopBits'] as num?)?.toInt() ?? 1;
    // Sem ENQ a balança não manda nada; no modo "genérico" (envio contínuo)
    // o pedido atrapalha.
    final bool enviarEnq =
        config['enviarEnq'] != false && protocolo != 'generico';
    final bool dtrRts = config['dtrRts'] != false;

    if (usarMock) {
      // Simula um atraso pequeno para simular comunicação de verdade
      await Future.delayed(const Duration(milliseconds: 300));
      return {
        'peso': pesoMock,
        'simulado': true,
        'erro': null,
        'ms': 300,
      };
    }

    // Com o simulador desligado, NUNCA devolvemos o peso fictício: se não for
    // possível ler a balança, o peso fica 0 e o erro é informado.
    // (No Web `Platform` lança Unsupported operation, por isso a checagem antes.)
    if (kIsWeb || !Platform.isWindows) {
      return {
        'peso': 0.0,
        'simulado': false,
        'erro': 'Leitura de balança serial disponível apenas no aplicativo desktop (Windows).',
      };
    }

    final paridadePs = _paridadePowerShell(paridade);
    final stopBitsPs = stopBitsQtde >= 2 ? 'Two' : 'One';
    final enviar = enviarEnq ? '1' : '0';
    final usarDtr = dtrRts ? '1' : '0';

    try {
      // Um único PowerShell: abre a porta, pede o peso, lê o QUADRO em bytes
      // e fecha. Nada de ReadLine (as balanças não mandam \r\n) nem de sleep
      // fixo — assim a leitura termina no ETX e volta em ~1s.
      final script = '''
\$ErrorActionPreference = 'Stop'
\$port = New-Object System.IO.Ports.SerialPort '$porta', $baudRate, '$paridadePs', $dataBits, '$stopBitsPs'
\$port.Handshake = 'None'
\$port.ReadTimeout = 60
\$port.WriteTimeout = 500
if ('$usarDtr' -eq '1') { \$port.DtrEnable = \$true; \$port.RtsEnable = \$true }
try {
    \$port.Open()
    \$port.DiscardInBuffer()
    if ('$enviar' -eq '1') { \$port.Write([char]5) }
    \$bytes = New-Object System.Collections.Generic.List[byte]
    \$limite = [DateTime]::UtcNow.AddMilliseconds($tempoLeituraMs)
    while ([DateTime]::UtcNow -lt \$limite) {
        try {
            \$b = \$port.ReadByte()
        } catch [System.TimeoutException] {
            if (\$bytes.Count -gt 0) { break }
            continue
        }
        if (\$b -lt 0) { break }
        \$bytes.Add([byte]\$b)
        if (\$b -eq 3 -or \$b -eq 13 -or \$b -eq 10) { break }
        if (\$bytes.Count -ge 40) { break }
    }
    if (\$bytes.Count -eq 0) {
        Write-Output 'VAZIO'
    } else {
        \$hex = (\$bytes | ForEach-Object { \$_.ToString('X2') }) -join ' '
        \$txt = [System.Text.Encoding]::GetEncoding(28591).GetString(\$bytes.ToArray())
        Write-Output ('HEX=' + \$hex)
        Write-Output ('TXT=' + \$txt)
    }
} catch {
    Write-Output ('ERRO=' + \$_.Exception.Message)
} finally {
    if (\$port.IsOpen) { \$port.Close() }
    \$port.Dispose()
}
''';

      final inicio = DateTime.now();
      final result = await runProcessHidden(
        'powershell',
        ['-NoProfile', '-NonInteractive', '-Command', script],
      );
      final duracaoMs = DateTime.now().difference(inicio).inMilliseconds;
      final saida = result.stdout.toString().trim();
      debugPrint(
        '>>> [Balanca] $porta ($protocolo, $baudRate) em ${duracaoMs}ms: $saida',
      );

      final erroPorta = _valorDaSaida(saida, 'ERRO=');
      if (erroPorta != null && erroPorta.isNotEmpty) {
        return {
          'peso': 0.0,
          'simulado': false,
          'ms': duracaoMs,
          'erro': 'Falha ao acessar a porta $porta: $erroPorta',
        };
      }

      if (result.exitCode != 0) {
        final erroStr = result.stderr.toString().trim();
        return {
          'peso': 0.0,
          'simulado': false,
          'ms': duracaoMs,
          'erro': 'Falha ao acessar a porta $porta: '
              '${erroStr.isEmpty ? 'código ${result.exitCode}' : erroStr}',
        };
      }

      final hex = _valorDaSaida(saida, 'HEX=') ?? '';
      final txt = _valorDaSaida(saida, 'TXT=') ?? '';

      if (saida.contains('VAZIO') || (hex.isEmpty && txt.isEmpty)) {
        // PRT2 não transmite nada com a balança em zero: a leitura vazia é
        // normal nesse caso e o operador precisa saber disso.
        final dica = protocolo == 'prt2'
            ? ' O protocolo PRT2 não transmite com a balança em zero: coloque '
                'o produto na plataforma e leia de novo.'
            : '';
        return {
          'peso': 0.0,
          'simulado': false,
          'ms': duracaoMs,
          'erro': 'Sem resposta da balança em $porta (${duracaoMs}ms). '
              'Confira se está ligada, o cabo/porta, a velocidade $baudRate e o '
              'protocolo ($protocolo).$dica',
        };
      }

      final bytes = _bytesDoQuadro(
        hex.isNotEmpty ? _bytesDoHex(hex) : latin1.encode(txt),
      );
      final leitura = _interpretarQuadro(
        bytes: bytes,
        protocolo: protocolo,
        casasDecimais: casasDecimais,
      );

      if (leitura.aviso != null) {
        return {
          'peso': 0.0,
          'simulado': false,
          'ms': duracaoMs,
          'bruto': hex,
          'erro': leitura.aviso,
        };
      }

      final peso = leitura.peso;
      if (peso == null) {
        return {
          'peso': 0.0,
          'simulado': false,
          'ms': duracaoMs,
          'bruto': hex,
          'erro': 'Peso ilegível no protocolo $protocolo (quadro: '
              '${hex.isEmpty ? txt : hex}). Troque o protocolo de pesagem se '
              'não for o da sua balança.',
        };
      }

      if (peso <= 0) {
        return {
          'peso': 0.0,
          'simulado': false,
          'ms': duracaoMs,
          'bruto': hex,
          'erro': 'A balança respondeu 0,000 kg. Coloque o produto na plataforma e leia de novo.',
        };
      }

      return {
        'peso': peso,
        'simulado': false,
        'ms': duracaoMs,
        'bruto': hex,
        'erro': null,
      };
    } catch (e) {
      return {
        'peso': 0.0,
        'simulado': false,
        'erro': 'Erro de comunicação na porta $porta: $e',
      };
    }
  }

  /// Extrai o valor de uma linha da saída do script ("HEX=02 30 30 ...").
  String? _valorDaSaida(String saida, String prefixo) {
    for (final linha in saida.split(RegExp(r'\r?\n'))) {
      if (linha.startsWith(prefixo)) {
        return linha.substring(prefixo.length).trim();
      }
    }
    return null;
  }

  /// Nome da paridade no formato que o .NET espera.
  String _paridadePowerShell(String paridade) {
    switch (paridade.trim().toLowerCase()) {
      case 'even':
      case 'par':
      case 'paridade par':
        return 'Even';
      case 'odd':
      case 'impar':
      case 'ímpar':
        return 'Odd';
      case 'mark':
        return 'Mark';
      case 'space':
        return 'Space';
      default:
        return 'None';
    }
  }

  /// Nome canônico do protocolo de pesagem.
  ///
  /// Aceita nomes antigos/variações ("toledo", "toledo_prt3"...) para uma
  /// configuração já gravada continuar valendo depois da atualização.
  String _protocoloNormalizado(String valor) {
    switch (valor.trim().toLowerCase()) {
      case 'prt2':
      case 'toledo_prt2':
      case 'toledo2':
        return 'prt2';
      case 'prt3':
      case 'toledo':
      case 'toledo_prt3':
      case 'toledo3':
        return 'prt3';
      case 'toledo_a':
      case 'toledoa':
      case 'protocolo_a':
        return 'toledo_a';
      case 'filizola':
        return 'filizola';
      case 'generico':
      case 'genérico':
        return 'generico';
      default:
        return 'auto';
    }
  }

  /// Recorta o quadro entre STX (0x02) e ETX (0x03) — a moldura que as
  /// balanças Toledo e Filizola usam. Sem STX, devolve os bytes como vieram.
  List<int> _bytesDoQuadro(List<int> bytes) {
    final inicio = bytes.indexOf(0x02);
    if (inicio < 0) return bytes;
    final fim = bytes.indexOf(0x03, inicio + 1);
    return bytes.sublist(inicio + 1, fim < 0 ? bytes.length : fim);
  }

  /// Interpreta o quadro já sem STX/ETX e devolve o peso em kg.
  ///
  /// Cada protocolo tem seu formato:
  ///  - **PRT2 / PRT3 / Filizola**: só o peso, 5 caracteres ASCII sem separador
  ///    ("01540" = 1,540 kg). No PRT3 o quadro pode vir como `IIIII` (instável),
  ///    `NNNNN` (negativo) ou `SSSSS` (sobrecarga).
  ///  - **Toledo Protocolo A**: status(1) + peso(6) + status2(1) + tara(6) +
  ///    unidade(6) + CR + checksum. O peso é o PRIMEIRO campo — pegar o maior
  ///    número do quadro pegaria a TARA, que é o que acontecia antes.
  ///  - **Genérico**: texto com separador ("1,540 kg").
  _LeituraPeso _interpretarQuadro({
    required List<int> bytes,
    required String protocolo,
    required int casasDecimais,
  }) {
    final conteudo = latin1.decode(bytes, allowInvalid: true);
    final semEspacos = conteudo.replaceAll(RegExp(r'\s'), '');

    // Quadros de estado do PRT3: não são peso, são avisos da balança.
    if (semEspacos.length >= 3) {
      if (RegExp(r'^I+$').hasMatch(semEspacos)) {
        return const _LeituraPeso(
          aviso: 'Peso instável: espere a balança parar e leia de novo.',
        );
      }
      if (RegExp(r'^N+$').hasMatch(semEspacos)) {
        return const _LeituraPeso(
          aviso: 'A balança está com peso negativo. Zere a balança e leia de novo.',
        );
      }
      if (RegExp(r'^S+$').hasMatch(semEspacos)) {
        return const _LeituraPeso(
          aviso: 'Peso acima da capacidade da balança.',
        );
      }
    }

    // Protocolo A (impressão dos Prix II/III): campo de peso de 6 dígitos
    // logo depois do byte de status, e depois a TARA (que NÃO é o peso).
    if (protocolo == 'toledo_a' ||
        (protocolo == 'auto' && _pareceProtocoloA(conteudo))) {
      final peso = _campoNumerico(conteudo, inicio: 1, tamanho: 6);
      if (peso != null) {
        return _LeituraPeso(
          peso: _pesoSaneado(peso / math.pow(10, casasDecimais)),
        );
      }
    }

    // Texto com separador decimal (genérico / Prix Rebanho / impressão): o
    // peso já vem em kg, então NÃO se divide por 1000.
    final comSeparador = RegExp(r'\d+[.,]\d+').allMatches(conteudo).toList();
    if (comSeparador.isNotEmpty) {
      final valor = double.tryParse(
        comSeparador.first.group(0)!.replaceAll(',', '.'),
      );
      if (valor != null) return _LeituraPeso(peso: _pesoSaneado(valor));
    }

    // PRT2 / PRT3 / Filizola: dígitos puros em gramas.
    final digitos = semEspacos.replaceAll(RegExp(r'[^0-9]'), '');
    if (digitos.isNotEmpty) {
      final inteiro = int.tryParse(digitos);
      if (inteiro != null) {
        return _LeituraPeso(
          peso: _pesoSaneado(inteiro / math.pow(10, casasDecimais)),
        );
      }
    }

    return const _LeituraPeso();
  }

  /// O quadro tem cara de Protocolo A (peso e tara de 6 dígitos)?
  bool _pareceProtocoloA(String conteudo) {
    if (conteudo.length < 14) return false;
    final peso = _campoNumerico(conteudo, inicio: 1, tamanho: 6);
    final tara = _campoNumerico(conteudo, inicio: 8, tamanho: 6);
    return peso != null && tara != null;
  }

  /// Lê um campo numérico de tamanho fixo, tolerando espaços de alinhamento.
  int? _campoNumerico(String texto, {required int inicio, required int tamanho}) {
    if (texto.length < inicio + tamanho) return null;
    final campo = texto.substring(inicio, inicio + tamanho).trim();
    if (campo.isEmpty || !RegExp(r'^\d+$').hasMatch(campo)) return null;
    return int.tryParse(campo);
  }

  /// Rejeita valores impossíveis — sinal de quadro lido no meio ou de
  /// status/tara interpretados como peso.
  double? _pesoSaneado(double valor) {
    if (!valor.isFinite || valor < 0 || valor > 999) return null;
    return double.parse(valor.toStringAsFixed(3));
  }

  /// Bytes do quadro em hexadecimal ("02 30 30 31 ...").
  List<int> _bytesDoHex(String hex) {
    final bytes = <int>[];
    for (final parte in hex.split(RegExp(r'\s+'))) {
      final valor = int.tryParse(parte, radix: 16);
      if (valor != null && valor >= 0 && valor <= 255) bytes.add(valor);
    }
    return bytes;
  }

  /// Gera e exporta o arquivo de itens compatível com Balanças Toledo (Layout MGV)
  /// Retorna o caminho do arquivo gerado
  Future<String> exportarItensToledo(List<Produto> produtos, String diretorioDestino) async {
    // Escrita de arquivo não existe no navegador. O botão correspondente fica
    // desabilitado no Web; esta guarda protege chamadas diretas.
    if (kIsWeb) {
      throw UnsupportedError(
        'Exportação de itens Toledo disponível apenas no aplicativo desktop.',
      );
    }
    if (diretorioDestino.isEmpty) {
      diretorioDestino = await obterDiretorioToledoPadrao();
    }

    final config = await obterConfiguracao();
    final depto = (config['deptoToledo'] ?? '01').toString().padLeft(2, '0');
    final validadeDias = int.tryParse(config['validadeToledoDias']?.toString() ?? '0') ?? 0;

    // Garante que o diretório existe
    final dir = Directory(diretorioDestino);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final file = File(p.join(diretorioDestino, 'txtitens.txt'));
    final List<String> linhas = [];

    for (var prod in produtos) {
      if (!prod.enviaBalanca) continue;

      // Toledo MGV5/MGV6 layout padrão fixo de texto:
      // Campo 1: Departamento (2 caracteres) - Padrão '01'
      final txtDepto = depto;

      // Campo 2: Tipo de item (1 caractere) - '0' para peso (KG), '1' para unidade (UN)
      final unidadesPeso = ['KG', 'KILO', 'KILOS', 'KILOGRAMA', 'G', 'GR', 'GRAMAS'];
      final isPeso = unidadesPeso.contains(prod.unidade.trim().toUpperCase());
      final txtTipo = isPeso ? '0' : '1';

      // Campo 3: Código do produto (6 caracteres) - Zero padded
      // Toledo aceita até 6 dígitos. Ex: '000123'
      final codigoNumerico = _extrairNumerosDoCodigo(prod.codigo ?? '');
      final txtCodigo = codigoNumerico.padLeft(6, '0').substring(0, 6);

      // Campo 4: Preço unitário (6 caracteres) - Sem decimal, zero padded. Ex: R$ 12.50 -> '001250'
      final precoCentavos = (prod.precoAtual * 100).round();
      final txtPreco = precoCentavos.toString().padLeft(6, '0');
      // Trunca se exceder
      final txtPrecoFinal = txtPreco.length > 6 ? txtPreco.substring(txtPreco.length - 6) : txtPreco;

      // Campo 5: Validade do produto em dias (3 caracteres) - Zero padded. Ex: 0 dias -> '000'
      final txtValidade = validadeDias.toString().padLeft(3, '0');

      // Campo 6: Descrição do produto (25 caracteres) - Alinhado à esquerda, preenchido com espaços
      String nomeClean = _removerAcentos(prod.nome);
      if (nomeClean.length > 25) {
        nomeClean = nomeClean.substring(0, 25);
      }
      final txtDescricao = nomeClean.padRight(25, ' ');

      // Adicionando informações extras para compatibilidade com MGV (total de 117 caracteres por linha padrão)
      // MGV aceita campos opcionais como descrição extra, info nutricional, etc.
      // O resto da linha preenchemos com espaços vazios até fechar 117 caracteres.
      final linha = '$txtDepto$txtTipo$txtCodigo$txtPrecoFinal$txtValidade$txtDescricao'.padRight(117, ' ');
      linhas.add(linha);
    }

    // Grava no arquivo itens.txt usando codificação ISO-8859-1 (Latin1) para suportar acentuação no terminal Toledo
    await file.writeAsString(linhas.join('\r\n'), encoding: latin1);

    return file.path;
  }

  /// Remove caracteres especiais e acentos da string para enviar para a balança
  String _removerAcentos(String str) {
    const comAcentos = 'ÄÅÁÂÀÃÄÅÇÉÊÈËÍÎÌÏÑÓÔÒÕÖØÚÛÙÜÝäåáâàãäåçéêèëíîìïñóôòõöøúûùüýÿ';
    const semAcentos = 'AAAAAAACEEEEIIIINOOOOOOUUUUYaaaaaaaceeeeiiiinoooooouuuuyy';

    String novaStr = str;
    for (int i = 0; i < comAcentos.length; i++) {
      novaStr = novaStr.replaceAll(comAcentos[i], semAcentos[i]);
    }

    // Remove qualquer outro caractere que não seja letra, número, espaço ou pontuação básica
    return novaStr.replaceAll(RegExp(r'[^\w\s.,\-/%]'), '');
  }

  /// Extrai apenas a parte numérica do código do produto
  String _extrairNumerosDoCodigo(String codigo) {
    final digitos = codigo.replaceAll(RegExp(r'[^0-9]'), '');
    if (digitos.isEmpty) {
      // Se não tiver números, gera um baseado no hash da string para não enviar vazio
      return (codigo.hashCode % 999999).abs().toString();
    }
    return digitos;
  }
}

/// O que um quadro da balança virou depois de interpretado.
class _LeituraPeso {
  /// Peso em kg (null quando o quadro não trouxe peso).
  final double? peso;

  /// Aviso da própria balança (instável, negativo, sobrecarga). Quando existe,
  /// não há peso para usar.
  final String? aviso;

  const _LeituraPeso({this.peso, this.aviso});
}
