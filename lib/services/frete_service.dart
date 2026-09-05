import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import '../models/opcao_frete.dart';
import '../models/taxa_entrega.dart';
import '../models/zona_entrega.dart';

/// Serviço para cálculo de frete usando APIs reais e sistema híbrido
class FreteService {
  // Configurações dos Correios (podem ser configuradas via variáveis de ambiente)
  static String? _codigoEmpresaCorreios;
  static String? _senhaCorreios;
  
  // CREDENCIAIS GLOBAIS (Configure aqui para usar a mesma chave em todas as lojas)
  static const String GLOBAL_CODIGO_CORREIOS = ''; // Ex: '9912214156'
  static const String GLOBAL_SENHA_CORREIOS = '';  // Ex: '123456'
  static String _codigoServicoPAC = '04510'; // PAC
  static String _codigoServicoSEDEX = '04014'; // SEDEX
  static String _codigoServicoPACMini = '04782'; // PAC Mini
  static String _codigoServicoSEDEX10 = '40169'; // SEDEX 10
  static String _codigoServicoSEDEX12 = '40126'; // SEDEX 12
  
  // Configurações de outras transportadoras (habilitadas por padrão para melhor experiência)
  static bool _habilitarJadlog = true;
  static bool _habilitarTotalExpress = true;
  static bool _habilitarAzulCargo = true;
  static bool _habilitarLoggi = true;
  static bool _habilitarEntregasRapidas = true; // iFood, Rappi, etc. (para produtos compatíveis)
  
  // Credenciais para APIs reais das transportadoras
  static String? _jadlogToken;
  static String? _totalExpressToken;
  static String? _azulCargoToken;
  static String? _loggiToken;
  static String? _ifoodToken;
  static String? _rappiToken;
  static String? _melhorEnvioToken; // Melhor Envio - plataforma unificada
  static String? _melhorEnvioEmail;
  
  /// Configura credenciais dos Correios (opcional - necessário para API oficial)
  /// Para obter credenciais: https://www.correios.com.br/enviar/precisa-de-ajuda/contratacao-de-servicos
  static void configurarCorreios({
    String? codigoEmpresa,
    String? senha,
  }) {
    _codigoEmpresaCorreios = codigoEmpresa;
    _senhaCorreios = senha;
    debugPrint('>>> [FreteService] Credenciais dos Correios configuradas: ${codigoEmpresa != null ? "Sim" : "Não"}');
  }
  
  /// Configura transportadoras adicionais
  static void configurarTransportadoras({
    bool habilitarJadlog = true,
    bool habilitarTotalExpress = true,
    bool habilitarAzulCargo = true,
    bool habilitarLoggi = true,
    bool habilitarEntregasRapidas = true,
  }) {
    _habilitarJadlog = habilitarJadlog;
    _habilitarTotalExpress = habilitarTotalExpress;
    _habilitarAzulCargo = habilitarAzulCargo;
    _habilitarLoggi = habilitarLoggi;
    _habilitarEntregasRapidas = habilitarEntregasRapidas;
  }
  
  /// Configura credenciais para APIs reais das transportadoras
  /// Quando configuradas, o sistema tentará usar a API real primeiro, senão usa cálculo estimado
  static void configurarCredenciaisTransportadoras({
    String? jadlogToken,
    String? totalExpressToken,
    String? azulCargoToken,
    String? loggiToken,
    String? ifoodToken,
    String? rappiToken,
    String? melhorEnvioToken,
    String? melhorEnvioEmail,
  }) {
    _jadlogToken = jadlogToken;
    _totalExpressToken = totalExpressToken;
    _azulCargoToken = azulCargoToken;
    _loggiToken = loggiToken;
    _ifoodToken = ifoodToken;
    _rappiToken = rappiToken;
    _melhorEnvioToken = melhorEnvioToken;
    _melhorEnvioEmail = melhorEnvioEmail;
    
    debugPrint('>>> [FreteService] Credenciais de transportadoras configuradas:');
    debugPrint('>>> [FreteService] - Jadlog: ${jadlogToken != null ? "Sim" : "Não (usará estimado)"}');
    debugPrint('>>> [FreteService] - Total Express: ${totalExpressToken != null ? "Sim" : "Não (usará estimado)"}');
    debugPrint('>>> [FreteService] - Azul Cargo: ${azulCargoToken != null ? "Sim" : "Não (usará estimado)"}');
    debugPrint('>>> [FreteService] - Loggi: ${loggiToken != null ? "Sim" : "Não (usará estimado)"}');
    debugPrint('>>> [FreteService] - Melhor Envio: ${melhorEnvioToken != null ? "Sim" : "Não (usará estimado)"}');
  }
  /// Busca endereço pelo CEP usando API ViaCEP
  static Future<Map<String, String?>> buscarEnderecoPorCEP(String cep) async {
    try {
      // Remove formatação do CEP
      final cepLimpo = cep.replaceAll(RegExp(r'[^\d]'), '');
      
      if (cepLimpo.length != 8) {
        throw Exception('CEP inválido');
      }

      final url = Uri.parse('https://viacep.com.br/ws/$cepLimpo/json/');
      final response = await http.get(url).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception('Timeout ao buscar CEP');
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        
        if (data.containsKey('erro')) {
          throw Exception('CEP não encontrado');
        }

        return {
          'endereco': data['logradouro'] as String?,
          'bairro': data['bairro'] as String?,
          'cidade': data['localidade'] as String?,
          'estado': data['uf'] as String?,
          'cep': cepLimpo,
        };
      } else {
        throw Exception('Erro ao buscar CEP: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('>>> Erro ao buscar CEP: $e');
      rethrow;
    }
  }

  /// Obtém coordenadas (latitude e longitude) a partir de um CEP
  /// Usa a API BrasilAPI que retorna coordenadas
  static Future<Map<String, double>?> _obterCoordenadasPorCEP(String cep) async {
    try {
      final cepLimpo = cep.replaceAll(RegExp(r'[^\d]'), '');
      
      if (cepLimpo.length != 8) {
        return null;
      }

      // Tentar BrasilAPI primeiro (retorna coordenadas)
      try {
        final url = Uri.parse('https://brasilapi.com.br/api/cep/v1/$cepLimpo');
        final response = await http.get(url).timeout(
          const Duration(seconds: 5),
          onTimeout: () => throw Exception('Timeout'),
        );

        if (response.statusCode == 200) {
          final data = json.decode(response.body) as Map<String, dynamic>;
          
          if (data.containsKey('location') && data['location'] != null) {
            final location = data['location'] as Map<String, dynamic>;
            final lat = location['coordinates']?['latitude'] as num?;
            final lon = location['coordinates']?['longitude'] as num?;
            
            if (lat != null && lon != null) {
              return {
                'lat': lat.toDouble(),
                'lon': lon.toDouble(),
              };
            }
          }
        }
      } catch (_) {
        // Se BrasilAPI falhar, tentar ViaCEP + geocodificação
        debugPrint('>>> [FreteService] BrasilAPI não retornou coordenadas, tentando alternativa');
      }

      // Fallback: usar ViaCEP e tentar geocodificação via OpenStreetMap Nominatim
      final endereco = await buscarEnderecoPorCEP(cep);
      if (endereco['cidade'] != null && endereco['estado'] != null) {
        final cidade = endereco['cidade']!;
        final estado = endereco['estado']!;
        final enderecoCompleto = '$cidade, $estado, Brasil';
        
        try {
          final geocodeUrl = Uri.parse(
            'https://nominatim.openstreetmap.org/search?q=${Uri.encodeComponent(enderecoCompleto)}&format=json&limit=1',
          );
          final geocodeResponse = await http.get(
            geocodeUrl,
            headers: {'User-Agent': 'SistemaExodo/1.0'},
          ).timeout(const Duration(seconds: 5));

          if (geocodeResponse.statusCode == 200) {
            final geocodeData = json.decode(geocodeResponse.body) as List<dynamic>;
            if (geocodeData.isNotEmpty) {
              final result = geocodeData.first as Map<String, dynamic>;
              final lat = double.tryParse(result['lat'] as String? ?? '');
              final lon = double.tryParse(result['lon'] as String? ?? '');
              
              if (lat != null && lon != null) {
                return {'lat': lat, 'lon': lon};
              }
            }
          }
        } catch (_) {
          // Geocodificação falhou, retornar null
        }
      }

      return null;
    } catch (e) {
      debugPrint('>>> [FreteService] Erro ao obter coordenadas por CEP: $e');
      return null;
    }
  }

  /// Obtém coordenadas (latitude e longitude) a partir de um CEP (wrapper público)
  static Future<Map<String, double>?> obterCoordenadasPorCEP(String cep) {
    return _obterCoordenadasPorCEP(cep);
  }

  /// Calcula distância entre duas coordenadas usando a fórmula de Haversine (wrapper público)
  static double calcularDistancia(double lat1, double lon1, double lat2, double lon2) {
    return _calcularDistancia(lat1, lon1, lat2, lon2);
  }

  /// Obtém coordenadas (latitude e longitude) a partir de um endereço completo
  static Future<Map<String, double>?> obterCoordenadasPorEndereco(String endereco) async {
    // Tenta primeiro o endereço completo fornecido
    final coords = await _consultarNominatim(endereco);
    if (coords != null) return coords;

    // Se falhou, e o endereço contém número (ex: "Rua Parintins, 36, ..."), tenta sem o número
    final partes = endereco.split(',');
    if (partes.length >= 3) {
      // Exclui a segunda parte (geralmente o número)
      final semNumero = [partes.first, ...partes.sublist(2)].join(',');
      debugPrint('>>> [FreteService] Tentando geocodificação sem número: $semNumero');
      return _consultarNominatim(semNumero);
    }
    
    return null;
  }

  static Future<Map<String, double>?> _consultarNominatim(String query) async {
    try {
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/search?q=${Uri.encodeComponent(query)}&format=json&limit=1',
      );
      final response = await http.get(
        url,
        headers: {'User-Agent': 'SistemaExodo/1.0'},
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as List<dynamic>;
        if (data.isNotEmpty) {
          final result = data.first as Map<String, dynamic>;
          final lat = double.tryParse(result['lat'] as String? ?? '');
          final lon = double.tryParse(result['lon'] as String? ?? '');
          if (lat != null && lon != null) {
            return {'lat': lat, 'lon': lon};
          }
        }
      }
    } catch (e) {
      debugPrint('>>> [FreteService] Erro ao consultar Nominatim ($query): $e');
    }
    return null;
  }


  /// Calcula a distância real de rota de carro via Google Maps Distance Matrix API
  static Future<double?> obterDistanciaGoogleMaps({
    required String origem,
    required String destino,
    required String apiKey,
  }) async {
    try {
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/distancematrix/json?'
        'origins=${Uri.encodeComponent(origem)}'
        '&destinations=${Uri.encodeComponent(destino)}'
        '&key=$apiKey',
      );
      final response = await http.get(url).timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        if (data['status'] == 'OK') {
          final rows = data['rows'] as List<dynamic>;
          if (rows.isNotEmpty) {
            final elements = rows.first['elements'] as List<dynamic>;
            if (elements.isNotEmpty) {
              final element = elements.first as Map<String, dynamic>;
              if (element['status'] == 'OK') {
                final distanceMap = element['distance'] as Map<String, dynamic>;
                // O valor retornado é em metros
                final metros = (distanceMap['value'] as num).toDouble();
                return metros / 1000.0; // Converter para km
              } else {
                debugPrint('>>> [FreteService] Element status error: ${element['status']}');
              }
            }
          }
        } else {
          debugPrint('>>> [FreteService] Matrix status error: ${data['status']}');
        }
      }
    } catch (e) {
      debugPrint('>>> [FreteService] Erro ao calcular distância via Google Maps: $e');
    }
    return null;
  }



  /// Calcula todas as opções de frete disponíveis (SISTEMA HÍBRIDO)
  /// 
  /// Prioridade: 1. Taxa por Bairro > 2. Entrega Mesmo Bairro > 3. Correios > 4. Transportadoras > 5. Cálculo por Distância > 6. Manual
  /// 
  /// [estadoOrigem] - Estado da loja (ex: 'PR')
  /// [estadoDestino] - Estado do cliente (ex: 'SP')
  /// [pesoTotal] - Peso total em gramas
  /// [valorPedido] - Valor total do pedido
  /// [cepOrigem] - CEP da loja (opcional, para cálculo mais preciso)
  /// [cepDestino] - CEP do cliente (opcional, para cálculo mais preciso)
  /// [bairroDestino] - Bairro do destino (opcional, para verificar taxa por bairro)
  /// [cidadeDestino] - Cidade do destino (opcional, para verificar taxa por bairro)
  /// [bairroOrigem] - Bairro da loja (opcional, para verificar entrega no mesmo bairro)
  /// [cidadeOrigem] - Cidade da loja (opcional, para verificar entrega no mesmo bairro)
    /// [taxasEntrega] - Lista de taxas de entrega cadastradas (opcional)
    /// [valorMinimoFreteGratis] - Valor mínimo para frete grátis (opcional, padrão: 399.90)
    /// [configFrete] - Configurações de frete do e-commerce (opcional)
    /// [zonasEntrega] - Lista de zonas de entrega inteligentes (opcional)
    /// 
    /// Retorna lista de OpcaoFrete ordenada por prioridade
    static Future<List<OpcaoFrete>> calcularOpcoesFrete({
    required String estadoOrigem,
    required String estadoDestino,
    required double pesoTotal, // em gramas
    required double valorPedido,
    String? cepOrigem,
    String? cepDestino,
    String? bairroDestino,
    String? cidadeDestino,
    String? bairroOrigem,
    String? cidadeOrigem,
    List<TaxaEntrega>? taxasEntrega,
    double? valorMinimoFreteGratis,
    Map<String, dynamic>? configFrete,
    List<ZonaEntrega>? zonasEntrega,
  }) async {
    // Valor padrão para frete grátis
    final valorMinimo = valorMinimoFreteGratis ?? 399.90;
    final opcoes = <OpcaoFrete>[];
    
    debugPrint('>>> [FreteService] ========================================');
    debugPrint('>>> [FreteService] INICIANDO CÁLCULO DE FRETE');
    debugPrint('>>> [FreteService] Estado Origem: $estadoOrigem | Estado Destino: $estadoDestino');
    debugPrint('>>> [FreteService] CEP Origem: $cepOrigem | CEP Destino: $cepDestino');
    debugPrint('>>> [FreteService] Peso Total: ${(pesoTotal / 1000).toStringAsFixed(2)} kg | Valor Pedido: R\$ $valorPedido');
    debugPrint('>>> [FreteService] Bairro Origem: $bairroOrigem | Bairro Destino: $bairroDestino');
    debugPrint('>>> [FreteService] Cidade Origem: $cidadeOrigem | Cidade Destino: $cidadeDestino');
    
    // -1. OPÇÕES FIXAS (DEFINIDAS PELO USUÁRIO)
    if (configFrete != null && configFrete['opcoesFreteFixas'] != null) {
      final fixasData = configFrete['opcoesFreteFixas'] as List<dynamic>;
      for (var f in fixasData) {
        try {
          final opcao = OpcaoFrete.fromMap(Map<String, dynamic>.from(f));
          opcoes.add(opcao);
          debugPrint('>>> [FreteService] ✅ Opção fixa adicionada: ${opcao.nome}');
        } catch (e) {
          debugPrint('>>> [FreteService] ⚠️ Erro ao carregar opção fixa: $e');
        }
      }
    }
    
    // 0. PRIORIDADE MÁXIMA: Zonas de Entrega Inteligentes (cálculo por bairro/distância)
    if (zonasEntrega != null && zonasEntrega.isNotEmpty) {
      try {
        final opcaoZona = await _calcularFretePorZona(
          zonasEntrega: zonasEntrega,
          cepOrigem: cepOrigem,
          cepDestino: cepDestino,
          bairroOrigem: bairroOrigem,
          cidadeOrigem: cidadeOrigem,
          bairroDestino: bairroDestino,
          cidadeDestino: cidadeDestino,
          estadoOrigem: estadoOrigem,
          estadoDestino: estadoDestino,
          valorPedido: valorPedido,
          valorMinimoFreteGratis: valorMinimo,
        );
        
        if (opcaoZona != null) {
          opcoes.add(opcaoZona);
          debugPrint('>>> [FreteService] ✅ Zona de entrega encontrada: ${opcaoZona.nome} - R\$ ${opcaoZona.valor}');
        }
      } catch (e, stackTrace) {
        debugPrint('>>> [FreteService] ⚠️ Erro ao calcular frete por zona: $e');
        debugPrint('>>> [FreteService] Stack: $stackTrace');
      }
    }
    
    // 1. PRIORIDADE: Verificar Taxa por Bairro (fallback se não houver zona)
    if (bairroDestino != null && taxasEntrega != null && taxasEntrega.isNotEmpty) {
      try {
        final taxaBairro = taxasEntrega.firstWhere(
          (t) => t.ativo &&
              t.bairro.toLowerCase().trim() == bairroDestino.toLowerCase().trim() &&
              (cidadeDestino == null || 
               t.cidade == null || 
               t.cidade!.toLowerCase().trim() == cidadeDestino.toLowerCase().trim()),
        );
        
        opcoes.add(OpcaoFrete(
          id: 'taxa_bairro_${taxaBairro.id}',
          nome: 'Entrega Local',
          tipo: 'taxa_bairro',
          valor: taxaBairro.valor,
          prazo: 1, // Entrega local geralmente é no mesmo dia ou 1 dia útil
          descricao: 'Taxa fixa para ${taxaBairro.bairro}',
          metadados: {
            'taxaId': taxaBairro.id,
            'bairro': taxaBairro.bairro,
          },
        ));
        
        debugPrint('>>> [FreteService] ✅ Taxa por bairro encontrada: R\$ ${taxaBairro.valor}');
      } catch (_) {
        debugPrint('>>> [FreteService] ℹ️ Nenhuma taxa por bairro encontrada');
      }
    }

    // 1.1. PRIORIDADE ALTA: Frete Inteligente Local (Mesma Cidade)
    // Substitui a antiga "Entrega no Mesmo Bairro" por um cálculo preciso em toda a cidade
    if (configFrete != null && 
        (configFrete['habilitarEntregaMesmoBairro'] as bool? ?? false) &&
        cidadeOrigem != null && 
        cidadeDestino != null) {
      
      final cidadeOrigemLower = cidadeOrigem.toLowerCase().trim();
      final cidadeDestinoLower = cidadeDestino.toLowerCase().trim();
      
      // Verificar se é a mesma cidade
      if (cidadeOrigemLower == cidadeDestinoLower) {
        debugPrint('>>> [FreteService] 🏙️ Mesma cidade detectada. Calculando Frete Inteligente Local...');
        
        // Tentar calcular via distância real
        if (cepOrigem != null && cepDestino != null) {
          final opcaoLocal = await _calcularFretePorDistancia(
            cepOrigem: cepOrigem,
            cepDestino: cepDestino,
            pesoTotal: pesoTotal,
            valorPedido: valorPedido,
            valorMinimoFreteGratis: valorMinimo,
            configFrete: configFrete,
          );
          
          if (opcaoLocal != null) {
            // Personalizar para entrega local
            final opcaoLocalFinal = OpcaoFrete(
              id: 'local_inteligente_${DateTime.now().millisecondsSinceEpoch}',
              nome: 'Entrega Local (Motoboy/Expressa)',
              tipo: 'entrega_local',
              valor: opcaoLocal.valor,
              prazo: 0, // Mesmo dia
              descricao: 'Entrega imediata na cidade (calculada por km)',
              metadados: {
                ...?opcaoLocal.metadados,
                'cidade': cidadeDestino,
                'tipo_veiculo': 'moto_carro',
                'mesmoDia': true,
              },
            );
            
            opcoes.add(opcaoLocalFinal);
            debugPrint('>>> [FreteService] ✅ Frete Inteligente Local adicionado: R\$ ${opcaoLocal.valor}');
          } else {
             // Fallback se falhar o cálculo de distância: Taxa Fixa configurada
             final taxaFixa = (configFrete['taxaEntregaMesmoBairro'] as num?)?.toDouble() ?? 10.0;
             opcoes.add(OpcaoFrete(
              id: 'local_fixo_fallback',
              nome: 'Entrega Local',
              tipo: 'entrega_local',
              valor: taxaFixa,
              prazo: 0,
              descricao: 'Entrega na cidade',
             ));
          }
        }
      }
    }

    // 2. SEGUNDA PRIORIDADE: API dos Correios (PAC, SEDEX e outros serviços)
    final habilitarCorreios = configFrete?['habilitarCorreios'] as bool? ?? true;
    if (habilitarCorreios && cepOrigem != null && cepDestino != null) {
      debugPrint('>>> [FreteService] Calculando opções dos Correios...');
      try {
        // Calcular PAC (sempre disponível)
        final opcaoPAC = await _calcularFreteCorreios(
          cepOrigem: cepOrigem,
          cepDestino: cepDestino,
          pesoTotal: pesoTotal,
          valorPedido: valorPedido,
          codigoServico: _codigoServicoPAC,
          nome: 'PAC',
          valorMinimoFreteGratis: valorMinimo,
          estadoOrigem: estadoOrigem,
          estadoDestino: estadoDestino,
        );
        if (opcaoPAC != null) {
          opcoes.add(opcaoPAC);
        }

        // Calcular SEDEX (sempre disponível)
        final opcaoSEDEX = await _calcularFreteCorreios(
          cepOrigem: cepOrigem,
          cepDestino: cepDestino,
          pesoTotal: pesoTotal,
          valorPedido: valorPedido,
          codigoServico: _codigoServicoSEDEX,
          nome: 'SEDEX',
          valorMinimoFreteGratis: valorMinimo,
          estadoOrigem: estadoOrigem,
          estadoDestino: estadoDestino,
        );
        if (opcaoSEDEX != null) {
          opcoes.add(opcaoSEDEX);
        }
        
        // Calcular PAC Mini (econômico para produtos pequenos)
        final opcaoPACMini = await _calcularFreteCorreios(
          cepOrigem: cepOrigem,
          cepDestino: cepDestino,
          pesoTotal: pesoTotal,
          valorPedido: valorPedido,
          codigoServico: _codigoServicoPACMini,
          nome: 'PAC Mini',
          valorMinimoFreteGratis: valorMinimo,
          estadoOrigem: estadoOrigem,
          estadoDestino: estadoDestino,
        );
        if (opcaoPACMini != null) {
          opcoes.add(opcaoPACMini);
        }
        
        // Calcular SEDEX 10 (expresso, apenas com credenciais)
        if (_codigoEmpresaCorreios != null && _senhaCorreios != null) {
          final opcaoSEDEX10 = await _calcularFreteCorreios(
            cepOrigem: cepOrigem,
            cepDestino: cepDestino,
            pesoTotal: pesoTotal,
            valorPedido: valorPedido,
            codigoServico: _codigoServicoSEDEX10,
            nome: 'SEDEX 10',
            valorMinimoFreteGratis: valorMinimo,
            estadoOrigem: estadoOrigem,
            estadoDestino: estadoDestino,
          );
          if (opcaoSEDEX10 != null) {
            opcoes.add(opcaoSEDEX10);
          }
          
          // Calcular SEDEX 12 (expresso até 12h)
          final opcaoSEDEX12 = await _calcularFreteCorreios(
            cepOrigem: cepOrigem,
            cepDestino: cepDestino,
            pesoTotal: pesoTotal,
            valorPedido: valorPedido,
            codigoServico: _codigoServicoSEDEX12,
            nome: 'SEDEX 12',
            valorMinimoFreteGratis: valorMinimo,
            estadoOrigem: estadoOrigem,
            estadoDestino: estadoDestino,
          );
          if (opcaoSEDEX12 != null) {
            opcoes.add(opcaoSEDEX12);
          }
        }
      } catch (e, stackTrace) {
        debugPrint('>>> [FreteService] ⚠️ Erro ao calcular frete dos Correios: $e');
        debugPrint('>>> [FreteService] Stack trace: $stackTrace');
      }
    } else {
      debugPrint('>>> [FreteService] ⚠️ CEPs não informados, pulando cálculo dos Correios');
    }
    
    // 2.1. MELHOR ENVIO (plataforma unificada - calcula múltiplas transportadoras de uma vez)
    if (cepOrigem != null && cepDestino != null && _melhorEnvioToken != null) {
      debugPrint('>>> [FreteService] Calculando opções via Melhor Envio...');
      try {
        final opcoesMelhorEnvio = await _calcularFreteMelhorEnvio(
          cepOrigem: cepOrigem,
          cepDestino: cepDestino,
          pesoTotal: pesoTotal,
          valorPedido: valorPedido,
          token: _melhorEnvioToken!,
          email: _melhorEnvioEmail,
        );
        opcoes.addAll(opcoesMelhorEnvio);
        debugPrint('>>> [FreteService] ✅ Melhor Envio retornou ${opcoesMelhorEnvio.length} opções');
      } catch (e, stackTrace) {
        debugPrint('>>> [FreteService] ⚠️ Erro ao calcular frete via Melhor Envio: $e');
        debugPrint('>>> [FreteService] Stack trace: $stackTrace');
      }
    }
    
    // 2.2. OUTRAS TRANSPORTADORAS (se habilitadas)
    if (cepOrigem != null && cepDestino != null) {
      debugPrint('>>> [FreteService] Calculando opções de transportadoras...');
      try {
        // Obter configurações de frete (priorizar config do e-commerce, senão usar padrão)
        final habilitarJadlog = configFrete?['habilitarJadlog'] as bool? ?? _habilitarJadlog;
        final habilitarTotalExpress = configFrete?['habilitarTotalExpress'] as bool? ?? _habilitarTotalExpress;
        final habilitarAzulCargo = configFrete?['habilitarAzulCargo'] as bool? ?? _habilitarAzulCargo;
        final habilitarLoggi = configFrete?['habilitarLoggi'] as bool? ?? _habilitarLoggi;
        final habilitarEntregasRapidas = configFrete?['habilitarEntregasRapidas'] as bool? ?? _habilitarEntregasRapidas;
        
        // Jadlog
        if (habilitarJadlog) {
          final opcaoJadlog = await _calcularFreteJadlog(
            cepOrigem: cepOrigem,
            cepDestino: cepDestino,
            pesoTotal: pesoTotal,
            valorPedido: valorPedido,
            valorMinimoFreteGratis: valorMinimo,
          );
          if (opcaoJadlog != null) {
            opcoes.add(opcaoJadlog);
          }
        }
        
        // Total Express
        if (habilitarTotalExpress) {
          final opcaoTotalExpress = await _calcularFreteTotalExpress(
            cepOrigem: cepOrigem,
            cepDestino: cepDestino,
            pesoTotal: pesoTotal,
            valorPedido: valorPedido,
            valorMinimoFreteGratis: valorMinimo,
          );
          if (opcaoTotalExpress != null) {
            opcoes.add(opcaoTotalExpress);
          }
        }
        
        // Azul Cargo
        if (habilitarAzulCargo) {
          final opcaoAzulCargo = await _calcularFreteAzulCargo(
            cepOrigem: cepOrigem,
            cepDestino: cepDestino,
            pesoTotal: pesoTotal,
            valorPedido: valorPedido,
            valorMinimoFreteGratis: valorMinimo,
          );
          if (opcaoAzulCargo != null) {
            opcoes.add(opcaoAzulCargo);
          }
        }
        
        // Loggi (entregas rápidas urbanas - apenas para distâncias curtas)
        if (habilitarLoggi) {
          final opcaoLoggi = await _calcularFreteLoggi(
            cepOrigem: cepOrigem,
            cepDestino: cepDestino,
            pesoTotal: pesoTotal,
            valorPedido: valorPedido,
            valorMinimoFreteGratis: valorMinimo,
          );
          if (opcaoLoggi != null) {
            opcoes.add(opcaoLoggi);
          }
        }
        
        // Entregas Rápidas (iFood, Rappi, etc.) - apenas para produtos leves e distâncias curtas
        if (habilitarEntregasRapidas && pesoTotal <= 5000) { // Máximo 5kg
          final opcaoEntregaRapida = await _calcularFreteEntregaRapida(
            cepOrigem: cepOrigem,
            cepDestino: cepDestino,
            pesoTotal: pesoTotal,
            valorPedido: valorPedido,
            valorMinimoFreteGratis: valorMinimo,
          );
          if (opcaoEntregaRapida != null) {
            opcoes.add(opcaoEntregaRapida);
          }
        }
      } catch (e, stackTrace) {
        debugPrint('>>> [FreteService] ⚠️ Erro ao calcular frete de outras transportadoras: $e');
        debugPrint('>>> [FreteService] Stack trace: $stackTrace');
      }
    } else {
      debugPrint('>>> [FreteService] ⚠️ CEPs não informados, pulando cálculo de transportadoras');
    }

    // 3. TERCEIRA PRIORIDADE: Cálculo por Distância (BrasilAPI)
    final habilitarEstimativa = configFrete?['habilitarEstimativaDistancia'] as bool? ?? true;
    
    if (habilitarEstimativa && cepOrigem != null && cepDestino != null) {
      debugPrint('>>> [FreteService] Calculando frete por distância...');
      try {
        final opcaoDistancia = await _calcularFretePorDistancia(
          cepOrigem: cepOrigem,
          cepDestino: cepDestino,
          pesoTotal: pesoTotal,
          valorPedido: valorPedido,
          valorMinimoFreteGratis: valorMinimo,
          configFrete: configFrete,
        );
        if (opcaoDistancia != null) {
          opcoes.add(opcaoDistancia);
        }
      } catch (e, stackTrace) {
        debugPrint('>>> [FreteService] ⚠️ Erro ao calcular frete por distância: $e');
        debugPrint('>>> [FreteService] Stack trace: $stackTrace');
      }
    } else if (!habilitarEstimativa) {
        debugPrint('>>> [FreteService] ℹ️ Cálculo por distância desativado pelo usuário');
    } else {
      debugPrint('>>> [FreteService] ⚠️ CEPs não informados, pulando cálculo por distância');
    }

    // 4. FALLBACK: Cálculo Manual (baseado em estados/regiões)
    // Adicionar opção manual apenas se não houver outras opções calculadas
    if (opcoes.isEmpty) {
      debugPrint('>>> [FreteService] Nenhuma opção calculada, adicionando opção manual (fallback)...');
      final opcaoManual = _calcularFreteManualOpcao(
        estadoOrigem: estadoOrigem,
        estadoDestino: estadoDestino,
        pesoTotal: pesoTotal,
        valorPedido: valorPedido,
        valorMinimoFreteGratis: valorMinimo,
      );
      opcoes.add(opcaoManual);
    } else {
      debugPrint('>>> [FreteService] ${opcoes.length} opção(ões) calculada(s), não usando fallback manual');
    }

    // Ordenar por valor (menor primeiro)
    opcoes.sort((a, b) {
      // Priorizar opções não-manuais
      if (a.tipo == 'manual' && b.tipo != 'manual') return 1;
      if (a.tipo != 'manual' && b.tipo == 'manual') return -1;
      // Se ambos são manuais ou ambos não são, ordenar por valor
      return a.valor.compareTo(b.valor);
    });

    debugPrint('>>> [FreteService] ========================================');
    debugPrint('>>> [FreteService] RESULTADO: Total de opções calculadas: ${opcoes.length}');
    for (var opcao in opcoes) {
      debugPrint('>>> [FreteService] - ${opcao.nome}: R\$ ${opcao.valor.toStringAsFixed(2)} (${opcao.prazo} dias) [${opcao.tipo}]');
    }
    debugPrint('>>> [FreteService] ========================================');

    return opcoes;
  }

  /// Calcula frete usando API real (tenta API primeiro, fallback para cálculo manual)
  /// 
  /// DEPRECATED: Use calcularOpcoesFrete() para obter múltiplas opções
  /// 
  /// [estadoOrigem] - Estado da loja (ex: 'PR')
  /// [estadoDestino] - Estado do cliente (ex: 'SP')
  /// [pesoTotal] - Peso total em gramas
  /// [valorPedido] - Valor total do pedido
  /// [cepOrigem] - CEP da loja (opcional, para cálculo mais preciso)
  /// [cepDestino] - CEP do cliente (opcional, para cálculo mais preciso)
  /// 
  /// Retorna um mapa com 'valor' (double) e 'prazo' (int em dias)
  @Deprecated('Use calcularOpcoesFrete() para obter múltiplas opções de frete')
  static Future<Map<String, dynamic>> calcularFrete({
    required String estadoOrigem,
    required String estadoDestino,
    required double pesoTotal, // em gramas
    required double valorPedido,
    String? cepOrigem,
    String? cepDestino,
  }) async {
    // TENTAR USAR API REAL PRIMEIRO
    if (cepOrigem != null && cepDestino != null) {
      try {
        final resultado = await _calcularFreteComAPI(
          cepOrigem: cepOrigem,
          cepDestino: cepDestino,
          pesoTotal: pesoTotal,
          valorPedido: valorPedido,
        );
        if (resultado != null) {
          return resultado;
        }
      } catch (e) {
        debugPrint('>>> [FreteService] ⚠️ Erro ao calcular frete com API: $e');
        debugPrint('>>> [FreteService] Usando cálculo manual como fallback');
      }
    }

    // FALLBACK: CÁLCULO MANUAL
    final valor = _calcularFreteManual(
      estadoOrigem: estadoOrigem,
      estadoDestino: estadoDestino,
      pesoTotal: pesoTotal,
      valorPedido: valorPedido,
    );

    return {
      'valor': valor,
      'prazo': _calcularPrazoEntrega(estadoOrigem, estadoDestino),
    };
  }

  /// Calcula frete usando API do BrasilAPI e cálculo de distância
  static Future<Map<String, dynamic>?> _calcularFreteComAPI({
    required String cepOrigem,
    required String cepDestino,
    required double pesoTotal,
    required double valorPedido,
  }) async {
    try {
      debugPrint('>>> [FreteService] Calculando frete com API...');
      
      // Limpar CEPs
      final cepOrigemLimpo = cepOrigem.replaceAll(RegExp(r'[^\d]'), '');
      final cepDestinoLimpo = cepDestino.replaceAll(RegExp(r'[^\d]'), '');

      if (cepOrigemLimpo.length != 8 || cepDestinoLimpo.length != 8) {
        return null;
      }

      // Buscar coordenadas dos CEPs usando BrasilAPI
      final coordenadasOrigem = await _obterCoordenadasPorCEP(cepOrigemLimpo);
      final coordenadasDestino = await _obterCoordenadasPorCEP(cepDestinoLimpo);

      if (coordenadasOrigem == null || coordenadasDestino == null) {
        debugPrint('>>> [FreteService] Não foi possível obter coordenadas dos CEPs');
        return null;
      }

      // Calcular distância em km usando fórmula de Haversine
      final distanciaKm = _calcularDistancia(
        coordenadasOrigem['lat']!,
        coordenadasOrigem['lon']!,
        coordenadasDestino['lat']!,
        coordenadasDestino['lon']!,
      );

      debugPrint('>>> [FreteService] Distância calculada: ${distanciaKm.toStringAsFixed(2)} km');

      // Calcular frete baseado em distância, peso e valor
      final valorFrete = _calcularFretePorDistanciaValor(
        distanciaKm: distanciaKm,
        pesoTotal: pesoTotal,
        valorPedido: valorPedido,
        configFrete: null, // Legacy API caller
      );

      // Calcular prazo baseado na distância
      final prazo = _calcularPrazoPorDistancia(distanciaKm);

      return {
        'valor': valorFrete,
        'prazo': prazo,
        'distanciaKm': distanciaKm,
      };
    } catch (e) {
      debugPrint('>>> [FreteService] Erro ao calcular frete com API: $e');
      return null;
    }
  }

  /// Calcula distância entre duas coordenadas usando fórmula de Haversine
  static double _calcularDistancia(double lat1, double lon1, double lat2, double lon2) {
    const double raioTerra = 6371; // Raio da Terra em km

    final dLat = _grausParaRadianos(lat2 - lat1);
    final dLon = _grausParaRadianos(lon2 - lon1);

    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_grausParaRadianos(lat1)) *
            cos(_grausParaRadianos(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2);

    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    final distancia = raioTerra * c;

    return distancia;
  }

  /// Converte graus para radianos
  static double _grausParaRadianos(double graus) {
    return graus * (pi / 180);
  }

  /// Calcula frete baseado em distância, peso e valor (retorna apenas valor)
  /// AGORA COM CÁLCULO PRECISO BASEADO EM COMBUSTÍVEL
  static double _calcularFretePorDistanciaValor({
    required double distanciaKm,
    required double pesoTotal,
    required double valorPedido,
    double valorMinimoFreteGratis = 399.90,
    Map<String, dynamic>? configFrete,
  }) {
    // 1. Frete grátis para pedidos acima do valor mínimo
    if (valorPedido >= valorMinimoFreteGratis) {
      return 0.0;
    }

    // --- CONFIGURAÇÕES DO FRETE PRÓPRIO ---
    // Valores padrão caso não venha na configuração
    final double precoCombustivel = (configFrete?['precoCombustivel'] as num?)?.toDouble() ?? 5.89; // Preço médio Gasolina
    final double consumoVeiculo = (configFrete?['consumoVeiculo'] as num?)?.toDouble() ?? 10.0; // km/l
    final double margemLucro = (configFrete?['margemLucroFrete'] as num?)?.toDouble() ?? 1.5; // 50% de margem (1.5x)
    final double custoFixo = (configFrete?['custoFixoEntrega'] as num?)?.toDouble() ?? 5.00; // Taxa de saída/manuseio
    final double taxaRetorno = (configFrete?['cobrarRetorno'] as bool? ?? true) ? 2.0 : 1.0; // Ida e volta (2x) ou só ida (1x)
    
    // --- CÁLCULO MATEMÁTICO ---
    // Custo de Combustível = (Distância Total / Consumo) * Preço Combustível
    // Distância Total = Ida * Taxa Retorno (se cobrar volta)
    final double distanciaTotal = distanciaKm * taxaRetorno;
    final double custoCombustivel = (distanciaTotal / consumoVeiculo) * precoCombustivel;
    
    // Custo Operacional (Manutenção, pneus, óleo - estimado em 20% do combustível)
    final double custoOperacional = custoCombustivel * 0.20;
    
    // Custo Total Base
    double custoTotal = custoCombustivel + custoOperacional + custoFixo;
    
    // Aplicar Margem de Lucro/Segurança
    double valorFinal = custoTotal * margemLucro;

    // --- ADICIONAL POR PESO ---
    // Se passar de 5kg, cobra adicional
    final pesoKg = pesoTotal / 1000;
    if (pesoKg > 5.0) {
      final pesoExcedente = pesoKg - 5.0;
      // R$ 1,50 por kg excedente
      valorFinal += (pesoExcedente * 1.50);
    }
    
    // --- VALOR MÍNIMO DE ENTREGA ---
    // Nunca cobrar menos que R$ 10,00 (exceto se grátis)
    valorFinal = max(10.0, valorFinal);

    // Arredondar para 2 casas decimais
    return double.parse(valorFinal.toStringAsFixed(2));
  }

  /// Calcula prazo de entrega baseado na distância
  static int _calcularPrazoPorDistancia(double distanciaKm) {
    if (distanciaKm <= 50) {
      return 1; // 1 dia útil (mesma cidade/região)
    } else if (distanciaKm <= 200) {
      return 2; // 2 dias úteis (estado)
    } else if (distanciaKm <= 500) {
      return 3; // 3 dias úteis (região)
    } else if (distanciaKm <= 1000) {
      return 5; // 5 dias úteis (região distante)
    } else {
      return 7; // 7 dias úteis (muito distante)
    }
  }

  /// Calcula frete manual (fallback)
  static double _calcularFreteManual({
    required String estadoOrigem,
    required String estadoDestino,
    required double pesoTotal,
    required double valorPedido,
    double valorMinimoFreteGratis = 399.90,
  }) {
    // Regiões do Brasil
    final regioes = {
      'AC': 'Norte', 'AP': 'Norte', 'AM': 'Norte', 'PA': 'Norte', 'RO': 'Norte', 'RR': 'Norte', 'TO': 'Norte',
      'AL': 'Nordeste', 'BA': 'Nordeste', 'CE': 'Nordeste', 'MA': 'Nordeste', 'PB': 'Nordeste', 'PE': 'Nordeste',
      'PI': 'Nordeste', 'RN': 'Nordeste', 'SE': 'Nordeste',
      'DF': 'Centro-Oeste', 'GO': 'Centro-Oeste', 'MT': 'Centro-Oeste', 'MS': 'Centro-Oeste',
      'ES': 'Sudeste', 'MG': 'Sudeste', 'RJ': 'Sudeste', 'SP': 'Sudeste',
      'PR': 'Sul', 'RS': 'Sul', 'SC': 'Sul',
    };

    final regiaoOrigem = regioes[estadoOrigem.toUpperCase()] ?? 'Sudeste';
    final regiaoDestino = regioes[estadoDestino.toUpperCase()] ?? 'Sudeste';

    // Frete grátis para pedidos acima do valor mínimo configurado
    if (valorPedido >= valorMinimoFreteGratis) {
      return 0.0;
    }

    // Base de cálculo
    double freteBase = 15.0; // Frete base mínimo

    // Mesma região
    if (regiaoOrigem == regiaoDestino) {
      freteBase = 12.0;
    } else {
      // Regiões diferentes
      final regioesDistantes = [
        ['Norte', 'Sul'],
        ['Nordeste', 'Sul'],
        ['Norte', 'Sudeste'],
      ];
      
      bool isDistante = regioesDistantes.any((pair) =>
          (pair[0] == regiaoOrigem && pair[1] == regiaoDestino) ||
          (pair[1] == regiaoOrigem && pair[0] == regiaoDestino));

      if (isDistante) {
        freteBase = 35.0; // Frete mais caro para regiões distantes
      } else {
        freteBase = 20.0; // Frete médio para regiões adjacentes
      }
    }

    // Mesmo estado = desconto
    if (estadoOrigem.toUpperCase() == estadoDestino.toUpperCase()) {
      freteBase = freteBase * 0.7; // 30% de desconto
    }

    // Adicionar por peso (a cada 1kg adicional, +R$ 5)
    final pesoKg = pesoTotal / 1000;
    if (pesoKg > 1) {
      final pesoAdicional = (pesoKg - 1).ceil();
      freteBase += pesoAdicional * 5.0;
    }

    // Limite máximo de frete
    if (freteBase > 80.0) {
      freteBase = 80.0;
    }

    return freteBase;
  }

  /// Calcula prazo de entrega baseado em estados (fallback)
  static int _calcularPrazoEntrega(String estadoOrigem, String estadoDestino) {
    if (estadoOrigem.toUpperCase() == estadoDestino.toUpperCase()) {
      return 2; // Mesmo estado: 2 dias úteis
    }

    final regioes = {
      'AC': 'Norte', 'AP': 'Norte', 'AM': 'Norte', 'PA': 'Norte', 'RO': 'Norte', 'RR': 'Norte', 'TO': 'Norte',
      'AL': 'Nordeste', 'BA': 'Nordeste', 'CE': 'Nordeste', 'MA': 'Nordeste', 'PB': 'Nordeste', 'PE': 'Nordeste',
      'PI': 'Nordeste', 'RN': 'Nordeste', 'SE': 'Nordeste',
      'DF': 'Centro-Oeste', 'GO': 'Centro-Oeste', 'MT': 'Centro-Oeste', 'MS': 'Centro-Oeste',
      'ES': 'Sudeste', 'MG': 'Sudeste', 'RJ': 'Sudeste', 'SP': 'Sudeste',
      'PR': 'Sul', 'RS': 'Sul', 'SC': 'Sul',
    };

    final regiaoOrigem = regioes[estadoOrigem.toUpperCase()] ?? 'Sudeste';
    final regiaoDestino = regioes[estadoDestino.toUpperCase()] ?? 'Sudeste';

    if (regiaoOrigem == regiaoDestino) {
      return 3; // Mesma região: 3 dias úteis
    } else {
      return 5; // Regiões diferentes: 5 dias úteis
    }
  }

  /// Retorna a região do estado
  static String? obterRegiao(String estado) {
    final regioes = {
      'AC': 'Norte', 'AP': 'Norte', 'AM': 'Norte', 'PA': 'Norte', 'RO': 'Norte', 'RR': 'Norte', 'TO': 'Norte',
      'AL': 'Nordeste', 'BA': 'Nordeste', 'CE': 'Nordeste', 'MA': 'Nordeste', 'PB': 'Nordeste', 'PE': 'Nordeste',
      'PI': 'Nordeste', 'RN': 'Nordeste', 'SE': 'Nordeste',
      'DF': 'Centro-Oeste', 'GO': 'Centro-Oeste', 'MT': 'Centro-Oeste', 'MS': 'Centro-Oeste',
      'ES': 'Sudeste', 'MG': 'Sudeste', 'RJ': 'Sudeste', 'SP': 'Sudeste',
      'PR': 'Sul', 'RS': 'Sul', 'SC': 'Sul',
    };
    return regioes[estado.toUpperCase()];
  }

  /// Calcula frete usando API dos Correios (PAC ou SEDEX)
  static Future<OpcaoFrete?> _calcularFreteCorreios({
    required String cepOrigem,
    required String cepDestino,
    required double pesoTotal,
    required double valorPedido,
    required String codigoServico,
    required String nome,
    double valorMinimoFreteGratis = 399.90,
    String? estadoOrigem,
    String? estadoDestino,
  }) async {
    try {
      // Limpar CEPs
      final cepOrigemLimpo = cepOrigem.replaceAll(RegExp(r'[^\d]'), '');
      final cepDestinoLimpo = cepDestino.replaceAll(RegExp(r'[^\d]'), '');

      if (cepOrigemLimpo.length != 8 || cepDestinoLimpo.length != 8) {
        return null;
      }

      // Se tiver credenciais (próprias da empresa ou globais), usar API oficial dos Correios
      final codigoEfetivo = (_codigoEmpresaCorreios != null && _codigoEmpresaCorreios!.trim().isNotEmpty) 
          ? _codigoEmpresaCorreios! 
          : GLOBAL_CODIGO_CORREIOS;
          
      final senhaEfetiva = (_senhaCorreios != null && _senhaCorreios!.trim().isNotEmpty) 
          ? _senhaCorreios! 
          : GLOBAL_SENHA_CORREIOS;

      if (codigoEfetivo.isNotEmpty && senhaEfetiva.isNotEmpty) {
        return await _calcularFreteCorreiosOficial(
          cepOrigem: cepOrigemLimpo,
          cepDestino: cepDestinoLimpo,
          pesoTotal: pesoTotal,
          valorPedido: valorPedido,
          codigoServico: codigoServico,
          nome: nome,
          codigoEmpresa: codigoEfetivo,
          senha: senhaEfetiva,
        );
      }

      // Caso contrário, usar cálculo estimado baseado em distância
      return await _calcularFreteCorreiosEstimado(
        cepOrigem: cepOrigemLimpo,
        cepDestino: cepDestinoLimpo,
        pesoTotal: pesoTotal,
        valorPedido: valorPedido,
        codigoServico: codigoServico,
        nome: nome,
        valorMinimoFreteGratis: valorMinimoFreteGratis,
        estadoOrigem: estadoOrigem,
        estadoDestino: estadoDestino,
      );
    } catch (e) {
      debugPrint('>>> [FreteService] Erro ao calcular frete dos Correios: $e');
      return null;
    }
  }

  /// Calcula frete usando API oficial dos Correios (requer credenciais)
  /// Esta é a API SOAP oficial dos Correios que retorna valores exatos
  static Future<OpcaoFrete?> _calcularFreteCorreiosOficial({
    required String cepOrigem,
    required String cepDestino,
    required double pesoTotal,
    required double valorPedido,
    required String codigoServico,
    required String nome,
    required String codigoEmpresa,
    required String senha,
  }) async {
    try {
      debugPrint('>>> [FreteService] Calculando frete oficial dos Correios: $nome');
      debugPrint('>>> [FreteService] CEP Origem: $cepOrigem, CEP Destino: $cepDestino');
      debugPrint('>>> [FreteService] Peso: ${(pesoTotal / 1000).toStringAsFixed(2)} kg, Valor: R\$ $valorPedido');
      
      // Formato do XML para API dos Correios (SOAP)
      // Dimensões padrão: 20x15x5 cm (formato 1 = caixa/pacote)
      final xml = '''<?xml version="1.0" encoding="UTF-8"?>
<soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
  <soap:Body>
    <CalcPrecoPrazo xmlns="http://tempuri.org/">
      <nCdEmpresa>$codigoEmpresa</nCdEmpresa>
      <sDsSenha>$senha</sDsSenha>
      <nCdServico>$codigoServico</nCdServico>
      <sCepOrigem>$cepOrigem</sCepOrigem>
      <sCepDestino>$cepDestino</sCepDestino>
      <nVlPeso>${(pesoTotal / 1000).toStringAsFixed(2)}</nVlPeso>
      <nCdFormato>1</nCdFormato>
      <nVlComprimento>20</nVlComprimento>
      <nVlAltura>5</nVlAltura>
      <nVlLargura>15</nVlLargura>
      <nVlDiametro>0</nVlDiametro>
      <sCdMaoPropria>N</sCdMaoPropria>
      <nVlValorDeclarado>$valorPedido</nVlValorDeclarado>
      <sCdAvisoRecebimento>N</sCdAvisoRecebimento>
    </CalcPrecoPrazo>
  </soap:Body>
</soap:Envelope>''';

      final url = Uri.parse('https://ws.correios.com.br/calculador/CalcPrecoPrazo.asmx');
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'text/xml; charset=utf-8',
          'SOAPAction': 'http://tempuri.org/CalcPrecoPrazo',
        },
        body: xml,
      ).timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          debugPrint('>>> [FreteService] ⚠️ Timeout ao calcular frete dos Correios');
          throw Exception('Timeout ao calcular frete dos Correios');
        },
      );

      if (response.statusCode == 200) {
        final responseBody = response.body;
        debugPrint('>>> [FreteService] Resposta dos Correios recebida');
        
        // Extrair valor e prazo do XML
        final valorMatch = RegExp(r'<Valor>([^<]+)</Valor>').firstMatch(responseBody);
        final prazoMatch = RegExp(r'<PrazoEntrega>([^<]+)</PrazoEntrega>').firstMatch(responseBody);
        final erroMatch = RegExp(r'<Erro>([^<]+)</Erro>').firstMatch(responseBody);
        final msgErroMatch = RegExp(r'<MsgErro>([^<]*)</MsgErro>').firstMatch(responseBody);

        if (erroMatch != null && erroMatch.group(1) != '0') {
          final codigoErro = erroMatch.group(1);
          final msgErro = msgErroMatch?.group(1) ?? 'Erro desconhecido';
          debugPrint('>>> [FreteService] ❌ Erro dos Correios: Código $codigoErro - $msgErro');
          return null;
        }

        if (valorMatch != null && prazoMatch != null) {
          // Converter valor de "123,45" para 123.45
          final valorStr = valorMatch.group(1)!.replaceAll(',', '.').trim();
          final valor = double.tryParse(valorStr) ?? 0.0;
          final prazo = int.tryParse(prazoMatch.group(1)!.trim()) ?? 0;

          if (valor > 0 && prazo > 0) {
            debugPrint('>>> [FreteService] ✅ Frete calculado: R\$ ${valor.toStringAsFixed(2)} - Prazo: $prazo dia(s) útil(is)');
            
            return OpcaoFrete(
              id: 'correios_${codigoServico}_${DateTime.now().millisecondsSinceEpoch}',
              nome: nome,
              tipo: codigoServico == _codigoServicoPAC ? 'correios_pac' : 'correios_sedex',
              valor: valor,
              prazo: prazo,
              codigoServico: codigoServico,
              descricao: 'Entrega via Correios (cálculo oficial)',
              metadados: {
                'metodo': 'oficial',
                'api': 'correios_soap',
              },
            );
          } else {
            debugPrint('>>> [FreteService] ⚠️ Valores inválidos retornados: valor=$valor, prazo=$prazo');
          }
        } else {
          debugPrint('>>> [FreteService] ⚠️ Não foi possível extrair valor ou prazo da resposta');
        }
      } else {
        debugPrint('>>> [FreteService] ❌ Erro HTTP: ${response.statusCode}');
      }

      return null;
    } catch (e, stackTrace) {
      debugPrint('>>> [FreteService] ❌ Erro ao calcular frete oficial dos Correios: $e');
      debugPrint('>>> [FreteService] Stack trace: $stackTrace');
      return null;
    }
  }

  /// Calcula frete estimado dos Correios baseado em distância (sem credenciais)
  static Future<OpcaoFrete?> _calcularFreteCorreiosEstimado({
    required String cepOrigem,
    required String cepDestino,
    required double pesoTotal,
    required double valorPedido,
    required String codigoServico,
    required String nome,
    double valorMinimoFreteGratis = 399.90,
    String? estadoOrigem,
    String? estadoDestino,
  }) async {
    try {
      debugPrint('>>> [FreteService] Calculando frete estimado dos Correios: $nome');
      
      double distanciaKm = 0;
      bool usarDistanciaEstimada = false;
      
      // Tentar obter coordenadas
      final coordenadasOrigem = await _obterCoordenadasPorCEP(cepOrigem);
      final coordenadasDestino = await _obterCoordenadasPorCEP(cepDestino);

      if (coordenadasOrigem != null && coordenadasDestino != null) {
        // Calcular distância real
        distanciaKm = _calcularDistancia(
          coordenadasOrigem['lat']!,
          coordenadasOrigem['lon']!,
          coordenadasDestino['lat']!,
          coordenadasDestino['lon']!,
        );
        debugPrint('>>> [FreteService] Distância calculada: ${distanciaKm.toStringAsFixed(2)} km');
      } else {
        // Se não conseguir coordenadas, usar estimativa baseada em estados
        debugPrint('>>> [FreteService] Não foi possível obter coordenadas, usando estimativa por estado');
        usarDistanciaEstimada = true;
        distanciaKm = _estimarDistanciaPorEstados(estadoOrigem, estadoDestino);
        debugPrint('>>> [FreteService] Distância estimada: ${distanciaKm.toStringAsFixed(2)} km');
      }

      // Calcular frete estimado baseado em tabela de preços dos Correios
      double valorFrete;
      int prazo;

      if (codigoServico == _codigoServicoPAC || codigoServico == _codigoServicoPACMini) {
        // PAC: mais barato, mais lento
        valorFrete = _calcularFretePACEstimado(distanciaKm, pesoTotal);
        prazo = _calcularPrazoPAC(distanciaKm);
      } else {
        // SEDEX: mais caro, mais rápido
        valorFrete = _calcularFreteSEDEXEstimado(distanciaKm, pesoTotal);
        prazo = _calcularPrazoSEDEX(distanciaKm);
      }

      // Frete grátis para pedidos acima do valor mínimo configurado
      if (valorPedido >= valorMinimoFreteGratis) {
        valorFrete = 0.0;
      }

      return OpcaoFrete(
        id: 'correios_${codigoServico}_${DateTime.now().millisecondsSinceEpoch}',
        nome: nome,
        tipo: codigoServico == _codigoServicoPAC || codigoServico == _codigoServicoPACMini ? 'correios_pac' : 'correios_sedex',
        valor: valorFrete,
        prazo: prazo,
        codigoServico: codigoServico,
        descricao: usarDistanciaEstimada ? 'Entrega via Correios (estimado por região)' : 'Entrega via Correios (estimado)',
        metadados: {
          'metodo': usarDistanciaEstimada ? 'estimado_regiao' : 'estimado',
          'distanciaKm': distanciaKm,
        },
      );
    } catch (e, stackTrace) {
      debugPrint('>>> [FreteService] Erro ao calcular frete estimado dos Correios: $e');
      debugPrint('>>> [FreteService] Stack trace: $stackTrace');
      return null;
    }
  }
  
  /// Estima distância baseada em estados quando não consegue coordenadas
  static double _estimarDistanciaPorEstados(String? estadoOrigem, String? estadoDestino) {
    if (estadoOrigem == null || estadoDestino == null) {
      return 500; // Distância média padrão
    }
    
    final estadoOrigemUpper = estadoOrigem.toUpperCase();
    final estadoDestinoUpper = estadoDestino.toUpperCase();
    
    // Mesmo estado: distância média de 200km
    if (estadoOrigemUpper == estadoDestinoUpper) {
      return 200;
    }
    
    // Regiões do Brasil
    final regioes = {
      'AC': 'Norte', 'AP': 'Norte', 'AM': 'Norte', 'PA': 'Norte', 'RO': 'Norte', 'RR': 'Norte', 'TO': 'Norte',
      'AL': 'Nordeste', 'BA': 'Nordeste', 'CE': 'Nordeste', 'MA': 'Nordeste', 'PB': 'Nordeste', 'PE': 'Nordeste',
      'PI': 'Nordeste', 'RN': 'Nordeste', 'SE': 'Nordeste',
      'DF': 'Centro-Oeste', 'GO': 'Centro-Oeste', 'MT': 'Centro-Oeste', 'MS': 'Centro-Oeste',
      'ES': 'Sudeste', 'MG': 'Sudeste', 'RJ': 'Sudeste', 'SP': 'Sudeste',
      'PR': 'Sul', 'RS': 'Sul', 'SC': 'Sul',
    };
    
    final regiaoOrigem = regioes[estadoOrigemUpper] ?? 'Sudeste';
    final regiaoDestino = regioes[estadoDestinoUpper] ?? 'Sudeste';
    
    // Mesma região: distância média de 500km
    if (regiaoOrigem == regiaoDestino) {
      return 500;
    }
    
    // Regiões distantes: distância média de 2000km
    final regioesDistantes = [
      ['Norte', 'Sul'],
      ['Nordeste', 'Sul'],
      ['Norte', 'Sudeste'],
    ];
    
    bool isDistante = regioesDistantes.any((pair) =>
        (pair[0] == regiaoOrigem && pair[1] == regiaoDestino) ||
        (pair[1] == regiaoOrigem && pair[0] == regiaoDestino));
    
    if (isDistante) {
      return 2000;
    }
    
    // Regiões adjacentes: distância média de 1000km
    return 1000;
  }

  /// Calcula frete PAC estimado (Baseado em tabelas 2024/2025)
  static double _calcularFretePACEstimado(double distanciaKm, double pesoTotal) {
    final pesoKg = pesoTotal / 1000;
    
    // Base 2024: PAC tem um custo fixo inicial mais alto
    // R$ 19,80 base para curta distância, subindo gradualmente
    double valorBase = 19.80;
    if (distanciaKm > 100) valorBase += (distanciaKm / 100) * 1.50;
    
    // Fator de peso PAC: ~R$ 3,20 por kg adicional
    double adicionalPeso = 0;
    if (pesoKg > 1) {
      adicionalPeso = (pesoKg - 1) * 3.20;
    }
    
    double valor = valorBase + adicionalPeso;
    
    // Adicional de Ar de Risco/Difícil Acesso (Estimado)
    if (distanciaKm > 1500) valor += 12.00;
    
    return double.parse(valor.toStringAsFixed(2));
  }

  /// Calcula frete SEDEX estimado (Baseado em tabelas 2024/2025)
  static double _calcularFreteSEDEXEstimado(double distanciaKm, double pesoTotal) {
    final pesoKg = pesoTotal / 1000;
    
    // Base 2024: SEDEX inicia em ~R$ 24,50 para local
    double valorBase = 24.50;
    
    // SEDEX escala mais rápido com a distância
    if (distanciaKm > 50) {
      valorBase += (distanciaKm / 50) * 2.80;
    }
    
    // Fator de peso SEDEX: ~R$ 5,50 por kg adicional
    double adicionalPeso = 0;
    if (pesoKg > 1) {
      adicionalPeso = (pesoKg - 1) * 5.50;
    }
    
    double valor = valorBase + adicionalPeso;
    
    // Seguro obrigatório estimado (1% do valor se fosse considerado, aqui simulamos um fixo)
    valor += 2.50;
    
    return double.parse(valor.toStringAsFixed(2));
  }

  /// Calcula prazo PAC
  static int _calcularPrazoPAC(double distanciaKm) {
    if (distanciaKm <= 50) return 3;
    if (distanciaKm <= 200) return 5;
    if (distanciaKm <= 500) return 7;
    if (distanciaKm <= 1000) return 10;
    return 15;
  }

  /// Calcula prazo SEDEX
  static int _calcularPrazoSEDEX(double distanciaKm) {
    if (distanciaKm <= 50) return 1;
    if (distanciaKm <= 200) return 2;
    if (distanciaKm <= 500) return 3;
    if (distanciaKm <= 1000) return 4;
    return 6;
  }

  /// Calcula frete por distância como opção
  static Future<OpcaoFrete?> _calcularFretePorDistancia({
    required String cepOrigem,
    required String cepDestino,
    required double pesoTotal,
    required double valorPedido,
    double valorMinimoFreteGratis = 399.90,
    Map<String, dynamic>? configFrete,
  }) async {
    try {
      final coordenadasOrigem = await _obterCoordenadasPorCEP(cepOrigem);
      final coordenadasDestino = await _obterCoordenadasPorCEP(cepDestino);

      if (coordenadasOrigem == null || coordenadasDestino == null) {
        return null;
      }

      final distanciaKm = _calcularDistancia(
        coordenadasOrigem['lat']!,
        coordenadasOrigem['lon']!,
        coordenadasDestino['lat']!,
        coordenadasDestino['lon']!,
      );

      final valorFrete = _calcularFretePorDistanciaValor(
        distanciaKm: distanciaKm,
        pesoTotal: pesoTotal,
        valorPedido: valorPedido,
        configFrete: configFrete,
      );

      final prazo = _calcularPrazoPorDistancia(distanciaKm);

      return OpcaoFrete(
        id: 'distancia_${DateTime.now().millisecondsSinceEpoch}',
        nome: 'Entrega por Distância',
        tipo: 'distancia',
        valor: valorFrete,
        prazo: prazo,
        descricao: 'Cálculo baseado em distância',
        metadados: {
          'distanciaKm': distanciaKm,
        },
      );
    } catch (e) {
      debugPrint('>>> [FreteService] Erro ao calcular frete por distância: $e');
      return null;
    }
  }

  /// Calcula frete manual como opção
  static OpcaoFrete _calcularFreteManualOpcao({
    required String estadoOrigem,
    required String estadoDestino,
    required double pesoTotal,
    required double valorPedido,
    double valorMinimoFreteGratis = 399.90,
  }) {
    final valor = _calcularFreteManual(
      estadoOrigem: estadoOrigem,
      estadoDestino: estadoDestino,
      pesoTotal: pesoTotal,
      valorPedido: valorPedido,
      valorMinimoFreteGratis: valorMinimoFreteGratis,
    );

    final prazo = _calcularPrazoEntrega(estadoOrigem, estadoDestino);

    return OpcaoFrete(
      id: 'manual_${DateTime.now().millisecondsSinceEpoch}',
      nome: 'Entrega Padrão',
      tipo: 'manual',
      valor: valor,
      prazo: prazo,
      descricao: 'Cálculo baseado em região',
      metadados: {
        'estadoOrigem': estadoOrigem,
        'estadoDestino': estadoDestino,
      },
    );
  }

  /// Calcula frete usando Jadlog (tenta API real primeiro, senão usa estimado)
  static Future<OpcaoFrete?> _calcularFreteJadlog({
    required String cepOrigem,
    required String cepDestino,
    required double pesoTotal,
    required double valorPedido,
    double valorMinimoFreteGratis = 399.90,
  }) async {
    try {
      // Tentar API real primeiro (se tiver credenciais)
      if (_jadlogToken != null) {
        final opcaoReal = await _calcularFreteJadlogAPI(
          cepOrigem: cepOrigem,
          cepDestino: cepDestino,
          pesoTotal: pesoTotal,
          valorPedido: valorPedido,
          token: _jadlogToken!,
        );
        if (opcaoReal != null) {
          debugPrint('>>> [FreteService] ✅ Jadlog calculado via API real');
          return opcaoReal;
        }
        debugPrint('>>> [FreteService] ⚠️ API Jadlog falhou, usando cálculo estimado');
      }
      
      // Fallback: cálculo estimado
      debugPrint('>>> [FreteService] Calculando Jadlog (estimado)...');
      final coordenadasOrigem = await _obterCoordenadasPorCEP(cepOrigem);
      final coordenadasDestino = await _obterCoordenadasPorCEP(cepDestino);

      if (coordenadasOrigem == null || coordenadasDestino == null) {
        return null;
      }

      final distanciaKm = _calcularDistancia(
        coordenadasOrigem['lat']!,
        coordenadasOrigem['lon']!,
        coordenadasDestino['lat']!,
        coordenadasDestino['lon']!,
      );

      final pesoKg = pesoTotal / 1000;
      
      // Base: R$ 0,60 por km (mínimo R$ 16,00) - similar ao SEDEX
      double valor = max(16.0, distanciaKm * 0.60);
      
      // Ajuste por peso
      if (pesoKg > 1) {
        final pesoAdicional = (pesoKg - 1).ceil();
        valor += pesoAdicional * 3.5;
      }
      
      // Limite máximo
      if (valor > 180.0) {
        valor = 180.0;
      }

      // Frete grátis
      if (valorPedido >= valorMinimoFreteGratis) {
        valor = 0.0;
      }

      // Prazo: geralmente 1-2 dias a mais que SEDEX
      final prazo = _calcularPrazoSEDEX(distanciaKm) + 1;

      return OpcaoFrete(
        id: 'jadlog_${DateTime.now().millisecondsSinceEpoch}',
        nome: 'Jadlog',
        tipo: 'jadlog',
        valor: valor,
        prazo: prazo,
        descricao: 'Entrega via Jadlog (estimado)',
        metadados: {
          'metodo': 'estimado',
          'distanciaKm': distanciaKm,
        },
      );
    } catch (e) {
      debugPrint('>>> [FreteService] Erro ao calcular frete Jadlog: $e');
      return null;
    }
  }

  /// Calcula frete usando Total Express (tenta API real primeiro, senão usa estimado)
  static Future<OpcaoFrete?> _calcularFreteTotalExpress({
    required String cepOrigem,
    required String cepDestino,
    required double pesoTotal,
    required double valorPedido,
    double valorMinimoFreteGratis = 399.90,
  }) async {
    try {
      // Tentar API real primeiro (se tiver credenciais)
      if (_totalExpressToken != null) {
        final opcaoReal = await _calcularFreteTotalExpressAPI(
          cepOrigem: cepOrigem,
          cepDestino: cepDestino,
          pesoTotal: pesoTotal,
          valorPedido: valorPedido,
          token: _totalExpressToken!,
        );
        if (opcaoReal != null) {
          debugPrint('>>> [FreteService] ✅ Total Express calculado via API real');
          return opcaoReal;
        }
        debugPrint('>>> [FreteService] ⚠️ API Total Express falhou, usando cálculo estimado');
      }
      
      // Fallback: cálculo estimado
      debugPrint('>>> [FreteService] Calculando Total Express (estimado)...');
      final coordenadasOrigem = await _obterCoordenadasPorCEP(cepOrigem);
      final coordenadasDestino = await _obterCoordenadasPorCEP(cepDestino);

      if (coordenadasOrigem == null || coordenadasDestino == null) {
        return null;
      }

      final distanciaKm = _calcularDistancia(
        coordenadasOrigem['lat']!,
        coordenadasOrigem['lon']!,
        coordenadasDestino['lat']!,
        coordenadasDestino['lon']!,
      );

      final pesoKg = pesoTotal / 1000;
      
      // Base: R$ 0,55 por km (mínimo R$ 15,00) - entre PAC e SEDEX
      double valor = max(15.0, distanciaKm * 0.55);
      
      // Ajuste por peso
      if (pesoKg > 1) {
        final pesoAdicional = (pesoKg - 1).ceil();
        valor += pesoAdicional * 3.0;
      }
      
      // Limite máximo
      if (valor > 160.0) {
        valor = 160.0;
      }

      // Frete grátis
      if (valorPedido >= valorMinimoFreteGratis) {
        valor = 0.0;
      }

      // Prazo: similar ao PAC
      final prazo = _calcularPrazoPAC(distanciaKm);

      return OpcaoFrete(
        id: 'total_express_${DateTime.now().millisecondsSinceEpoch}',
        nome: 'Total Express',
        tipo: 'total_express',
        valor: valor,
        prazo: prazo,
        descricao: 'Entrega via Total Express (estimado)',
        metadados: {
          'metodo': 'estimado',
          'distanciaKm': distanciaKm,
        },
      );
    } catch (e) {
      debugPrint('>>> [FreteService] Erro ao calcular frete Total Express: $e');
      return null;
    }
  }

  /// Calcula frete usando Azul Cargo (tenta API real primeiro, senão usa estimado)
  static Future<OpcaoFrete?> _calcularFreteAzulCargo({
    required String cepOrigem,
    required String cepDestino,
    required double pesoTotal,
    required double valorPedido,
    double valorMinimoFreteGratis = 399.90,
  }) async {
    try {
      // Tentar API real primeiro (se tiver credenciais)
      if (_azulCargoToken != null) {
        final opcaoReal = await _calcularFreteAzulCargoAPI(
          cepOrigem: cepOrigem,
          cepDestino: cepDestino,
          pesoTotal: pesoTotal,
          valorPedido: valorPedido,
          token: _azulCargoToken!,
        );
        if (opcaoReal != null) {
          debugPrint('>>> [FreteService] ✅ Azul Cargo calculado via API real');
          return opcaoReal;
        }
        debugPrint('>>> [FreteService] ⚠️ API Azul Cargo falhou, usando cálculo estimado');
      }
      
      // Fallback: cálculo estimado
      debugPrint('>>> [FreteService] Calculando Azul Cargo (estimado)...');
      final coordenadasOrigem = await _obterCoordenadasPorCEP(cepOrigem);
      final coordenadasDestino = await _obterCoordenadasPorCEP(cepDestino);

      if (coordenadasOrigem == null || coordenadasDestino == null) {
        return null;
      }

      final distanciaKm = _calcularDistancia(
        coordenadasOrigem['lat']!,
        coordenadasOrigem['lon']!,
        coordenadasDestino['lat']!,
        coordenadasDestino['lon']!,
      );

      final pesoKg = pesoTotal / 1000;
      
      // Azul Cargo: preços competitivos, bom para distâncias médias
      // Base: R$ 0,50 por km (mínimo R$ 14,00)
      double valor = max(14.0, distanciaKm * 0.50);
      
      // Ajuste por peso
      if (pesoKg > 1) {
        final pesoAdicional = (pesoKg - 1).ceil();
        valor += pesoAdicional * 2.8;
      }
      
      // Limite máximo
      if (valor > 140.0) {
        valor = 140.0;
      }

      // Frete grátis
      if (valorPedido >= valorMinimoFreteGratis) {
        valor = 0.0;
      }

      // Prazo: similar ao PAC, mas um pouco mais rápido
      final prazo = _calcularPrazoPAC(distanciaKm) - 1;
      final prazoFinal = prazo > 0 ? prazo : 2;

      return OpcaoFrete(
        id: 'azul_cargo_${DateTime.now().millisecondsSinceEpoch}',
        nome: 'Azul Cargo',
        tipo: 'azul_cargo',
        valor: valor,
        prazo: prazoFinal,
        descricao: 'Entrega via Azul Cargo (estimado)',
        metadados: {
          'metodo': 'estimado',
          'distanciaKm': distanciaKm,
        },
      );
    } catch (e) {
      debugPrint('>>> [FreteService] Erro ao calcular frete Azul Cargo: $e');
      return null;
    }
  }

  /// Calcula frete usando Loggi (tenta API real primeiro, senão usa estimado)
  static Future<OpcaoFrete?> _calcularFreteLoggi({
    required String cepOrigem,
    required String cepDestino,
    required double pesoTotal,
    required double valorPedido,
    double valorMinimoFreteGratis = 399.90,
  }) async {
    try {
      // Tentar API real primeiro (se tiver credenciais)
      if (_loggiToken != null) {
        final opcaoReal = await _calcularFreteLoggiAPI(
          cepOrigem: cepOrigem,
          cepDestino: cepDestino,
          pesoTotal: pesoTotal,
          valorPedido: valorPedido,
          token: _loggiToken!,
        );
        if (opcaoReal != null) {
          debugPrint('>>> [FreteService] ✅ Loggi calculado via API real');
          return opcaoReal;
        }
        debugPrint('>>> [FreteService] ⚠️ API Loggi falhou, usando cálculo estimado');
      }
      
      // Fallback: cálculo estimado
      debugPrint('>>> [FreteService] Calculando Loggi (estimado)...');
      final coordenadasOrigem = await _obterCoordenadasPorCEP(cepOrigem);
      final coordenadasDestino = await _obterCoordenadasPorCEP(cepDestino);

      if (coordenadasOrigem == null || coordenadasDestino == null) {
        return null;
      }

      final distanciaKm = _calcularDistancia(
        coordenadasOrigem['lat']!,
        coordenadasOrigem['lon']!,
        coordenadasDestino['lat']!,
        coordenadasDestino['lon']!,
      );

      // Loggi funciona melhor para distâncias curtas (até 50km)
      if (distanciaKm > 50) {
        return null; // Não oferecer Loggi para distâncias longas
      }

      final pesoKg = pesoTotal / 1000;
      
      // Loggi: preço fixo base + por km (ideal para entregas urbanas rápidas)
      // Base: R$ 8,00 + R$ 0,80 por km
      double valor = 8.0 + (distanciaKm * 0.80);
      
      // Ajuste por peso (máximo 10kg para Loggi)
      if (pesoKg > 1 && pesoKg <= 10) {
        final pesoAdicional = (pesoKg - 1).ceil();
        valor += pesoAdicional * 1.5;
      } else if (pesoKg > 10) {
        return null; // Loggi não aceita mais de 10kg
      }
      
      // Limite máximo
      if (valor > 60.0) {
        valor = 60.0;
      }

      // Frete grátis
      if (valorPedido >= valorMinimoFreteGratis) {
        valor = 0.0;
      }

      // Prazo: muito rápido para distâncias curtas (mesmo dia ou 1 dia útil)
      final prazo = distanciaKm <= 20 ? 1 : 2;

      return OpcaoFrete(
        id: 'loggi_${DateTime.now().millisecondsSinceEpoch}',
        nome: 'Loggi Express',
        tipo: 'loggi',
        valor: valor,
        prazo: prazo,
        descricao: 'Entrega rápida via Loggi (mesmo dia/1 dia útil)',
        metadados: {
          'metodo': 'estimado',
          'distanciaKm': distanciaKm,
          'expresso': true,
        },
      );
    } catch (e) {
      debugPrint('>>> [FreteService] Erro ao calcular frete Loggi: $e');
      return null;
    }
  }

  /// Calcula frete para entregas rápidas (iFood, Rappi, etc.) - apenas produtos leves
  static Future<OpcaoFrete?> _calcularFreteEntregaRapida({
    required String cepOrigem,
    required String cepDestino,
    required double pesoTotal,
    required double valorPedido,
    double valorMinimoFreteGratis = 399.90,
  }) async {
    try {
      final coordenadasOrigem = await _obterCoordenadasPorCEP(cepOrigem);
      final coordenadasDestino = await _obterCoordenadasPorCEP(cepDestino);

      if (coordenadasOrigem == null || coordenadasDestino == null) {
        return null;
      }

      final distanciaKm = _calcularDistancia(
        coordenadasOrigem['lat']!,
        coordenadasOrigem['lon']!,
        coordenadasDestino['lat']!,
        coordenadasDestino['lon']!,
      );

      // Entregas rápidas funcionam apenas para distâncias muito curtas (até 15km)
      if (distanciaKm > 15) {
        return null;
      }

      // Apenas para produtos muito leves (até 5kg)
      if (pesoTotal > 5000) {
        return null;
      }

      final pesoKg = pesoTotal / 1000;
      
      // Entregas rápidas: preço fixo + taxa por km (mais caro, mas muito rápido)
      // Base: R$ 12,00 + R$ 1,20 por km
      double valor = 12.0 + (distanciaKm * 1.20);
      
      // Ajuste por peso (mínimo)
      if (pesoKg > 2) {
        final pesoAdicional = (pesoKg - 2).ceil();
        valor += pesoAdicional * 2.0;
      }
      
      // Limite máximo
      if (valor > 50.0) {
        valor = 50.0;
      }

      // Frete grátis (pode ser configurado diferente para entregas rápidas)
      if (valorPedido >= valorMinimoFreteGratis) {
        valor = 0.0;
      }

      // Prazo: muito rápido (mesmo dia, até 2 horas)
      final prazo = 0; // 0 = mesmo dia

      return OpcaoFrete(
        id: 'entrega_rapida_${DateTime.now().millisecondsSinceEpoch}',
        nome: 'Entrega Rápida',
        tipo: 'entrega_rapida',
        valor: valor,
        prazo: prazo,
        descricao: 'Entrega no mesmo dia (até 2 horas) via iFood/Rappi',
        metadados: {
          'metodo': 'estimado',
          'distanciaKm': distanciaKm,
          'expresso': true,
          'mesmoDia': true,
        },
      );
    } catch (e) {
      debugPrint('>>> [FreteService] Erro ao calcular frete de entrega rápida: $e');
      return null;
    }
  }

  // ============================================
  // FUNÇÕES PARA INTEGRAÇÃO REAL COM APIs
  // ============================================
  // Estas funções serão chamadas quando houver credenciais configuradas
  // Implemente a integração real com as APIs das transportadoras aqui

  /// Calcula frete usando API real da Jadlog
  /// Documentação: https://www.jadlog.com.br/siteInstitucional/tecnologia
  /// API: https://www.jadlog.com.br/api/calcula-frete
  static Future<OpcaoFrete?> _calcularFreteJadlogAPI({
    required String cepOrigem,
    required String cepDestino,
    required double pesoTotal,
    required double valorPedido,
    required String token,
  }) async {
    try {
      debugPrint('>>> [FreteService] Calculando frete via API real da Jadlog...');
      
      // API da Jadlog - endpoint de cálculo de frete
      // Nota: Ajustar URL e estrutura conforme documentação oficial quando disponível
      final url = Uri.parse('https://www.jadlog.com.br/api/calcula-frete');
      
      final body = {
        'cepOrigem': cepOrigem.replaceAll(RegExp(r'[^\d]'), ''),
        'cepDestino': cepDestino.replaceAll(RegExp(r'[^\d]'), ''),
        'peso': (pesoTotal / 1000).toStringAsFixed(2), // converter para kg
        'valor': valorPedido.toStringAsFixed(2),
        'modalidade': 'EXPRESSO', // ou 'ECONOMICO' conforme necessidade
      };
      
      final response = await http.post(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: json.encode(body),
      ).timeout(const Duration(seconds: 15));
      
      debugPrint('>>> [FreteService] Jadlog API Status: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        // Estrutura de resposta pode variar - ajustar conforme documentação oficial
        final valor = _extrairValorFrete(data, ['valor', 'preco', 'frete']);
        final prazo = _extrairPrazoFrete(data, ['prazo', 'prazoEntrega', 'dias']);
        
        if (valor != null && valor > 0) {
          return OpcaoFrete(
            id: 'jadlog_api_${DateTime.now().millisecondsSinceEpoch}',
            nome: 'Jadlog',
            tipo: 'jadlog',
            valor: valor,
            prazo: prazo ?? 5,
            descricao: 'Entrega via Jadlog (API oficial)',
            metadados: {
              'metodo': 'api_real',
              'resposta': data.toString(),
            },
          );
        }
      } else {
        debugPrint('>>> [FreteService] Jadlog API retornou erro: ${response.statusCode} - ${response.body}');
      }
      
      return null;
    } catch (e, stackTrace) {
      debugPrint('>>> [FreteService] Erro ao calcular frete via API Jadlog: $e');
      debugPrint('>>> [FreteService] Stack: $stackTrace');
      return null;
    }
  }
  
  /// Helper para extrair valor de frete de diferentes formatos de resposta
  static double? _extrairValorFrete(Map<String, dynamic> data, List<String> keys) {
    for (var key in keys) {
      if (data.containsKey(key)) {
        final value = data[key];
        if (value is num) return value.toDouble();
        if (value is String) return double.tryParse(value.replaceAll(',', '.'));
      }
    }
    return null;
  }
  
  /// Helper para extrair prazo de entrega de diferentes formatos de resposta
  static int? _extrairPrazoFrete(Map<String, dynamic> data, List<String> keys) {
    for (var key in keys) {
      if (data.containsKey(key)) {
        final value = data[key];
        if (value is int) return value;
        if (value is num) return value.toInt();
        if (value is String) return int.tryParse(value);
      }
    }
    return null;
  }

  /// Calcula frete usando API real da Total Express
  /// Documentação: https://www.totalexpress.com.br/integracoes
  static Future<OpcaoFrete?> _calcularFreteTotalExpressAPI({
    required String cepOrigem,
    required String cepDestino,
    required double pesoTotal,
    required double valorPedido,
    required String token,
  }) async {
    try {
      debugPrint('>>> [FreteService] Calculando frete via API real da Total Express...');
      
      // API da Total Express - endpoint de cálculo
      final url = Uri.parse('https://api.totalexpress.com.br/v1/calcular');
      
      final body = {
        'cepOrigem': cepOrigem.replaceAll(RegExp(r'[^\d]'), ''),
        'cepDestino': cepDestino.replaceAll(RegExp(r'[^\d]'), ''),
        'peso': pesoTotal / 1000, // kg
        'valor': valorPedido,
        'tipoServico': 'EXPRESSO', // ou 'ECONOMICO'
      };
      
      final response = await http.post(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: json.encode(body),
      ).timeout(const Duration(seconds: 15));
      
      debugPrint('>>> [FreteService] Total Express API Status: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        final valor = _extrairValorFrete(data, ['valor', 'preco', 'frete', 'valorFrete']);
        final prazo = _extrairPrazoFrete(data, ['prazo', 'prazoEntrega', 'dias', 'prazoDias']);
        
        if (valor != null && valor > 0) {
          return OpcaoFrete(
            id: 'total_express_api_${DateTime.now().millisecondsSinceEpoch}',
            nome: 'Total Express',
            tipo: 'total_express',
            valor: valor,
            prazo: prazo ?? 5,
            descricao: 'Entrega via Total Express (API oficial)',
            metadados: {
              'metodo': 'api_real',
              'resposta': data.toString(),
            },
          );
        }
      } else {
        debugPrint('>>> [FreteService] Total Express API retornou erro: ${response.statusCode} - ${response.body}');
      }
      
      return null;
    } catch (e, stackTrace) {
      debugPrint('>>> [FreteService] Erro ao calcular frete via API Total Express: $e');
      debugPrint('>>> [FreteService] Stack: $stackTrace');
      return null;
    }
  }

  /// Calcula frete usando API real da Azul Cargo
  /// Documentação: https://www.azulcargo.com.br/integracoes
  static Future<OpcaoFrete?> _calcularFreteAzulCargoAPI({
    required String cepOrigem,
    required String cepDestino,
    required double pesoTotal,
    required double valorPedido,
    required String token,
  }) async {
    try {
      debugPrint('>>> [FreteService] Calculando frete via API real da Azul Cargo...');
      
      // API da Azul Cargo - endpoint de cálculo
      final url = Uri.parse('https://api.azulcargo.com.br/v1/calcular-frete');
      
      final body = {
        'cepOrigem': cepOrigem.replaceAll(RegExp(r'[^\d]'), ''),
        'cepDestino': cepDestino.replaceAll(RegExp(r'[^\d]'), ''),
        'peso': pesoTotal / 1000, // kg
        'valor': valorPedido,
      };
      
      final response = await http.post(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: json.encode(body),
      ).timeout(const Duration(seconds: 15));
      
      debugPrint('>>> [FreteService] Azul Cargo API Status: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        final valor = _extrairValorFrete(data, ['valor', 'preco', 'frete', 'valorFrete', 'total']);
        final prazo = _extrairPrazoFrete(data, ['prazo', 'prazoEntrega', 'dias', 'prazoDias']);
        
        if (valor != null && valor > 0) {
          return OpcaoFrete(
            id: 'azul_cargo_api_${DateTime.now().millisecondsSinceEpoch}',
            nome: 'Azul Cargo',
            tipo: 'azul_cargo',
            valor: valor,
            prazo: prazo ?? 3,
            descricao: 'Entrega via Azul Cargo (API oficial)',
            metadados: {
              'metodo': 'api_real',
              'resposta': data.toString(),
            },
          );
        }
      } else {
        debugPrint('>>> [FreteService] Azul Cargo API retornou erro: ${response.statusCode} - ${response.body}');
      }
      
      return null;
    } catch (e, stackTrace) {
      debugPrint('>>> [FreteService] Erro ao calcular frete via API Azul Cargo: $e');
      debugPrint('>>> [FreteService] Stack: $stackTrace');
      return null;
    }
  }

  /// Calcula frete usando API real da Loggi (GraphQL)
  /// Documentação: https://developers.loggi.com/
  static Future<OpcaoFrete?> _calcularFreteLoggiAPI({
    required String cepOrigem,
    required String cepDestino,
    required double pesoTotal,
    required double valorPedido,
    required String token,
  }) async {
    try {
      debugPrint('>>> [FreteService] Calculando frete via API real da Loggi...');
      
      // Loggi usa GraphQL API
      final url = Uri.parse('https://www.loggi.com/graphql/');
      
      final query = '''
        query {
          calculateShipping(
            originZipcode: "${cepOrigem.replaceAll(RegExp(r'[^\d]'), '')}",
            destinationZipcode: "${cepDestino.replaceAll(RegExp(r'[^\d]'), '')}",
            weight: ${(pesoTotal / 1000).toStringAsFixed(2)}
          ) {
            price
            estimatedTime
          }
        }
      ''';
      
      final response = await http.post(
        url,
        headers: {
          'Authorization': 'ApiKey $token',
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: json.encode({
          'query': query,
        }),
      ).timeout(const Duration(seconds: 15));
      
      debugPrint('>>> [FreteService] Loggi API Status: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final shipping = data['data']?['calculateShipping'];
        
        if (shipping != null) {
          final valor = shipping['price']?.toDouble();
          final estimatedTime = shipping['estimatedTime'];
          
          if (valor != null && valor > 0) {
            // Converter estimatedTime (minutos) para dias úteis
            int prazo = 1;
            if (estimatedTime != null) {
              final minutos = estimatedTime is int ? estimatedTime : (estimatedTime is num ? estimatedTime.toInt() : 0);
              prazo = (minutos / (8 * 60)).ceil(); // 8 horas de trabalho por dia
              if (prazo < 1) prazo = 1;
            }
            
            return OpcaoFrete(
              id: 'loggi_api_${DateTime.now().millisecondsSinceEpoch}',
              nome: 'Loggi Express',
              tipo: 'loggi',
              valor: valor,
              prazo: prazo,
              descricao: 'Entrega rápida via Loggi (API oficial)',
              metadados: {
                'metodo': 'api_real',
                'resposta': data.toString(),
              },
            );
          }
        }
      } else {
        debugPrint('>>> [FreteService] Loggi API retornou erro: ${response.statusCode} - ${response.body}');
      }
      
      return null;
    } catch (e, stackTrace) {
      debugPrint('>>> [FreteService] Erro ao calcular frete via API Loggi: $e');
      debugPrint('>>> [FreteService] Stack: $stackTrace');
      return null;
    }
  }

  /// Calcula frete usando Melhor Envio (plataforma unificada)
  /// Documentação: https://melhorenvio.com.br/api-docs/
  /// O Melhor Envio calcula frete de múltiplas transportadoras de uma vez
  static Future<List<OpcaoFrete>> _calcularFreteMelhorEnvio({
    required String cepOrigem,
    required String cepDestino,
    required double pesoTotal,
    required double valorPedido,
    required String token,
    String? email,
  }) async {
    final opcoes = <OpcaoFrete>[];
    
    try {
      debugPrint('>>> [FreteService] Calculando frete via Melhor Envio...');
      
      // API do Melhor Envio - endpoint de cálculo
      final url = Uri.parse('https://melhorenvio.com.br/api/v2/me/shipment/calculate');
      
      final body = {
        'from': {
          'postal_code': cepOrigem.replaceAll(RegExp(r'[^\d]'), ''),
        },
        'to': {
          'postal_code': cepDestino.replaceAll(RegExp(r'[^\d]'), ''),
        },
        'products': [
          {
            'weight': pesoTotal / 1000, // kg
            'width': 20, // cm (padrão)
            'height': 5, // cm (padrão)
            'length': 15, // cm (padrão)
            'insurance_value': valorPedido,
            'quantity': 1,
          }
        ],
      };
      
      final headers = {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'User-Agent': 'Sistema Exodo',
      };
      
      if (email != null) {
        headers['X-User-Email'] = email;
      }
      
      final response = await http.post(
        url,
        headers: headers,
        body: json.encode(body),
      ).timeout(const Duration(seconds: 20));
      
      debugPrint('>>> [FreteService] Melhor Envio API Status: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        // Melhor Envio retorna uma lista de opções de diferentes transportadoras
        if (data is List) {
          for (var item in data) {
            final nome = item['name'] ?? item['company']?['name'] ?? 'Transportadora';
            final valor = (item['price'] ?? item['price_cash'] ?? 0.0).toDouble();
            final prazo = item['delivery_time'] ?? item['delivery_range']?['min'] ?? 0;
            
            if (valor > 0) {
              opcoes.add(OpcaoFrete(
                id: 'melhor_envio_${item['id'] ?? DateTime.now().millisecondsSinceEpoch}',
                nome: nome,
                tipo: 'melhor_envio',
                valor: valor,
                prazo: prazo is int ? prazo : (prazo is num ? prazo.toInt() : 5),
                descricao: 'Entrega via $nome (Melhor Envio)',
                metadados: {
                  'metodo': 'api_real',
                  'melhor_envio_id': item['id']?.toString(),
                  'company_id': item['company']?['id']?.toString(),
                },
              ));
            }
          }
        } else if (data is Map) {
          // Se retornar um único objeto
          final valor = (data['price'] ?? data['price_cash'] ?? 0.0).toDouble();
          final prazo = data['delivery_time'] ?? data['delivery_range']?['min'] ?? 0;
          
          if (valor > 0) {
            opcoes.add(OpcaoFrete(
              id: 'melhor_envio_${data['id'] ?? DateTime.now().millisecondsSinceEpoch}',
              nome: data['name'] ?? data['company']?['name'] ?? 'Melhor Envio',
              tipo: 'melhor_envio',
              valor: valor,
              prazo: prazo is int ? prazo : (prazo is num ? prazo.toInt() : 5),
              descricao: 'Entrega via Melhor Envio (API oficial)',
              metadados: {
                'metodo': 'api_real',
                'melhor_envio_id': data['id']?.toString(),
              },
            ));
          }
        }
        
        debugPrint('>>> [FreteService] Melhor Envio retornou ${opcoes.length} opções');
      } else {
        debugPrint('>>> [FreteService] Melhor Envio API retornou erro: ${response.statusCode} - ${response.body}');
      }
    } catch (e, stackTrace) {
      debugPrint('>>> [FreteService] Erro ao calcular frete via Melhor Envio: $e');
      debugPrint('>>> [FreteService] Stack: $stackTrace');
    }
    
    return opcoes;
  }

  /// Calcula frete usando Zonas de Entrega Inteligentes
  /// Prioriza: Bairro > Cidade > Raio > Região
  static Future<OpcaoFrete?> _calcularFretePorZona({
    required List<ZonaEntrega> zonasEntrega,
    String? cepOrigem,
    String? cepDestino,
    String? bairroOrigem,
    String? cidadeOrigem,
    String? bairroDestino,
    String? cidadeDestino,
    required String estadoOrigem,
    required String estadoDestino,
    required double valorPedido,
    required double valorMinimoFreteGratis,
  }) async {
    try {
      // Filtrar apenas zonas ativas e ordenar por prioridade
      final zonasAtivas = zonasEntrega
          .where((z) => z.ativo)
          .toList()
        ..sort((a, b) => a.prioridade.compareTo(b.prioridade));

      if (zonasAtivas.isEmpty) return null;

      // 1. PRIORIDADE: Verificar zona por BAIRRO
      if (bairroDestino != null && bairroDestino.isNotEmpty) {
        try {
          final zonaBairro = zonasAtivas.firstWhere(
            (z) => z.tipo == 'bairro' &&
                z.bairro != null &&
                z.bairro!.toLowerCase().trim() == bairroDestino.toLowerCase().trim() &&
                (z.cidade == null || 
                 cidadeDestino == null || 
                 z.cidade!.toLowerCase().trim() == cidadeDestino.toLowerCase().trim()),
          );

          if (zonaBairro.tipo == 'bairro' && zonaBairro.bairro != null) {
            return _criarOpcaoFreteZona(zonaBairro, valorPedido, valorMinimoFreteGratis);
          }
        } catch (_) {
          // Nenhuma zona de bairro encontrada, continuar
        }
      }

      // 2. PRIORIDADE: Verificar zona por CIDADE
      if (cidadeDestino != null && cidadeDestino.isNotEmpty) {
        try {
          final zonaCidade = zonasAtivas.firstWhere(
            (z) => z.tipo == 'cidade' &&
                z.cidade != null &&
                z.cidade!.toLowerCase().trim() == cidadeDestino.toLowerCase().trim() &&
                (z.estado == null || 
                 estadoDestino.isEmpty || 
                 z.estado!.toUpperCase() == estadoDestino.toUpperCase()),
          );

          if (zonaCidade.tipo == 'cidade' && zonaCidade.cidade != null) {
            return _criarOpcaoFreteZona(zonaCidade, valorPedido, valorMinimoFreteGratis);
          }
        } catch (_) {
          // Nenhuma zona de cidade encontrada, continuar
        }
      }

      // 3. PRIORIDADE: Verificar zona por RAIO (requer coordenadas)
      if (cepOrigem != null && cepDestino != null && 
          cepOrigem.replaceAll(RegExp(r'[^\d]'), '').length == 8 &&
          cepDestino.replaceAll(RegExp(r'[^\d]'), '').length == 8) {
        try {
          final coordenadasOrigem = await _obterCoordenadasPorCEP(cepOrigem);
          final coordenadasDestino = await _obterCoordenadasPorCEP(cepDestino);

          if (coordenadasOrigem != null && coordenadasDestino != null) {
            final distanciaKm = _calcularDistancia(
              coordenadasOrigem['lat']!,
              coordenadasOrigem['lon']!,
              coordenadasDestino['lat']!,
              coordenadasDestino['lon']!,
            );

            // Procurar zona por raio que contenha a distância
            for (var zona in zonasAtivas) {
              if (zona.tipo == 'raio' && 
                  zona.raioKm != null && 
                  distanciaKm <= zona.raioKm!) {
                return _criarOpcaoFreteZonaComDistancia(
                  zona, 
                  distanciaKm, 
                  valorPedido, 
                  valorMinimoFreteGratis,
                );
              }
            }
          }
        } catch (e) {
          debugPrint('>>> [FreteService] Erro ao calcular distância para zona: $e');
        }
      }

      // 4. PRIORIDADE: Verificar zona por REGIÃO (mesmo estado)
      if (estadoOrigem.isNotEmpty && estadoDestino.isNotEmpty &&
          estadoOrigem.toUpperCase() == estadoDestino.toUpperCase()) {
        try {
          final zonaRegiao = zonasAtivas.firstWhere(
            (z) => z.tipo == 'regiao' &&
                z.estado != null &&
                z.estado!.toUpperCase() == estadoDestino.toUpperCase(),
          );

          if (zonaRegiao.tipo == 'regiao' && zonaRegiao.estado != null) {
            return _criarOpcaoFreteZona(zonaRegiao, valorPedido, valorMinimoFreteGratis);
          }
        } catch (_) {
          // Nenhuma zona de região encontrada, continuar
        }
      }

      return null;
    } catch (e, stackTrace) {
      debugPrint('>>> [FreteService] Erro ao calcular frete por zona: $e');
      debugPrint('>>> [FreteService] Stack: $stackTrace');
      return null;
    }
  }

  /// Cria OpcaoFrete a partir de uma ZonaEntrega
  static OpcaoFrete _criarOpcaoFreteZona(
    ZonaEntrega zona,
    double valorPedido,
    double valorMinimoFreteGratis,
  ) {
    double valor = zona.taxaFixa;

    // Frete grátis para pedidos acima do valor mínimo
    if (valorPedido >= valorMinimoFreteGratis) {
      valor = 0.0;
    }

    // Calcular prazo médio
    final prazo = ((zona.prazoMinimo + zona.prazoMaximo) / 2).ceil();

    return OpcaoFrete(
      id: 'zona_${zona.id}_${DateTime.now().millisecondsSinceEpoch}',
      nome: zona.nome,
      tipo: 'zona_entrega',
      valor: valor,
      prazo: prazo,
      descricao: 'Entrega ${zona.tipo == 'bairro' ? 'no bairro' : zona.tipo == 'cidade' ? 'na cidade' : 'na região'}',
      metadados: {
        'zonaId': zona.id,
        'tipo': zona.tipo,
        'metodo': 'zona_inteligente',
      },
    );
  }

  /// Cria OpcaoFrete a partir de uma ZonaEntrega com cálculo por distância
  static OpcaoFrete _criarOpcaoFreteZonaComDistancia(
    ZonaEntrega zona,
    double distanciaKm,
    double valorPedido,
    double valorMinimoFreteGratis,
  ) {
    double valor = zona.taxaFixa;

    // Adicionar taxa por km se configurada
    if (zona.taxaPorKm != null && zona.taxaPorKm! > 0) {
      valor += distanciaKm * zona.taxaPorKm!;
    }

    // Frete grátis para pedidos acima do valor mínimo
    if (valorPedido >= valorMinimoFreteGratis) {
      valor = 0.0;
    }

    // Calcular prazo baseado na distância (mais próximo = mais rápido)
    int prazo = zona.prazoMinimo;
    if (distanciaKm > 10) {
      prazo = zona.prazoMaximo;
    } else if (distanciaKm > 5) {
      prazo = ((zona.prazoMinimo + zona.prazoMaximo) / 2).ceil();
    }

    return OpcaoFrete(
      id: 'zona_raio_${zona.id}_${DateTime.now().millisecondsSinceEpoch}',
      nome: zona.nome,
      tipo: 'zona_entrega',
      valor: valor,
      prazo: prazo,
      descricao: 'Entrega por raio (${distanciaKm.toStringAsFixed(1)} km)',
      metadados: {
        'zonaId': zona.id,
        'tipo': 'raio',
        'distanciaKm': distanciaKm,
        'metodo': 'zona_inteligente',
      },
    );
  }
}

