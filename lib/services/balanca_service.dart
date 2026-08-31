import 'dart:io';
import 'dart:convert';
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
    'paridade': 'None', // None, Even, Odd
    'stopBits': 1,
    'usarMock': true,
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

  /// Salva as configurações da balança
  Future<void> salvarConfiguracao(Map<String, dynamic> novaConfig) async {
    try {
      await _storage.salvar(_keyBalancaConfig, novaConfig);
      debugPrint('Configuração da balança salva com sucesso: $novaConfig');
    } catch (e) {
      debugPrint('Erro ao salvar configuração da balança: $e');
    }
  }

  /// Obtém o diretório padrão para exportar os itens do Toledo (geralmente área de trabalho)
  Future<String> obterDiretorioToledoPadrao() async {
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
    if (!Platform.isWindows) {
      return ['MOCK_PORT'];
    }
    try {
      // Executa comando powershell para listar as portas seriais registradas
      final result = await runProcessHidden(
        'powershell',
        ['-Command', '[System.IO.Ports.SerialPort]::getportnames()'],
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

  /// Lê o peso da balança
  /// Retorna um Map contendo:
  /// - 'peso': double (peso lido)
  /// - 'simulado': bool (se o peso é fictício/mocked)
  /// - 'erro': String? (mensagem de erro caso ocorra)
  Future<Map<String, dynamic>> lerPeso() async {
    final config = await obterConfiguracao();
    final bool usarMock = config['usarMock'] ?? true;
    final double pesoMock = (config['pesoMock'] ?? 1.500).toDouble();
    final String porta = config['porta'] ?? 'COM1';
    final int baudRate = config['baudRate'] ?? 9600;

    if (usarMock) {
      // Simula um atraso pequeno para simular comunicação de verdade
      await Future.delayed(const Duration(milliseconds: 300));
      return {
        'peso': pesoMock,
        'simulado': true,
        'erro': null,
      };
    }

    if (!Platform.isWindows) {
      return {
        'peso': pesoMock,
        'simulado': true,
        'erro': 'Leitura de porta serial física suportada apenas em Windows.',
      };
    }

    try {
      // Script rápido em PowerShell para tentar abrir a porta e ler uma linha/buffer.
      // O script tenta ler da porta serial por até 1.5 segundos.
      final script = '''
\$port = New-Object System.IO.Ports.SerialPort $porta, $baudRate, None, 8, one
\$port.ReadTimeout = 1500
try {
    \$port.Open()
    # Se a balança exige comando ENQ (Toledo pede Hex 05 para ler)
    # \$port.Write([char]5)
    
    # Lê os dados da balança. Geralmente a balança fica enviando dados contínuos.
    # Vamos ler os primeiros bytes disponíveis ou a primeira linha
    Start-Sleep -Milliseconds 150
    if (\$port.BytesToRead -gt 0) {
        \$data = \$port.ReadExisting()
        Write-Output \$data
    } else {
        \$line = \$port.ReadLine()
        Write-Output \$line
    }
} catch {
    Write-Error \$.Exception.Message
} finally {
    if (\$port.IsOpen) {
        \$port.Close()
    }
}
''';

      final result = await runProcessHidden(
        'powershell',
        ['-Command', script],
      );

      if (result.exitCode == 0) {
        final saidaRaw = result.stdout.toString().trim();
        debugPrint('Dados lidos da Balança Serial ($porta): "$saidaRaw"');

        if (saidaRaw.isEmpty) {
          return {
            'peso': pesoMock,
            'simulado': true,
            'erro': 'Sem resposta da balança na porta $porta (Retorno vazio). Simulando peso padrão.',
          };
        }

        // Tenta extrair o peso da string de resposta.
        // A resposta padrão de balanças Toledo (Prix 3) e Filizola normalmente contém o peso limpo:
        // Exemplo Toledo: STX + peso (5 ou 6 caracteres) + ETX. Ex: "\x02001540\x03" ou "001.540" ou "1.540"
        // Exemplo Filizola: "01540" (1.540 kg)
        final pesoExtraido = _extrairPesoDeString(saidaRaw);
        if (pesoExtraido != null && pesoExtraido > 0) {
          return {
            'peso': pesoExtraido,
            'simulado': false,
            'erro': null,
          };
        }

        return {
          'peso': pesoMock,
          'simulado': true,
          'erro': 'Não foi possível extrair um peso válido dos dados recebidos: "$saidaRaw". Simulando peso padrão.',
        };
      } else {
        final erroStr = result.stderr.toString().trim();
        return {
          'peso': pesoMock,
          'simulado': true,
          'erro': 'Falha ao acessar porta $porta: $erroStr. Simulando peso padrão.',
        };
      }
    } catch (e) {
      return {
        'peso': pesoMock,
        'simulado': true,
        'erro': 'Erro de comunicação na porta $porta: $e. Simulando peso padrão.',
      };
    }
  }

  /// Analisa e limpa a string recebida da serial para obter o valor decimal do peso
  double? _extrairPesoDeString(String raw) {
    try {
      // Remove caracteres não numéricos exceto ponto e vírgula
      // Exemplo: se vier "STX01250ETX" (1.250kg) ou "01.250"
      final apenasDigitosEPonto = raw.replaceAll(RegExp(r'[^0-9.,]'), '');
      
      if (apenasDigitosEPonto.isEmpty) return null;

      // Se contém divisor de decimal explícito
      if (apenasDigitosEPonto.contains('.') || apenasDigitosEPonto.contains(',')) {
        final limpo = apenasDigitosEPonto.replaceAll(',', '.');
        return double.tryParse(limpo);
      }

      // Se não tiver ponto, interpretamos de acordo com o padrão de balanças (normalmente 3 casas decimais)
      // Exemplo: "01250" -> 1.250 kg. "1250" -> 1.250 kg. "250" -> 0.250 kg.
      final valorInt = int.tryParse(apenasDigitosEPonto);
      if (valorInt != null) {
        return valorInt / 1000.0;
      }
    } catch (_) {}
    return null;
  }

  /// Gera e exporta o arquivo de itens compatível com Balanças Toledo (Layout MGV)
  /// Retorna o caminho do arquivo gerado
  Future<String> exportarItensToledo(List<Produto> produtos, String diretorioDestino) async {
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
