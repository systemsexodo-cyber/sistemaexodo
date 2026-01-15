import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:xml/xml.dart' as xml;
import 'dart:convert';
import '../models/produto.dart';
import '../models/nota_entrada.dart';
import '../services/data_service.dart';
import '../services/codigo_service.dart';
import '../services/grupos_manager.dart';
import '../theme.dart';
import 'package:intl/intl.dart';

class EntradaMercadoriasPage extends StatefulWidget {
  const EntradaMercadoriasPage({super.key});

  @override
  State<EntradaMercadoriasPage> createState() => _EntradaMercadoriasPageState();
}

class _EntradaMercadoriasPageState extends State<EntradaMercadoriasPage> with SingleTickerProviderStateMixin {
  final _formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  final _formatoPercentual = NumberFormat.percentPattern('pt_BR');
  
  late TabController _tabController;
  
  List<_ItemEntrada> _itens = [];
  bool _carregando = false;
  String _modo = 'xml'; // 'xml' ou 'manual'
  final TextEditingController _buscaController = TextEditingController();
  String _busca = '';
  int _abaAtiva = 0; // 0 = Itens, 1 = Notas
  String? _notaRascunhoId; // ID da nota rascunho atual
  String? _numeroNotaReal; // Número real da nota fiscal (do XML)
  
  // Filtros e busca para aba de Notas
  final TextEditingController _buscaNotasController = TextEditingController();
  final TextEditingController _filtroFornecedorController = TextEditingController();
  String? _filtroStatus; // 'rascunho', 'processada', 'cancelada', null = todos
  DateTime? _filtroDataInicio;
  DateTime? _filtroDataFim;
  // Informações adicionais do XML
  
  // Função para extrair grupo do XML baseado no NCM ou categoria
  String _extrairGrupoDoXML(xml.XmlElement prod) {
    try {
      // Tentar buscar NCM (pode estar como NCM ou nCM)
      String ncm = '';
      try {
        var ncmElements = prod.findElements('NCM');
        if (ncmElements.isEmpty) {
          ncmElements = prod.findElements('nCM');
        }
        if (ncmElements.isNotEmpty) {
          ncm = ncmElements.first.text.trim();
        }
      } catch (_) {}
      
      // Tentar buscar categoria ou grupo diretamente (se existir no XML)
      String categoria = '';
      try {
        final categoriaElements = prod.findElements('categoria');
        if (categoriaElements.isNotEmpty) {
          categoria = categoriaElements.first.text.trim();
        } else {
          final grupoElements = prod.findElements('grupo');
          if (grupoElements.isNotEmpty) {
            categoria = grupoElements.first.text.trim();
          }
        }
      } catch (_) {}
      
      // Se encontrou categoria/grupo no XML, usar e cadastrar
      if (categoria.isNotEmpty) {
        _cadastrarGrupoSeNaoExistir(categoria);
        return categoria;
      }
      
      // Se não encontrou, tentar mapear pelo NCM (primeiros 2 dígitos indicam a categoria)
      if (ncm.isNotEmpty && ncm.length >= 2) {
        final ncmPrefix = ncm.substring(0, 2);
        String grupoMapeado = 'Sem Grupo';
        
        // Mapeamento básico de NCM para grupos comuns
        switch (ncmPrefix) {
          case '84': // Máquinas e aparelhos mecânicos
          case '85': // Máquinas e aparelhos elétricos
            grupoMapeado = 'Hardware';
            break;
          case '90': // Instrumentos de óptica, precisão
            grupoMapeado = 'Periféricos';
            break;
          case '39': // Plásticos
          case '40': // Borracha
            grupoMapeado = 'Acessórios';
            break;
          case '61': // Vestuário de malha
          case '62': // Vestuário não de malha
            grupoMapeado = 'Vestuário';
            break;
          case '64': // Calçados
            grupoMapeado = 'Calçados';
            break;
          case '30': // Produtos farmacêuticos
            grupoMapeado = 'Farmácia';
            break;
          case '22': // Bebidas
            grupoMapeado = 'Bebidas';
            break;
          case '09': // Café, chá, mate
          case '19': // Preparações à base de cereais
            grupoMapeado = 'Alimentos';
            break;
          default:
            grupoMapeado = 'Sem Grupo';
        }
        
        // Cadastrar grupo mapeado se não for "Sem Grupo"
        if (grupoMapeado != 'Sem Grupo') {
          _cadastrarGrupoSeNaoExistir(grupoMapeado);
        }
        
        return grupoMapeado;
      }
      
      return 'Sem Grupo';
    } catch (e) {
      print('>>> Erro ao extrair grupo do XML: $e');
      return 'Sem Grupo';
    }
  }
  
  // Função para cadastrar grupo se não existir
  void _cadastrarGrupoSeNaoExistir(String grupo) {
    if (grupo.isNotEmpty && grupo != 'Sem Grupo') {
      final gruposManager = GruposManager();
      if (!gruposManager.existeGrupo(grupo)) {
        gruposManager.adicionarGrupo(grupo);
        print('>>> Grupo "$grupo" cadastrado automaticamente');
      }
    }
  }
  String? _chaveNFe;
  String? _fornecedorNome;
  String? _fornecedorCNPJ;
  DateTime? _dataEmissao;
  double? _valorTotal;
  String? _serie;
  String? _modelo;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this, initialIndex: _itens.isEmpty ? 1 : _abaAtiva);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {
          _abaAtiva = _tabController.index;
        });
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _buscaController.dispose();
    _buscaNotasController.dispose();
    _filtroFornecedorController.dispose();
    for (var item in _itens) {
      item.dispose();
    }
    super.dispose();
  }


  Future<void> _carregarXML() async {
    // Limpar estado anterior antes de carregar novo XML
    setState(() {
      _itens.clear();
      _numeroNotaReal = null;
      _notaRascunhoId = null;
      _chaveNFe = null;
      _fornecedorNome = null;
      _fornecedorCNPJ = null;
      _dataEmissao = null;
      _valorTotal = null;
      _serie = null;
      _modelo = null;
    });
    
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xml'],
        withData: true, // Importante: ler os bytes do arquivo
      );

      if (result != null && result.files.isNotEmpty) {
        setState(() => _carregando = true);

        // Ler o arquivo - usar bytes (funciona em todas as plataformas)
        String xmlString;
        final file = result.files.single;
        
        print('>>> Arquivo selecionado: ${file.name}');
        print('>>> Tamanho do arquivo: ${file.size} bytes');
        
        if (file.bytes != null && file.bytes!.isNotEmpty) {
          // Ler dos bytes (funciona em web e desktop)
          xmlString = utf8.decode(file.bytes!);
          print('>>> XML decodificado com sucesso, ${xmlString.length} caracteres');
        } else {
          setState(() => _carregando = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Erro: Não foi possível ler o conteúdo do arquivo XML. Tente selecionar o arquivo novamente.'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }
        
        print('>>> XML carregado, tamanho: ${xmlString.length} caracteres');
        
        xml.XmlDocument document;
        try {
          document = xml.XmlDocument.parse(xmlString);
          print('>>> XML parseado com sucesso');
        } catch (e) {
          print('>>> ERRO ao parsear XML: $e');
          setState(() => _carregando = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Erro ao processar XML: $e'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }

        _itens.clear();
        print('>>> Lista de itens limpa, iniciando processamento...');

        // Extrair número real da nota fiscal
        String? numeroNotaReal;
        try {
          // Tentar encontrar nNF (número da nota fiscal)
          final ideElements = document.findAllElements('ide');
          if (ideElements.isNotEmpty) {
            final nNF = ideElements.first.findElements('nNF');
            if (nNF.isNotEmpty) {
              numeroNotaReal = nNF.first.text;
            }
          }
        } catch (e) {
          print('Erro ao extrair número da nota: $e');
        }

        _numeroNotaReal = numeroNotaReal;

        // Extrair informações adicionais do XML
        try {
          // Extrair chave de acesso (infNFe)
          final infNFeElements = document.findAllElements('infNFe');
          if (infNFeElements.isNotEmpty) {
            final chaveAttr = infNFeElements.first.getAttribute('Id');
            if (chaveAttr != null && chaveAttr.startsWith('NFe')) {
              _chaveNFe = chaveAttr.substring(3); // Remove o prefixo "NFe"
            }
          }

          // Extrair informações do emitente (fornecedor)
          final emitElements = document.findAllElements('emit');
          if (emitElements.isNotEmpty) {
            final emit = emitElements.first;
            
            // Nome do fornecedor
            final xNome = emit.findElements('xNome');
            if (xNome.isNotEmpty) {
              _fornecedorNome = xNome.first.text;
            }
            
            // CNPJ do fornecedor
            final cnpj = emit.findElements('CNPJ');
            if (cnpj.isNotEmpty) {
              _fornecedorCNPJ = cnpj.first.text;
            } else {
              // Tentar CPF se não tiver CNPJ
              final cpf = emit.findElements('CPF');
              if (cpf.isNotEmpty) {
                _fornecedorCNPJ = cpf.first.text;
              }
            }
          }

          // Extrair informações do IDE (identificação)
          final ideElements = document.findAllElements('ide');
          if (ideElements.isNotEmpty) {
            final ide = ideElements.first;
            
            // Série
            final serie = ide.findElements('serie');
            if (serie.isNotEmpty) {
              _serie = serie.first.text;
            }
            
            // Modelo
            final modelo = ide.findElements('mod');
            if (modelo.isNotEmpty) {
              _modelo = modelo.first.text;
            }
            
            // Data de emissão
            final dhEmi = ide.findElements('dhEmi');
            if (dhEmi.isNotEmpty) {
              try {
                final dataStr = dhEmi.first.text;
                // Formato: 2024-01-15T10:30:00-03:00
                _dataEmissao = DateTime.parse(dataStr);
              } catch (e) {
                print('Erro ao parsear data de emissão: $e');
              }
            } else {
              // Tentar dEmi (data simples)
              final dEmi = ide.findElements('dEmi');
              if (dEmi.isNotEmpty) {
                try {
                  final dataStr = dEmi.first.text;
                  // Formato: 20240115
                  if (dataStr.length == 8) {
                    _dataEmissao = DateTime.parse('${dataStr.substring(0, 4)}-${dataStr.substring(4, 6)}-${dataStr.substring(6, 8)}');
                  }
                } catch (e) {
                  print('Erro ao parsear data de emissão (dEmi): $e');
                }
              }
            }
          }

          // Extrair valor total
          final totalElements = document.findAllElements('total');
          if (totalElements.isNotEmpty) {
            final icmTot = totalElements.first.findElements('ICMSTot');
            if (icmTot.isNotEmpty) {
              final vNF = icmTot.first.findElements('vNF');
              if (vNF.isNotEmpty) {
                _valorTotal = double.tryParse(vNF.first.text.replaceAll(',', '.'));
              }
            }
          }

          print('>>> Informações extraídas do XML:');
          print('>>>   Chave NFe: $_chaveNFe');
          print('>>>   Fornecedor: $_fornecedorNome');
          print('>>>   CNPJ: $_fornecedorCNPJ');
          print('>>>   Data Emissão: $_dataEmissao');
          print('>>>   Valor Total: $_valorTotal');
          print('>>>   Série: $_serie');
          print('>>>   Modelo: $_modelo');
        } catch (e) {
          print('Erro ao extrair informações adicionais do XML: $e');
        }

        // Verificar se nota já foi processada (apenas avisar, não impedir carregamento)
        // Nota: notas canceladas/excluídas não bloqueiam o processamento
        bool notaJaProcessada = false;
        if (numeroNotaReal != null && numeroNotaReal.isNotEmpty) {
          final service = Provider.of<DataService>(context, listen: false);
          
          // Buscar todas as notas com o mesmo número
          final notasComMesmoNumero = service.notasEntrada.where(
            (n) => n.numeroNotaReal == numeroNotaReal,
          ).toList();
          
          print('>>> Verificando duplicatas no carregamento XML para nota $numeroNotaReal');
          print('>>> Encontradas ${notasComMesmoNumero.length} nota(s) com este número');
          
          // Filtrar apenas notas processadas e não canceladas
          final notasProcessadasAtivas = notasComMesmoNumero.where(
            (n) => n.isProcessada && !n.isCancelada,
          ).toList();
          
          if (notasProcessadasAtivas.isNotEmpty) {
            notaJaProcessada = true;
            print('>>> Nota $numeroNotaReal já foi processada anteriormente (mas pode ser processada novamente)');
          } else {
            print('>>> Nota $numeroNotaReal não encontrada ou foi excluída - pode processar normalmente');
          }
        } else {
          print('>>> Número da nota não encontrado no XML - processando normalmente');
        }
        
        // LIMPAR ESTADO ANTES DE CARREGAR NOVO XML
        setState(() {
          // Limpar itens anteriores
          for (var item in _itens) {
            item.dispose();
          }
          _itens.clear();
          
          // Limpar campos da nota anterior (mas manter os novos que foram extraídos do XML)
          // Não limpar _numeroNotaReal, _chaveNFe, etc. pois foram recém extraídos do XML
          _notaRascunhoId = null;
          _modo = 'xml';
          _abaAtiva = 0; // Ir para aba de itens
        });

        // Tentar parsear NFe
        final detElements = document.findAllElements('det');
        print('>>> Encontrados ${detElements.length} elementos <det> no XML');
        
        if (detElements.isEmpty) {
          // Tentar outros formatos de XML
          print('>>> Tentando buscar elementos alternativos...');
          final prodElements = document.findAllElements('prod');
          print('>>> Encontrados ${prodElements.length} elementos <prod> no XML');
          
          // Se não encontrou <det>, tentar buscar <prod> diretamente
          if (prodElements.isNotEmpty) {
            print('>>> Processando elementos <prod> diretamente...');
            for (var prod in prodElements) {
              try {
                final codigo = prod.findElements('cProd').isEmpty 
                    ? '' 
                    : prod.findElements('cProd').first.text;
                final nome = prod.findElements('xProd').isEmpty 
                    ? '' 
                    : prod.findElements('xProd').first.text;
                
                if (nome.isEmpty) {
                  print('>>> Item sem nome encontrado, pulando...');
                  continue;
                }
                
                final quantidade = prod.findElements('qCom').isEmpty
                    ? 0.0
                    : (double.tryParse(
                        prod.findElements('qCom').first.text.replaceAll(',', '.')
                      ) ?? 0.0);
                final valorUnitario = prod.findElements('vUnCom').isEmpty
                    ? 0.0
                    : (double.tryParse(
                        prod.findElements('vUnCom').first.text.replaceAll(',', '.')
                      ) ?? 0.0);
                
                String? codigoBarras;
                try {
                  final cEAN = prod.findElements('cEAN');
                  if (cEAN.isNotEmpty) {
                    final codigoBarrasText = cEAN.first.text;
                    if (codigoBarrasText.isNotEmpty && codigoBarrasText != 'SEM GTIN') {
                      codigoBarras = codigoBarrasText;
                    }
                  }
                } catch (_) {}
                
            String unidade = 'UN';
            try {
              final uCom = prod.findElements('uCom');
              if (uCom.isNotEmpty) {
                unidade = uCom.first.text;
              }
            } catch (_) {}

            String codigoFinal = codigo;
            
            // Extrair grupo do XML
            String grupo = _extrairGrupoDoXML(prod);
            // Cadastrar grupo se não existir
            _cadastrarGrupoSeNaoExistir(grupo);
            
            // Calcular preço de venda (se não houver no XML, usar margem padrão de 50% sobre o custo)
            double precoVendaCalculado = valorUnitario > 0 
                ? valorUnitario * 1.5  // Margem de 50% sobre o custo
                : 0.0;
            
            // Se produto existe, usar o preço atual dele e manter o grupo existente
            final produtoExistente = _buscarProdutoPorCodigo(codigoFinal);
            if (produtoExistente != null) {
              precoVendaCalculado = produtoExistente.preco;
              // Se o produto já existe, usar o grupo dele em vez do extraído do XML
              grupo = produtoExistente.grupo;
            }
            
            print('>>> Item processado (prod direto): $nome - Qtd: $quantidade - Código: $codigoFinal - Custo: $valorUnitario - Venda: $precoVendaCalculado - Grupo: $grupo');
            _itens.add(_ItemEntrada(
              codigo: codigoFinal,
              codigoBarras: codigoBarras,
              nome: nome,
              quantidade: quantidade,
              quantidadeEmbalagens: quantidade,
              quantidadePorEmbalagem: 1,
              precoCusto: valorUnitario,
              precoVenda: precoVendaCalculado,
              unidade: unidade,
              grupo: grupo,
              produtoExistente: produtoExistente,
            ));
              } catch (e, stackTrace) {
                print('>>> Erro ao processar item (prod direto): $e');
                print('>>> Stack trace: $stackTrace');
              }
            }
          }
        }
        
        int itensProcessados = 0;
        for (var det in detElements) {
          try {
            final prod = det.findElements('prod');
            if (prod.isEmpty) {
              print('>>> Elemento <det> sem <prod> encontrado, pulando...');
              continue;
            }
            
            final codigo = prod.first.findElements('cProd').isEmpty 
                ? '' 
                : prod.first.findElements('cProd').first.text;
            final nome = prod.first.findElements('xProd').isEmpty 
                ? '' 
                : prod.first.findElements('xProd').first.text;
            
            if (nome.isEmpty) {
              print('>>> Item sem nome encontrado, pulando...');
              continue;
            }
            
            final quantidade = prod.first.findElements('qCom').isEmpty
                ? 0.0
                : (double.tryParse(
                    prod.first.findElements('qCom').first.text.replaceAll(',', '.')
                  ) ?? 0.0);
            final valorUnitario = prod.first.findElements('vUnCom').isEmpty
                ? 0.0
                : (double.tryParse(
                    prod.first.findElements('vUnCom').first.text.replaceAll(',', '.')
                  ) ?? 0.0);
            
            // Buscar código de barras se existir
            String? codigoBarras;
            try {
              final cEAN = prod.first.findElements('cEAN');
              if (cEAN.isNotEmpty) {
                final codigoBarrasText = cEAN.first.text;
                if (codigoBarrasText.isNotEmpty && codigoBarrasText != 'SEM GTIN') {
                  codigoBarras = codigoBarrasText;
                }
              }
            } catch (_) {}

            // Buscar unidade
            String unidade = 'UN';
            try {
              final uCom = prod.first.findElements('uCom');
              if (uCom.isNotEmpty) {
                unidade = uCom.first.text;
              }
            } catch (_) {}

            // Manter o código original da nota exatamente como vem, mesmo se estiver vazio
            String codigoFinal = codigo;
            
            // Extrair grupo do XML
            String grupo = _extrairGrupoDoXML(prod.first);
            // Cadastrar grupo se não existir
            _cadastrarGrupoSeNaoExistir(grupo);
            
            // Calcular preço de venda (se não houver no XML, usar margem padrão de 50% sobre o custo)
            double precoVendaCalculado = valorUnitario > 0 
                ? valorUnitario * 1.5  // Margem de 50% sobre o custo
                : 0.0;
            
            // Se produto existe, usar o preço atual dele e manter o grupo existente
            final produtoExistente = _buscarProdutoPorCodigo(codigoFinal);
            if (produtoExistente != null) {
              precoVendaCalculado = produtoExistente.preco;
              // Se o produto já existe, usar o grupo dele em vez do extraído do XML
              grupo = produtoExistente.grupo;
            }

            print('>>> Item processado: $nome - Qtd: $quantidade - Código: $codigoFinal - Custo: $valorUnitario - Venda: $precoVendaCalculado - Grupo: $grupo');
            _itens.add(_ItemEntrada(
              codigo: codigoFinal,
              codigoBarras: codigoBarras,
              nome: nome,
              quantidade: quantidade,
              quantidadeEmbalagens: quantidade, // Inicialmente igual à quantidade do XML
              quantidadePorEmbalagem: 1, // Padrão: 1 item por embalagem
              precoCusto: valorUnitario,
              precoVenda: precoVendaCalculado,
              unidade: unidade,
              grupo: grupo,
              produtoExistente: produtoExistente,
            ));
            itensProcessados++;
          } catch (e, stackTrace) {
            print('>>> Erro ao processar item: $e');
            print('>>> Stack trace: $stackTrace');
          }
        }
        
        print('>>> Total de itens processados: $itensProcessados de ${detElements.length} elementos <det>');
        print('>>> Total de itens na lista: ${_itens.length}');

        setState(() {
          _carregando = false;
          _modo = 'xml';
        });
        
        print('>>> Estado atualizado, _itens.length = ${_itens.length}');

        // Mostrar mensagens apropriadas
        if (_itens.isEmpty) {
          print('>>> AVISO: Nenhum item foi adicionado à lista após processar XML');
          print('>>> Verifique os logs acima para identificar o problema');
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Nenhum item encontrado no XML. Verifique o console para mais detalhes.'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 5),
            ),
          );
        } else {
          print('>>> SUCESSO: ${_itens.length} item(ns) carregado(s) e adicionados à lista');
          
          // Ir para aba de itens imediatamente
          setState(() {
            _abaAtiva = 0;
          });
          // Forçar atualização do TabController
          if (mounted) {
            _tabController.animateTo(0);
          }
          
          // Se a nota já foi processada, mostrar aviso adicional
          if (notaJaProcessada) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Atenção: A nota fiscal $numeroNotaReal já foi processada anteriormente! ${_itens.length} item(ns) carregado(s) do XML.',
                ),
                backgroundColor: Colors.orange,
                duration: const Duration(seconds: 6),
              ),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('${_itens.length} item(ns) carregado(s) do XML com sucesso!'),
                backgroundColor: Colors.green,
                duration: const Duration(seconds: 3),
              ),
            );
          }
        }
      }
    } catch (e) {
      setState(() => _carregando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao carregar XML: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// Busca produto por código (interno, código de barras ou código do fornecedor)
  Produto? _buscarProdutoPorCodigo(String codigo) {
    final service = Provider.of<DataService>(context, listen: false);
    try {
      return service.produtos.firstWhere(
        (p) => 
          p.codigo == codigo || 
          p.codigoBarras == codigo ||
          p.temCodigoFornecedor(codigo),
      );
    } catch (_) {
      return null;
    }
  }
  
  /// Busca produto por nome (para matching inteligente)
  Produto? _buscarProdutoPorNome(String nome) {
    final service = Provider.of<DataService>(context, listen: false);
    try {
      // Busca exata primeiro
      return service.produtos.firstWhere(
        (p) => p.nome.toLowerCase().trim() == nome.toLowerCase().trim(),
      );
    } catch (_) {
      // Se não encontrar exato, tenta busca parcial
      try {
        return service.produtos.firstWhere(
          (p) => p.nome.toLowerCase().contains(nome.toLowerCase().trim()) ||
                 nome.toLowerCase().trim().contains(p.nome.toLowerCase()),
        );
      } catch (_) {
        return null;
      }
    }
  }

  void _adicionarItemManual() {
    final service = Provider.of<DataService>(context, listen: false);
    final codigosExistentes = [
      ...service.produtos.map((p) => p.codigo),
      ..._itens.map((i) => i.codigo).where((c) => c.isNotEmpty),
    ];
    final novoCodigo = CodigoService.gerarProximoCodigo(codigosExistentes);
    
    setState(() {
      _itens.add(_ItemEntrada(
        codigo: novoCodigo,
        nome: '',
        quantidade: 0,
        quantidadeEmbalagens: 0,
        quantidadePorEmbalagem: 1,
        precoCusto: 0,
        unidade: 'UN',
        grupo: 'Sem Grupo',
        produtoExistente: null,
      ));
      _modo = 'manual';
      _abaAtiva = 0; // Ir para aba de itens
    });
    // Forçar atualização do TabController
    if (mounted) {
      _tabController.animateTo(0);
    }
  }

  void _removerItem(int index) {
    setState(() {
      _itens[index].dispose();
      _itens.removeAt(index);
    });
  }

  Future<void> _salvarComoRascunho() async {
    if (_itens.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Adicione pelo menos um item para salvar'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    print('>>> Salvando rascunho com ${_itens.length} itens');
    print('>>> Aba atual: $_abaAtiva');
    print('>>> Nota rascunho ID: $_notaRascunhoId');

    final service = Provider.of<DataService>(context, listen: false);
    final notaId = _notaRascunhoId ?? DateTime.now().millisecondsSinceEpoch.toString();
    
    // Converter itens para ItemNotaEntrada (sem valores anteriores ainda, serão salvos no processamento)
    final itensNota = _itens.map((item) {
      return ItemNotaEntrada(
        codigo: item.codigo,
        codigoBarras: item.codigoBarras,
        nome: item.nome,
        quantidade: item.quantidade,
        quantidadeEmbalagens: item.quantidadeEmbalagens,
        quantidadePorEmbalagem: item.quantidadePorEmbalagem,
        precoCusto: item.precoCusto,
        precoVenda: item.precoVenda,
        unidade: item.unidade,
        produtoId: item.produtoExistente?.id,
      );
    }).toList();

    final nota = NotaEntrada(
      id: notaId,
      dataCriacao: _notaRascunhoId != null 
          ? service.notasEntrada.firstWhere((n) => n.id == notaId).dataCriacao
          : DateTime.now(),
      tipo: _modo,
      status: 'rascunho',
      itens: itensNota,
      numeroNotaReal: _numeroNotaReal,
      chaveNFe: _chaveNFe,
      fornecedorNome: _fornecedorNome,
      fornecedorCNPJ: _fornecedorCNPJ,
      dataEmissao: _dataEmissao,
      valorTotal: _valorTotal,
      serie: _serie,
      modelo: _modelo,
    );

    // Salvar a nota
    if (_notaRascunhoId != null) {
      service.updateNotaEntrada(nota);
      print('>>> Rascunho atualizado: $notaId');
    } else {
      await service.addNotaEntrada(nota);
      print('>>> Novo rascunho criado: $notaId');
    }

    // Ir para a aba de notas para ver o rascunho salvo
    setState(() {
      _notaRascunhoId = notaId; // Atualizar o ID mesmo se já existir
      _abaAtiva = 1; // Ir para a aba de notas para ver o rascunho salvo
    });

    print('>>> Após salvar - Itens na tela: ${_itens.length}');
    print('>>> Após salvar - Aba: $_abaAtiva');
    print('>>> Após salvar - Nota rascunho ID: $_notaRascunhoId');

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Nota ${nota.numeroNota} salva como rascunho! Você pode continuar editando.'),
        backgroundColor: Colors.blue,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _carregarRascunho(NotaEntrada nota) {
    final service = Provider.of<DataService>(context, listen: false);
    setState(() {
      // Limpar itens atuais
      for (var item in _itens) {
        item.dispose();
      }
      _itens.clear();

      // Carregar itens da nota
      for (var itemNota in nota.itens) {
        Produto? produto;
        if (itemNota.produtoId != null) {
          try {
            produto = service.produtos.firstWhere(
              (p) => p.id == itemNota.produtoId,
            );
          } catch (_) {
            produto = null;
          }
        }

        _itens.add(_ItemEntrada(
          codigo: itemNota.codigo,
          codigoBarras: itemNota.codigoBarras,
          nome: itemNota.nome,
          quantidade: itemNota.quantidade,
          quantidadeEmbalagens: itemNota.quantidadeEmbalagens,
          quantidadePorEmbalagem: itemNota.quantidadePorEmbalagem,
          precoCusto: itemNota.precoCusto,
          precoVenda: itemNota.precoVenda,
          unidade: itemNota.unidade,
          grupo: produto?.grupo ?? 'Sem Grupo',
          produtoExistente: produto,
        ));
      }

      _notaRascunhoId = nota.id;
      _modo = nota.tipo;
      _numeroNotaReal = nota.numeroNotaReal;
      _abaAtiva = 0; // Voltar para aba de itens
    });
  }

  Future<void> _buscarProduto(int index) async {
    final item = _itens[index];
    final produto = await showDialog<Produto>(
      context: context,
      builder: (context) => _DialogBuscarProduto(busca: _busca),
    );

    if (produto != null) {
      // Verificar se já existe outro item com o mesmo código
      final outroItemComMesmoCodigo = _itens.asMap().entries.any(
        (entry) => entry.key != index && 
                   entry.value.codigo == produto.codigo &&
                   entry.value.codigo.isNotEmpty,
      );

      if (outroItemComMesmoCodigo) {
        final confirmar = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Código Já Utilizado'),
            content: Text(
              'Já existe outro item na lista com o código "${produto.codigo}".\n\n'
              'Deseja substituir o item atual por este produto?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Substituir'),
              ),
            ],
          ),
        );

        if (confirmar != true) {
          return;
        }
      }

      // Preencher campos com o produto selecionado
      setState(() {
        item.codigo = produto.codigo ?? '';
        item.codigoBarras = produto.codigoBarras;
        item.nome = produto.nome;
        item._nomeController.text = produto.nome;
        item.unidade = produto.unidade;
        item._unidadeController.text = produto.unidade;
        item.grupo = produto.grupo;
        item._grupoController.text = produto.grupo;
        item.produtoExistente = produto;
        item.precoVenda = produto.preco;
        item.margemAtual = produto.margemLucroPercentual;
        
        // Manter o preço de custo atual se já foi preenchido, senão usar o do produto
        if (item.precoCusto == 0 && produto.precoCusto != null) {
          item.precoCusto = produto.precoCusto!;
          item._precoCustoController.text = produto.precoCusto!.toString();
        }
        
        item._codigoController.text = item.codigo;
        item._nomeController.text = item.nome;
        item._unidadeController.text = item.unidade;
        item._precoVendaController.text = item.precoVenda.toString();
      });
    }
  }

  Future<void> _processarEntrada() async {
    final service = Provider.of<DataService>(context, listen: false);
    
    if (_itens.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Adicione pelo menos um item'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Verificar se nota já foi processada (se tiver número real)
    // Nota: notas canceladas/excluídas não bloqueiam o processamento
    if (_numeroNotaReal != null && _numeroNotaReal!.isNotEmpty) {
      // Buscar todas as notas com o mesmo número (incluindo canceladas para debug)
      final notasComMesmoNumero = service.notasEntrada.where(
        (n) => n.numeroNotaReal == _numeroNotaReal,
      ).toList();
      
      print('>>> Verificando duplicatas para nota $_numeroNotaReal');
      print('>>> Encontradas ${notasComMesmoNumero.length} nota(s) com este número');
      
      // Filtrar apenas notas processadas e não canceladas
      final notasProcessadasAtivas = notasComMesmoNumero.where(
        (n) => n.isProcessada && !n.isCancelada,
      ).toList();
      
      print('>>> Notas processadas ativas: ${notasProcessadasAtivas.length}');
      
      if (notasProcessadasAtivas.isNotEmpty) {
        final nota = notasProcessadasAtivas.first;
        print('>>> Nota encontrada: ${nota.id} - Status: ${nota.status}');
        
        final confirmar = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Nota Já Processada'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'A nota fiscal $_numeroNotaReal já foi processada anteriormente!',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                if (nota.dataProcessamento != null)
                  Text('Data de processamento: ${DateFormat('dd/MM/yyyy HH:mm').format(nota.dataProcessamento!)}'),
                const SizedBox(height: 16),
                const Text(
                  'Deseja realmente processar novamente?',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Isso pode causar duplicação de estoque e produtos.',
                  style: TextStyle(fontSize: 12, color: Colors.red),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                child: const Text('Processar Mesmo Assim'),
              ),
            ],
          ),
        );

        if (confirmar != true) {
          print('>>> Processamento cancelado pelo usuário');
          return; // Cancelar processamento
        } else {
          print('>>> Usuário confirmou processamento mesmo com duplicata');
        }
      } else {
        print('>>> Nenhuma nota processada ativa encontrada - pode processar normalmente');
      }
    }

    int processados = 0;
    int atualizados = 0;
    int criados = 0;
    
    // Lista para armazenar itens com valores anteriores para salvar na nota
    final List<ItemNotaEntrada> itensComValoresAnteriores = [];
    
    // Lista para rastrear códigos gerados durante esta operação
    // Isso garante que cada novo produto receba o próximo código sequencial
    final List<String> codigosGeradosNestaOperacao = [];

    for (var item in _itens) {
      if (item.nome.isEmpty || item.quantidade <= 0) continue;

      try {
        // Buscar produto por código (interno, código de barras ou código do fornecedor)
        if (item.produtoExistente == null && item.codigo.isNotEmpty) {
          final produtoEncontrado = _buscarProdutoPorCodigo(item.codigo);
          
          if (produtoEncontrado != null) {
            // Verificar se foi encontrado por código do fornecedor
            final encontradoPorCodigoFornecedor = produtoEncontrado.temCodigoFornecedor(item.codigo) && 
                                                   produtoEncontrado.codigo != item.codigo;
            
            if (encontradoPorCodigoFornecedor) {
              // Produto encontrado por código do fornecedor - confirmar
              final confirmar = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Código do Fornecedor Reconhecido'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('O código "${item.codigo}" do fornecedor corresponde ao produto:'),
                      const SizedBox(height: 8),
                      Text(
                        '${produtoEncontrado.nome}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Código no sistema: ${produtoEncontrado.codigo ?? "N/A"}',
                        style: TextStyle(color: Colors.blue[700], fontSize: 12),
                      ),
                      const SizedBox(height: 16),
                      const Text('Deseja lançar este item no produto existente?'),
                      const SizedBox(height: 8),
                      const Text(
                        'O estoque será adicionado ao produto existente.',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Não, cancelar'),
                    ),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Sim, usar produto existente'),
                    ),
                  ],
                ),
              );

              if (confirmar == true) {
                item.produtoExistente = produtoEncontrado;
                item.nome = produtoEncontrado.nome;
                item._nomeController.text = produtoEncontrado.nome;
              } else {
                continue;
              }
            } else {
              // Produto encontrado por código interno - usar diretamente
              item.produtoExistente = produtoEncontrado;
              item.nome = produtoEncontrado.nome;
              item._nomeController.text = produtoEncontrado.nome;
            }
          } else {
            // Não encontrou por código - tentar buscar por nome
            final produtoPorNome = _buscarProdutoPorNome(item.nome);
            if (produtoPorNome != null) {
              // Produto encontrado por nome - perguntar se quer associar o código do fornecedor
              final associar = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Produto Encontrado por Nome'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Encontrei um produto com nome similar:'),
                      const SizedBox(height: 8),
                      Text(
                        '${produtoPorNome.nome}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Código no sistema: ${produtoPorNome.codigo ?? "N/A"}',
                        style: TextStyle(color: Colors.blue[700], fontSize: 12),
                      ),
                      const SizedBox(height: 16),
                      Text('O código "${item.codigo}" será associado como código do fornecedor.'),
                      const SizedBox(height: 8),
                      const Text(
                        'Deseja usar este produto?',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Não, criar novo'),
                    ),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Sim, usar e associar código'),
                    ),
                  ],
                ),
              );

              if (associar == true) {
                // Adicionar código do fornecedor ao produto
                final produtoAtualizado = produtoPorNome.adicionarCodigoFornecedor(item.codigo);
                service.updateProduto(produtoAtualizado);
                
                item.produtoExistente = produtoAtualizado;
                item.nome = produtoAtualizado.nome;
                item._nomeController.text = produtoAtualizado.nome;
              }
              // Se não associar, continua para criar novo produto
            }
          }
        }

        if (item.produtoExistente != null) {
          // Produto existe - atualizar
          final produtoAtual = item.produtoExistente!;
          final custoAnterior = produtoAtual.precoCusto ?? 0;
          final custoNovo = item.precoCusto;
          
          // Calcular margens
          final margemAnterior = produtoAtual.margemLucroPercentual;
          double? margemNova;
          if (custoNovo > 0 && item.precoVenda > 0) {
            margemNova = ((item.precoVenda - custoNovo) / custoNovo) * 100;
          }
          
          // Verificar se custo mudou e se margem mudou
          bool custoMudou = custoAnterior > 0 && custoNovo != custoAnterior;
          bool margemMudou = margemNova != null && 
                            margemAnterior != 0 && 
                            (margemNova - margemAnterior).abs() > 0.01;
          
          if (custoMudou || margemMudou) {
            // Perguntar sobre alteração de preço de custo e margem
            final aplicar = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Alteração de Custo e Margem'),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Produto: ${produtoAtual.nome}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 16),
                      if (custoMudou) ...[
                        const Text('Custo:', style: TextStyle(fontWeight: FontWeight.bold)),
                        Text('  Anterior: ${_formatoMoeda.format(custoAnterior)}'),
                        Text('  Novo: ${_formatoMoeda.format(custoNovo)}'),
                        if (custoNovo > custoAnterior)
                          Text(
                            '  Aumento: ${((custoNovo - custoAnterior) / custoAnterior * 100).toStringAsFixed(2)}%',
                            style: const TextStyle(color: Colors.orange),
                          )
                        else
                          Text(
                            '  Redução: ${((custoAnterior - custoNovo) / custoAnterior * 100).toStringAsFixed(2)}%',
                            style: const TextStyle(color: Colors.green),
                          ),
                        const SizedBox(height: 12),
                      ],
                      if (margemMudou && margemNova != null) ...[
                        const Text('Margem de Lucro:', style: TextStyle(fontWeight: FontWeight.bold)),
                        Text('  Anterior: ${margemAnterior.toStringAsFixed(2)}%'),
                        Text('  Nova: ${margemNova.toStringAsFixed(2)}%'),
                        Text(
                          '  Diferença: ${(margemNova - margemAnterior).toStringAsFixed(2)}%',
                          style: TextStyle(
                            color: margemNova > margemAnterior ? Colors.green : Colors.red,
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      const Text(
                        'Deseja alterar o preço de custo e manter a nova margem?',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Não'),
                  ),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Sim, alterar'),
                  ),
                ],
              ),
            );

            if (aplicar == true) {
              // Aplicar novo custo e ajustar preço para manter margem se necessário
              if (margemNova != null && margemAnterior != 0) {
                // Manter a margem anterior se possível, ou usar a nova
                final precoParaManterMargemAnterior = custoNovo * (1 + (margemAnterior / 100));
                item.precoVenda = precoParaManterMargemAnterior;
                item._precoVendaController.text = precoParaManterMargemAnterior.toStringAsFixed(2);
              }
            } else {
              // Não aplicar - manter valores atuais do produto
              item.precoCusto = custoAnterior;
              item._precoCustoController.text = custoAnterior.toString();
              item.precoVenda = produtoAtual.preco;
              item._precoVendaController.text = produtoAtual.preco.toString();
            }
          }

          // Salvar valores anteriores antes de atualizar
          final precoCustoAnterior = produtoAtual.precoCusto;
          final precoVendaAnterior = produtoAtual.preco;
          final estoqueAnterior = produtoAtual.estoque;
          
          // Atualizar produto
          var produtoAtualizado = produtoAtual.copyWith(
            precoCusto: item.precoCusto,
            preco: item.precoVenda,
            estoque: produtoAtual.estoque + item.quantidade.toInt(),
            updatedAt: DateTime.now(),
          );

          // Se o código do item não está nos códigos do fornecedor, adicionar
          if (item.codigo.isNotEmpty && !produtoAtual.temCodigoFornecedor(item.codigo) && produtoAtual.codigo != item.codigo) {
            produtoAtualizado = produtoAtualizado.adicionarCodigoFornecedor(item.codigo);
            print('>>> Código do fornecedor "${item.codigo}" associado ao produto "${produtoAtualizado.nome}" (código interno: ${produtoAtualizado.codigo})');
          }
          
          service.updateProduto(produtoAtualizado);
          print('>>> Produto atualizado: ${produtoAtualizado.nome} - Estoque: ${produtoAtualizado.estoque} - Custo: ${produtoAtualizado.precoCusto}');
          
          // Registrar entrada no histórico
          service.registrarEntradaEstoque(
            produtoId: produtoAtual.id,
            quantidade: item.quantidade.toInt(),
            observacao: 'Entrada por ${_modo == 'xml' ? 'XML' : 'Manual'}',
          );

          // Adicionar item com valores anteriores
          itensComValoresAnteriores.add(ItemNotaEntrada(
            codigo: item.codigo,
            codigoBarras: item.codigoBarras,
            nome: item.nome,
            quantidade: item.quantidade,
            quantidadeEmbalagens: item.quantidadeEmbalagens,
            quantidadePorEmbalagem: item.quantidadePorEmbalagem,
            precoCusto: item.precoCusto,
            precoVenda: item.precoVenda,
            unidade: item.unidade,
            produtoId: produtoAtual.id,
            precoCustoAnterior: precoCustoAnterior,
            precoVendaAnterior: precoVendaAnterior,
            estoqueAnterior: estoqueAnterior,
            produtoNovo: false,
          ));

          atualizados++;
        } else {
          // Produto não existe - criar novo
          // SEMPRE gerar código interno no formato do sistema (COD-X)
          // O código da nota sempre vira código do fornecedor
          // Considerar códigos existentes + códigos já gerados nesta operação
          final codigosExistentes = [
            ...service.produtos.map((p) => p.codigo).where((c) => c != null).cast<String>(),
            ...codigosGeradosNestaOperacao,
          ];
          // Usar gerarProximoUltimo para sempre ir para o próximo após o último (sem preencher furos)
          final codigoInterno = CodigoService.gerarProximoUltimo(codigosExistentes);
          
          // Adicionar o código gerado à lista para os próximos itens considerarem
          codigosGeradosNestaOperacao.add(codigoInterno);
          
          // Código da nota sempre vira código do fornecedor (se existir)
          List<String> codigosFornecedor = [];
          if (item.codigo.isNotEmpty) {
            codigosFornecedor = [item.codigo];
            print('>>> Produto criado com código interno: $codigoInterno e código do fornecedor: ${item.codigo}');
          } else {
            print('>>> Produto criado com código interno: $codigoInterno (sem código do fornecedor)');
          }
          
          // Garantir que o grupo está cadastrado
          _cadastrarGrupoSeNaoExistir(item.grupo);
          
          final novoProduto = Produto(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            codigo: codigoInterno,
            codigoBarras: item.codigoBarras,
            nome: item.nome,
            unidade: item.unidade,
            grupo: item.grupo,
            preco: item.precoVenda,
            precoCusto: item.precoCusto,
            estoque: item.quantidade.toInt(),
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
            codigosFornecedor: codigosFornecedor,
          );

          service.addProduto(novoProduto);
          print('>>> Produto criado: ${novoProduto.nome} - Estoque: ${novoProduto.estoque} - Custo: ${novoProduto.precoCusto}');
          
          // Registrar entrada no histórico
          service.registrarEntradaEstoque(
            produtoId: novoProduto.id,
            quantidade: item.quantidade.toInt(),
            observacao: 'Entrada por ${_modo == 'xml' ? 'XML' : 'Manual'} - Produto novo',
          );

          // Adicionar item marcando como produto novo
          itensComValoresAnteriores.add(ItemNotaEntrada(
            codigo: item.codigo,
            codigoBarras: item.codigoBarras,
            nome: item.nome,
            quantidade: item.quantidade,
            quantidadeEmbalagens: item.quantidadeEmbalagens,
            quantidadePorEmbalagem: item.quantidadePorEmbalagem,
            precoCusto: item.precoCusto,
            precoVenda: item.precoVenda,
            unidade: item.unidade,
            produtoId: novoProduto.id,
            produtoNovo: true,
          ));

          criados++;
        }

        processados++;
      } catch (e) {
        print('Erro ao processar item: $e');
      }
    }

    // Verificar se realmente processou algo
    if (processados == 0) {
      print('>>> AVISO: Nenhum item foi processado!');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nenhum item foi processado. Verifique os itens e tente novamente.'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 3),
        ),
      );
      return; // Não continuar se não processou nada
    }

    // Armazenar nota processada para poder visualizar depois
    NotaEntrada? notaProcessada;

    // Atualizar nota se for rascunho ou criar nova como processada
    if (_notaRascunhoId != null) {
      // Atualizar nota existente como processada com itens que têm valores anteriores
      final notaExistente = service.notasEntrada.firstWhere((n) => n.id == _notaRascunhoId);
      notaProcessada = notaExistente.copyWith(
        status: 'processada',
        dataProcessamento: DateTime.now(),
        numeroNotaReal: _numeroNotaReal ?? notaExistente.numeroNotaReal,
        itens: itensComValoresAnteriores.isNotEmpty ? itensComValoresAnteriores : notaExistente.itens,
        chaveNFe: _chaveNFe ?? notaExistente.chaveNFe,
        fornecedorNome: _fornecedorNome ?? notaExistente.fornecedorNome,
        fornecedorCNPJ: _fornecedorCNPJ ?? notaExistente.fornecedorCNPJ,
        dataEmissao: _dataEmissao ?? notaExistente.dataEmissao,
        valorTotal: _valorTotal ?? notaExistente.valorTotal,
        serie: _serie ?? notaExistente.serie,
        modelo: _modelo ?? notaExistente.modelo,
      );
      service.updateNotaEntrada(notaProcessada);
      print('>>> Nota rascunho atualizada: ${notaProcessada.id}');
    } else if (itensComValoresAnteriores.isNotEmpty) {
      // Criar nova nota processada com itens que têm valores anteriores
      final notaId = DateTime.now().millisecondsSinceEpoch.toString();
      notaProcessada = NotaEntrada(
        id: notaId,
        dataCriacao: DateTime.now(),
        dataProcessamento: DateTime.now(),
        tipo: _modo,
        status: 'processada',
        itens: itensComValoresAnteriores,
        numeroNotaReal: _numeroNotaReal,
        chaveNFe: _chaveNFe,
        fornecedorNome: _fornecedorNome,
        fornecedorCNPJ: _fornecedorCNPJ,
        dataEmissao: _dataEmissao,
        valorTotal: _valorTotal,
        serie: _serie,
        modelo: _modelo,
      );
      await service.addNotaEntrada(notaProcessada);
      print('>>> Nova nota processada criada: ${notaProcessada.id}');
    } else {
      // Não há itens para salvar na nota, mas processou itens
      print('>>> AVISO: Processou $processados itens mas não há itens para salvar na nota');
    }

    // Fechar qualquer mensagem anterior
    ScaffoldMessenger.of(context).clearSnackBars();
    
    // Mostrar mensagem que desaparece automaticamente em 2 segundos
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '✓ Entrada processada!',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  Text(
                    '$processados processados | $atualizados atualizados | $criados criados',
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2), // Reduzido para 2 segundos
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(8),
        action: notaProcessada != null
            ? SnackBarAction(
                label: 'Ver',
                textColor: Colors.white,
                onPressed: () {
                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                  _mostrarDetalhesNota(notaProcessada!);
                },
              )
            : null,
      ),
    );

    setState(() {
      // Limpar todos os itens
      for (var item in _itens) {
        item.dispose();
      }
      _itens.clear();
      _notaRascunhoId = null;
      _numeroNotaReal = null;
      _chaveNFe = null;
      _fornecedorNome = null;
      _fornecedorCNPJ = null;
      _dataEmissao = null;
      _valorTotal = null;
      _serie = null;
      _modelo = null;
      _modo = 'xml'; // Resetar modo para o padrão
      _abaAtiva = 1; // Ir para a aba de notas para ver a nota processada
      _busca = ''; // Limpar busca
      _buscaController.clear(); // Limpar campo de busca
    });
  }

  @override
  Widget build(BuildContext context) {
    // Atualizar índice do TabController se necessário
    if (_tabController.index != _abaAtiva) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _tabController.index != _abaAtiva) {
          _tabController.animateTo(_abaAtiva);
        }
      });
    }
    
    return AppTheme.appBackground(
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Entrada de Mercadorias'),
          centerTitle: true,
          backgroundColor: Colors.transparent,
          elevation: 0,
          actions: [
            IconButton(
              icon: const Icon(Icons.upload_file),
              tooltip: 'Carregar XML',
              onPressed: _carregando ? null : _carregarXML,
            ),
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: 'Adicionar Manual',
              onPressed: _adicionarItemManual,
            ),
          ],
          bottom: TabBar(
            controller: _tabController,
            indicatorColor: Colors.blueAccent,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: [
              Tab(
                icon: const Icon(Icons.inventory_2, size: 20),
                text: 'Itens (${_itens.length})',
              ),
              const Tab(
                icon: Icon(Icons.receipt_long, size: 20),
                text: 'Notas',
              ),
            ],
          ),
        ),
        body: _carregando
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                controller: _tabController,
                children: [
                  _buildAbaItens(),
                  _buildAbaNotas(),
                ],
              ),
      ),
    );
  }

  Widget _buildAbaItens() {
    if (_itens.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.inventory_2_outlined,
              size: 100,
              color: Colors.white.withOpacity(0.3),
            ),
            const SizedBox(height: 24),
            Text(
              'Nenhum item adicionado',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white.withOpacity(0.7),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Carregue um XML ou adicione manualmente',
              style: TextStyle(
                fontSize: 14,
                color: Colors.white.withOpacity(0.5),
              ),
            ),
            const SizedBox(height: 32),
            // Botão destacado para ver notas
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 32),
              child: ElevatedButton.icon(
                onPressed: () {
                  setState(() {
                    _abaAtiva = 1;
                  });
                  // Forçar atualização do TabController
                  _tabController.animateTo(1);
                },
                icon: const Icon(Icons.receipt_long, size: 24),
                label: const Text(
                  'Ver Notas Registradas',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 4,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Filtro de busca
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: TextField(
            controller: _buscaController,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: 'Buscar produto',
              labelStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
              hintText: 'Digite o nome ou código...',
              hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
              prefixIcon: Icon(Icons.search, color: Colors.white.withOpacity(0.7)),
              suffixIcon: _busca.isNotEmpty
                  ? IconButton(
                      icon: Icon(Icons.clear, color: Colors.white.withOpacity(0.7)),
                      onPressed: () {
                        _buscaController.clear();
                        setState(() => _busca = '');
                      },
                    )
                  : null,
              filled: true,
              fillColor: Colors.white.withOpacity(0.1),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Colors.blueAccent, width: 2),
              ),
            ),
            onChanged: (value) => setState(() => _busca = value),
          ),
        ),
        // Lista de itens
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: _itens.length,
            itemBuilder: (context, index) {
              final item = _itens[index];
              if (_busca.isNotEmpty &&
                  !item.nome.toLowerCase().contains(_busca.toLowerCase()) &&
                  !item.codigo.toLowerCase().contains(_busca.toLowerCase())) {
                return const SizedBox.shrink();
              }
              return _ItemEntradaWidget(
                item: item,
                index: index,
                formatoMoeda: _formatoMoeda,
                formatoPercentual: _formatoPercentual,
                onBuscarProduto: () => _buscarProduto(index),
                onRemover: () => _removerItem(index),
              );
            },
          ),
        ),
                  // Botões de ação
                  if (_itens.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Theme.of(context).scaffoldBackgroundColor,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 4,
                            offset: const Offset(0, -2),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _salvarComoRascunho,
                              icon: const Icon(Icons.save),
                              label: const Text('Salvar Rascunho'),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 16),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: ElevatedButton.icon(
                              onPressed: _processarEntrada,
                              icon: const Icon(Icons.check),
                              label: Text('Processar (${_itens.length})'),
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              );
  }

  // Função para filtrar notas
  List<NotaEntrada> _filtrarNotas(List<NotaEntrada> notas) {
    String busca = _buscaNotasController.text.toLowerCase().trim();
    
    return notas.where((nota) {
      // Filtro por status
      if (_filtroStatus != null) {
        if (_filtroStatus == 'rascunho' && !nota.isRascunho) return false;
        if (_filtroStatus == 'processada' && !nota.isProcessada) return false;
        if (_filtroStatus == 'cancelada' && !nota.isCancelada) return false;
      }
      
      // Filtro por fornecedor
      String filtroFornecedor = _filtroFornecedorController.text.trim();
      if (filtroFornecedor.isNotEmpty) {
        if (nota.fornecedorNome == null || 
            !nota.fornecedorNome!.toLowerCase().contains(filtroFornecedor.toLowerCase())) {
          return false;
        }
      }
      
      // Filtro por data
      if (_filtroDataInicio != null) {
        final dataNota = nota.dataCriacao;
        if (dataNota.isBefore(_filtroDataInicio!)) return false;
      }
      if (_filtroDataFim != null) {
        final dataNota = nota.dataCriacao;
        final dataFimComHora = DateTime(_filtroDataFim!.year, _filtroDataFim!.month, _filtroDataFim!.day, 23, 59, 59);
        if (dataNota.isAfter(dataFimComHora)) return false;
      }
      
      // Busca geral (número, chave NFe, fornecedor)
      if (busca.isNotEmpty) {
        bool encontrou = false;
        
        // Buscar no número da nota
        if (nota.numeroNota.toLowerCase().contains(busca)) encontrou = true;
        
        // Buscar na chave NFe
        if (nota.chaveNFe != null && nota.chaveNFe!.toLowerCase().contains(busca)) encontrou = true;
        
        // Buscar no nome do fornecedor
        if (nota.fornecedorNome != null && nota.fornecedorNome!.toLowerCase().contains(busca)) encontrou = true;
        
        // Buscar no CNPJ do fornecedor
        if (nota.fornecedorCNPJ != null && nota.fornecedorCNPJ!.contains(busca)) encontrou = true;
        
        if (!encontrou) return false;
      }
      
      return true;
    }).toList();
  }

  Widget _buildAbaNotas() {
    return Consumer<DataService>(
      builder: (context, service, _) {
        final todasNotas = service.notasEntrada
          ..sort((a, b) => b.dataCriacao.compareTo(a.dataCriacao));
        
        // Aplicar filtros
        final notasFiltradas = _filtrarNotas(todasNotas);
        
        final notasRascunho = notasFiltradas.where((n) => n.isRascunho).toList();
        final notasProcessadas = notasFiltradas.where((n) => n.isProcessada).toList();

        return Column(
          children: [
            // Barra de busca e filtros
            _buildBarraBuscaFiltros(),
            
            // Mensagem se não houver notas ou se os filtros não retornarem resultados
            if (notasFiltradas.isEmpty)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        todasNotas.isEmpty ? Icons.receipt_long : Icons.search_off,
                        size: 64,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        todasNotas.isEmpty
                            ? 'Nenhuma nota registrada'
                            : 'Nenhuma nota encontrada com os filtros aplicados',
                        style: TextStyle(color: Colors.grey[600], fontSize: 16),
                      ),
                      if (todasNotas.isNotEmpty && notasFiltradas.isEmpty)
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _buscaNotasController.clear();
                              _filtroFornecedorController.clear();
                              _filtroStatus = null;
                              _filtroDataInicio = null;
                              _filtroDataFim = null;
                            });
                          },
                          child: const Text('Limpar filtros'),
                        ),
                    ],
                  ),
                ),
              )
            else ...[
            // Notas em andamento
            if (notasRascunho.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  children: [
                    Icon(Icons.edit, color: Colors.orange, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Em Andamento (${notasRascunho.length})',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                flex: notasProcessadas.isNotEmpty ? 1 : 2,
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: notasRascunho.length,
                  itemBuilder: (context, index) {
                    final nota = notasRascunho[index];
                    return _NotaCard(
                      nota: nota,
                      onCarregar: () => _carregarRascunho(nota),
                      onDeletar: () {
                        service.deleteNotaEntrada(nota.id);
                        if (_notaRascunhoId == nota.id) {
                          setState(() => _notaRascunhoId = null);
                        }
                      },
                      onVerDetalhes: () => _mostrarDetalhesNota(nota),
                    );
                  },
                ),
              ),
            ],
            // Notas processadas
            if (notasProcessadas.isNotEmpty) ...[
              if (notasRascunho.isNotEmpty)
                const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.green, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Processadas (${notasProcessadas.length})',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                flex: notasRascunho.isNotEmpty ? 1 : 2,
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: notasProcessadas.length,
                  itemBuilder: (context, index) {
                    final nota = notasProcessadas[index];
                    return _NotaCard(
                      nota: nota,
                      onCancelar: () => _mostrarDialogoCancelamento(context, service, nota),
                      onVerDetalhes: () => _mostrarDetalhesNota(nota),
                    );
                  },
                ),
              ),
            ],
            ],
          ],
        );
      },
    );
  }

  Widget _buildBarraBuscaFiltros() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        border: Border(
          bottom: BorderSide(color: Colors.white.withOpacity(0.1), width: 1),
        ),
      ),
      child: Column(
        children: [
          // Campo de busca
          TextField(
            controller: _buscaNotasController,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Buscar por número, chave NFe, fornecedor ou CNPJ...',
              hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
              prefixIcon: Icon(Icons.search, color: Colors.white.withOpacity(0.7)),
              suffixIcon: _buscaNotasController.text.isNotEmpty
                  ? IconButton(
                      icon: Icon(Icons.clear, color: Colors.white.withOpacity(0.7)),
                      onPressed: () {
                        setState(() {
                          _buscaNotasController.clear();
                        });
                      },
                    )
                  : null,
              filled: true,
              fillColor: Colors.white.withOpacity(0.1),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Colors.blueAccent, width: 2),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            onChanged: (value) => setState(() {}),
          ),
          const SizedBox(height: 12),
          
          // Filtros
          Row(
            children: [
              // Filtro de Status
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withOpacity(0.2)),
                  ),
                  child: DropdownButton<String>(
                    value: _filtroStatus,
                    hint: Text('Status', style: TextStyle(color: Colors.white.withOpacity(0.5))),
                    isExpanded: true,
                    underline: const SizedBox(),
                    icon: Icon(Icons.filter_list, color: Colors.white.withOpacity(0.7), size: 20),
                    dropdownColor: const Color(0xFF2C3E50),
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    items: [
                      DropdownMenuItem(value: null, child: Text('Todos', style: TextStyle(color: Colors.white.withOpacity(0.7)))),
                      const DropdownMenuItem(value: 'rascunho', child: Text('Rascunho')),
                      const DropdownMenuItem(value: 'processada', child: Text('Processada')),
                      const DropdownMenuItem(value: 'cancelada', child: Text('Cancelada')),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _filtroStatus = value;
                      });
                    },
                  ),
                ),
              ),
              const SizedBox(width: 8),
              
              // Filtro de Fornecedor
              Expanded(
                child: TextField(
                  controller: _filtroFornecedorController,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  onChanged: (value) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Fornecedor...',
                    hintStyle: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 12),
                    prefixIcon: Icon(Icons.business, color: Colors.white.withOpacity(0.7), size: 20),
                    suffixIcon: _filtroFornecedorController.text.isNotEmpty
                        ? IconButton(
                            icon: Icon(Icons.clear, color: Colors.white.withOpacity(0.7), size: 18),
                            onPressed: () {
                              setState(() {
                                _filtroFornecedorController.clear();
                              });
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.1),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.blueAccent, width: 2),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              
              // Botão de filtro de data
              Container(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: (_filtroDataInicio != null || _filtroDataFim != null)
                        ? Colors.blueAccent
                        : Colors.white.withOpacity(0.2),
                  ),
                ),
                child: IconButton(
                  icon: Icon(
                    _filtroDataInicio != null || _filtroDataFim != null
                        ? Icons.date_range
                        : Icons.calendar_today,
                  color: _filtroDataInicio != null || _filtroDataFim != null
                      ? Colors.blueAccent
                      : Colors.white.withOpacity(0.7),
                  ),
                  tooltip: 'Filtrar por data',
                  onPressed: () => _mostrarDialogoFiltroData(),
                ),
              ),
              
              // Botão limpar filtros
              if (_filtroStatus != null ||
                  _filtroFornecedorController.text.isNotEmpty ||
                  _filtroDataInicio != null ||
                  _filtroDataFim != null ||
                  _buscaNotasController.text.isNotEmpty)
                Container(
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.redAccent.withOpacity(0.5)),
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.clear_all, color: Colors.redAccent),
                    tooltip: 'Limpar todos os filtros',
                    onPressed: () {
                      setState(() {
                        _buscaNotasController.clear();
                        _filtroFornecedorController.clear();
                        _filtroStatus = null;
                        _filtroDataInicio = null;
                        _filtroDataFim = null;
                      });
                    },
                  ),
                ),
            ],
          ),
          
          // Chips de filtros ativos
          if (_filtroStatus != null ||
              _filtroFornecedorController.text.isNotEmpty ||
              _filtroDataInicio != null ||
              _filtroDataFim != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (_filtroStatus != null)
                    Chip(
                      label: Text(
                        _filtroStatus == 'rascunho'
                            ? 'Rascunho'
                            : _filtroStatus == 'processada'
                                ? 'Processada'
                                : 'Cancelada',
                        style: const TextStyle(fontSize: 12, color: Colors.white),
                      ),
                      deleteIcon: Icon(Icons.close, size: 16, color: Colors.white.withOpacity(0.7)),
                      onDeleted: () {
                        setState(() {
                          _filtroStatus = null;
                        });
                      },
                      backgroundColor: Colors.blueAccent.withOpacity(0.3),
                      side: BorderSide(color: Colors.blueAccent.withOpacity(0.5)),
                    ),
                  if (_filtroFornecedorController.text.isNotEmpty)
                    Chip(
                      label: Text('Fornecedor: ${_filtroFornecedorController.text}', style: const TextStyle(fontSize: 12, color: Colors.white)),
                      deleteIcon: Icon(Icons.close, size: 16, color: Colors.white.withOpacity(0.7)),
                      onDeleted: () {
                        setState(() {
                          _filtroFornecedorController.clear();
                        });
                      },
                      backgroundColor: Colors.purpleAccent.withOpacity(0.3),
                      side: BorderSide(color: Colors.purpleAccent.withOpacity(0.5)),
                    ),
                  if (_filtroDataInicio != null || _filtroDataFim != null)
                    Chip(
                      label: Text(
                        _filtroDataInicio != null && _filtroDataFim != null
                            ? '${DateFormat('dd/MM/yyyy').format(_filtroDataInicio!)} - ${DateFormat('dd/MM/yyyy').format(_filtroDataFim!)}'
                            : _filtroDataInicio != null
                                ? 'A partir de ${DateFormat('dd/MM/yyyy').format(_filtroDataInicio!)}'
                                : 'Até ${DateFormat('dd/MM/yyyy').format(_filtroDataFim!)}',
                        style: const TextStyle(fontSize: 12, color: Colors.white),
                      ),
                      deleteIcon: Icon(Icons.close, size: 16, color: Colors.white.withOpacity(0.7)),
                      onDeleted: () {
                        setState(() {
                          _filtroDataInicio = null;
                          _filtroDataFim = null;
                        });
                      },
                      backgroundColor: Colors.greenAccent.withOpacity(0.3),
                      side: BorderSide(color: Colors.greenAccent.withOpacity(0.5)),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  void _mostrarDialogoFiltroData() {
    DateTime? dataInicioTemp = _filtroDataInicio;
    DateTime? dataFimTemp = _filtroDataFim;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          backgroundColor: const Color(0xFF1E1E2E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Filtrar por Período',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 24),
                
                // Data Início
                ListTile(
                  leading: const Icon(Icons.calendar_today, color: Colors.blueAccent),
                  title: const Text('Data Início', style: TextStyle(color: Colors.white70)),
                  subtitle: Text(
                    dataInicioTemp != null
                        ? DateFormat('dd/MM/yyyy').format(dataInicioTemp!)
                        : 'Não definida',
                    style: const TextStyle(color: Colors.white),
                  ),
                  trailing: dataInicioTemp != null
                      ? IconButton(
                          icon: const Icon(Icons.clear, color: Colors.redAccent),
                          onPressed: () {
                            setDialogState(() {
                              dataInicioTemp = null;
                            });
                          },
                        )
                      : null,
                  onTap: () async {
                    final data = await showDatePicker(
                      context: context,
                      initialDate: dataInicioTemp ?? DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now(),
                      builder: (context, child) {
                        return Theme(
                          data: ThemeData.dark().copyWith(
                            colorScheme: const ColorScheme.dark(
                              primary: Colors.blueAccent,
                              onPrimary: Colors.white,
                              surface: Color(0xFF1E1E2E),
                              onSurface: Colors.white,
                            ),
                          ),
                          child: child!,
                        );
                      },
                    );
                    if (data != null) {
                      setDialogState(() {
                        dataInicioTemp = data;
                      });
                    }
                  },
                ),
                
                // Data Fim
                ListTile(
                  leading: const Icon(Icons.event, color: Colors.greenAccent),
                  title: const Text('Data Fim', style: TextStyle(color: Colors.white70)),
                  subtitle: Text(
                    dataFimTemp != null
                        ? DateFormat('dd/MM/yyyy').format(dataFimTemp!)
                        : 'Não definida',
                    style: const TextStyle(color: Colors.white),
                  ),
                  trailing: dataFimTemp != null
                      ? IconButton(
                          icon: const Icon(Icons.clear, color: Colors.redAccent),
                          onPressed: () {
                            setDialogState(() {
                              dataFimTemp = null;
                            });
                          },
                        )
                      : null,
                  onTap: () async {
                    final data = await showDatePicker(
                      context: context,
                      initialDate: dataFimTemp ?? DateTime.now(),
                      firstDate: dataInicioTemp ?? DateTime(2020),
                      lastDate: DateTime.now(),
                      builder: (context, child) {
                        return Theme(
                          data: ThemeData.dark().copyWith(
                            colorScheme: const ColorScheme.dark(
                              primary: Colors.greenAccent,
                              onPrimary: Colors.white,
                              surface: Color(0xFF1E1E2E),
                              onSurface: Colors.white,
                            ),
                          ),
                          child: child!,
                        );
                      },
                    );
                    if (data != null) {
                      setDialogState(() {
                        dataFimTemp = data;
                      });
                    }
                  },
                ),
                
                const SizedBox(height: 24),
                
                // Botões
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancelar', style: TextStyle(color: Colors.white70)),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () {
                        setState(() {
                          _filtroDataInicio = dataInicioTemp;
                          _filtroDataFim = dataFimTemp;
                        });
                        Navigator.pop(context);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueAccent,
                      ),
                      child: const Text('Aplicar'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _mostrarDetalhesNota(NotaEntrada nota) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: const Color(0xFF1E1E2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700, maxHeight: 800),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: nota.isProcessada ? Colors.green.withOpacity(0.2) : Colors.blue.withOpacity(0.2),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      nota.isProcessada ? Icons.check_circle : Icons.receipt_long,
                      color: nota.isProcessada ? Colors.greenAccent : Colors.blueAccent,
                      size: 32,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Detalhes da Nota Fiscal',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Nº ${nota.numeroNota}',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: nota.isProcessada 
                            ? Colors.greenAccent.withOpacity(0.2)
                            : nota.isRascunho
                                ? Colors.orange.withOpacity(0.2)
                                : Colors.red.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: nota.isProcessada 
                              ? Colors.greenAccent
                              : nota.isRascunho
                                  ? Colors.orange
                                  : Colors.red,
                          width: 1,
                        ),
                      ),
                      child: Text(
                        nota.isProcessada ? 'PROCESSADA' : nota.isRascunho ? 'RASCUNHO' : 'CANCELADA',
                        style: TextStyle(
                          color: nota.isProcessada 
                              ? Colors.greenAccent
                              : nota.isRascunho
                                  ? Colors.orange
                                  : Colors.red,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              
              // Content
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Informações básicas
                      _buildSectionTitle('Informações Básicas', Icons.info),
                      const SizedBox(height: 12),
                      _buildInfoCard(
                        context,
                        Icons.numbers,
                        'Número da Nota',
                        nota.numeroNota,
                      ),
                      if (nota.serie != null)
                        _buildInfoCard(
                          context,
                          Icons.confirmation_number,
                          'Série',
                          nota.serie!,
                        ),
                      if (nota.modelo != null)
                        _buildInfoCard(
                          context,
                          Icons.description,
                          'Modelo',
                          nota.modelo!,
                        ),
                      if (nota.chaveNFe != null) ...[
                        const SizedBox(height: 8),
                        _buildInfoCard(
                          context,
                          Icons.key,
                          'Chave de Acesso NFe',
                          nota.chaveNFe!,
                          isLong: true,
                        ),
                      ],
                      
                      const SizedBox(height: 24),
                      
                      // Fornecedor
                      if (nota.fornecedorNome != null || nota.fornecedorCNPJ != null) ...[
                        _buildSectionTitle('Fornecedor', Icons.business),
                        const SizedBox(height: 12),
                        if (nota.fornecedorNome != null)
                          _buildInfoCard(
                            context,
                            Icons.business,
                            'Nome',
                            nota.fornecedorNome!,
                          ),
                        if (nota.fornecedorCNPJ != null)
                          _buildInfoCard(
                            context,
                            Icons.badge,
                            'CNPJ/CPF',
                            _formatarCNPJ(nota.fornecedorCNPJ!),
                            originalValue: nota.fornecedorCNPJ!,
                          ),
                        const SizedBox(height: 24),
                      ],
                      
                      // Datas
                      _buildSectionTitle('Datas', Icons.calendar_today),
                      const SizedBox(height: 12),
                      if (nota.dataEmissao != null)
                        _buildInfoCard(
                          context,
                          Icons.calendar_today,
                          'Data de Emissão',
                          DateFormat('dd/MM/yyyy HH:mm').format(nota.dataEmissao!),
                        ),
                      _buildInfoCard(
                        context,
                        Icons.check_circle,
                        'Data de Processamento',
                        DateFormat('dd/MM/yyyy HH:mm').format(nota.dataProcessamento ?? nota.dataCriacao),
                        isHighlight: true,
                      ),
                      
                      const SizedBox(height: 24),
                      
                      // Valores
                      if (nota.valorTotal != null) ...[
                        _buildSectionTitle('Valores', Icons.attach_money),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.green.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.greenAccent.withOpacity(0.3)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.attach_money, color: Colors.greenAccent, size: 28),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Valor Total',
                                      style: TextStyle(
                                        color: Colors.white70,
                                        fontSize: 12,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    SelectableText(
                                      _formatoMoeda.format(nota.valorTotal!),
                                      style: TextStyle(
                                        color: Colors.greenAccent,
                                        fontSize: 24,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.copy, size: 20),
                                color: Colors.greenAccent,
                                tooltip: 'Copiar Valor Total',
                                onPressed: () {
                                  Clipboard.setData(ClipboardData(text: _formatoMoeda.format(nota.valorTotal!)));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Row(
                                        children: [
                                          const Icon(Icons.check_circle, color: Colors.white, size: 20),
                                          const SizedBox(width: 8),
                                          Text('Valor Total copiado: ${_formatoMoeda.format(nota.valorTotal!)}'),
                                        ],
                                      ),
                                      backgroundColor: Colors.green,
                                      duration: const Duration(seconds: 2),
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],
                      
                      // Itens da Nota
                      _buildSectionTitle('Itens da Nota (${nota.itens.length})', Icons.inventory),
                      const SizedBox(height: 12),
                      ...nota.itens.asMap().entries.map((entry) {
                        final index = entry.key;
                        final item = entry.value;
                        return _buildItemCard(item, index + 1);
                      }),
                    ],
                  ),
                ),
              ),
              
              // Footer
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.2),
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(20),
                    bottomRight: Radius.circular(20),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    ElevatedButton.icon(
                      onPressed: () {
                        // Copiar todas as informações da nota
                        final buffer = StringBuffer();
                        buffer.writeln('NOTA FISCAL DE ENTRADA');
                        buffer.writeln('='.padRight(50, '='));
                        buffer.writeln('Número: ${nota.numeroNota}');
                        if (nota.serie != null) buffer.writeln('Série: ${nota.serie}');
                        if (nota.modelo != null) buffer.writeln('Modelo: ${nota.modelo}');
                        if (nota.chaveNFe != null) buffer.writeln('Chave NFe: ${nota.chaveNFe}');
                        buffer.writeln('');
                        if (nota.fornecedorNome != null) buffer.writeln('Fornecedor: ${nota.fornecedorNome}');
                        if (nota.fornecedorCNPJ != null) buffer.writeln('CNPJ/CPF: ${_formatarCNPJ(nota.fornecedorCNPJ!)}');
                        buffer.writeln('');
                        if (nota.dataEmissao != null) buffer.writeln('Data Emissão: ${DateFormat('dd/MM/yyyy HH:mm').format(nota.dataEmissao!)}');
                        buffer.writeln('Data Processamento: ${DateFormat('dd/MM/yyyy HH:mm').format(nota.dataProcessamento ?? nota.dataCriacao)}');
                        buffer.writeln('');
                        if (nota.valorTotal != null) buffer.writeln('Valor Total: ${_formatoMoeda.format(nota.valorTotal!)}');
                        buffer.writeln('');
                        buffer.writeln('ITENS (${nota.itens.length}):');
                        buffer.writeln('-'.padRight(50, '-'));
                        for (var i = 0; i < nota.itens.length; i++) {
                          final item = nota.itens[i];
                          buffer.writeln('${i + 1}. ${item.nome}');
                          buffer.writeln('   Código: ${item.codigo}');
                          buffer.writeln('   Qtd: ${item.quantidade} ${item.unidade}');
                          buffer.writeln('   Custo: ${_formatoMoeda.format(item.precoCusto)}');
                          buffer.writeln('   Venda: ${_formatoMoeda.format(item.precoVenda)}');
                          if (i < nota.itens.length - 1) buffer.writeln('');
                        }
                        
                        Clipboard.setData(ClipboardData(text: buffer.toString()));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Row(
                              children: [
                                const Icon(Icons.check_circle, color: Colors.white, size: 20),
                                const SizedBox(width: 8),
                                const Text('Todas as informações da nota foram copiadas!'),
                              ],
                            ),
                            backgroundColor: Colors.green,
                            duration: const Duration(seconds: 2),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      },
                      icon: const Icon(Icons.copy_all),
                      label: const Text('Copiar Tudo'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueAccent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                      label: const Text('Fechar'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.grey[800],
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildSectionTitle(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: Colors.blueAccent, size: 20),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
  
  Widget _buildInfoCard(BuildContext context, IconData icon, String label, String value, {bool isLong = false, bool isHighlight = false, String? originalValue}) {
    final textToCopy = originalValue ?? value;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isHighlight ? Colors.blue.withOpacity(0.1) : Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isHighlight ? Colors.blueAccent.withOpacity(0.3) : Colors.white.withOpacity(0.1),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: isHighlight ? Colors.blueAccent : Colors.white70, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                SelectableText(
                  value,
                  style: TextStyle(
                    color: isHighlight ? Colors.blueAccent : Colors.white,
                    fontSize: isHighlight ? 16 : 14,
                    fontWeight: isHighlight ? FontWeight.bold : FontWeight.normal,
                  ),
                  maxLines: isLong ? 3 : null,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.copy, size: 18),
            color: Colors.white70,
            tooltip: 'Copiar $label',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: textToCopy));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Row(
                    children: [
                      const Icon(Icons.check_circle, color: Colors.white, size: 20),
                      const SizedBox(width: 8),
                      Text('$label copiado: $value'),
                    ],
                  ),
                  backgroundColor: Colors.green,
                  duration: const Duration(seconds: 2),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
          ),
        ],
      ),
    );
  }
  
  Widget _buildItemCard(ItemNotaEntrada item, int index) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.blueAccent.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '#$index',
                  style: const TextStyle(
                    color: Colors.blueAccent,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SelectableText(
                  item.nome,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.copy, size: 18),
                color: Colors.white70,
                tooltip: 'Copiar informações do item',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () {
                  final itemText = 'Item #$index: ${item.nome}\n'
                      'Código: ${item.codigo}\n'
                      'Quantidade: ${item.quantidade} ${item.unidade}\n'
                      'Preço Custo: ${_formatoMoeda.format(item.precoCusto)}\n'
                      'Preço Venda: ${_formatoMoeda.format(item.precoVenda)}';
                  Clipboard.setData(ClipboardData(text: itemText));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Row(
                        children: [
                          const Icon(Icons.check_circle, color: Colors.white, size: 20),
                          const SizedBox(width: 8),
                          Text('Informações do item "${item.nome}" copiadas'),
                        ],
                      ),
                      backgroundColor: Colors.green,
                      duration: const Duration(seconds: 2),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildItemInfo('Código', item.codigo, Icons.qr_code),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildItemInfo('Qtd', '${item.quantidade} ${item.unidade}', Icons.inventory),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildItemInfo('Custo', _formatoMoeda.format(item.precoCusto), Icons.shopping_cart),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildItemInfo('Venda', _formatoMoeda.format(item.precoVenda), Icons.attach_money),
              ),
            ],
          ),
          if (item.produtoNovo)
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.2),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add_circle, color: Colors.greenAccent, size: 16),
                  const SizedBox(width: 4),
                  Text(
                    'Produto Novo',
                    style: TextStyle(
                      color: Colors.greenAccent,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
  
  Widget _buildItemInfo(String label, String value, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: Colors.white54, size: 16),
        const SizedBox(width: 6),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 11,
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }


  String _formatarCNPJ(String cnpj) {
    if (cnpj.length == 11) {
      // CPF: 000.000.000-00
      return '${cnpj.substring(0, 3)}.${cnpj.substring(3, 6)}.${cnpj.substring(6, 9)}-${cnpj.substring(9)}';
    } else if (cnpj.length == 14) {
      // CNPJ: 00.000.000/0000-00
      return '${cnpj.substring(0, 2)}.${cnpj.substring(2, 5)}.${cnpj.substring(5, 8)}/${cnpj.substring(8, 12)}-${cnpj.substring(12)}';
    }
    return cnpj;
  }

  Future<void> _mostrarDialogoCancelamento(
    BuildContext context,
    DataService service,
    NotaEntrada nota,
  ) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir e Reverter Nota'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Deseja realmente excluir a nota ${nota.numeroNota} e desfazer todas as alterações?',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            const Text(
              'Esta ação irá:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text('• Reverter todas as alterações nos produtos'),
            const Text('• Remover produtos criados nesta nota'),
            const Text('• Restaurar valores anteriores (preço, estoque)'),
            const Text('• Diminuir estoque adicionado pela nota'),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.warning, color: Colors.orange),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Esta ação não pode ser desfeita!',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.orange,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Sim, Excluir e Reverter'),
          ),
        ],
      ),
    );

    if (confirmar == true) {
      try {
        await service.cancelarNotaEntrada(nota.id);
        
        // LIMPAR COMPLETAMENTE O ESTADO após excluir a nota
        if (mounted) {
          setState(() {
            // Limpar todos os itens
            for (var item in _itens) {
              item.dispose();
            }
            _itens.clear();
            
            // Limpar todos os campos relacionados à nota
            _notaRascunhoId = null;
            _numeroNotaReal = null;
            _chaveNFe = null;
            _fornecedorNome = null;
            _fornecedorCNPJ = null;
            _dataEmissao = null;
            _valorTotal = null;
            _serie = null;
            _modelo = null;
            _modo = 'xml'; // Resetar para modo padrão
            
            // Limpar busca
            _busca = '';
            _buscaController.clear();
            
            // Voltar para aba de itens
            _abaAtiva = 0;
          });
        }
        
        // Aguardar um pouco para garantir que o estado foi atualizado
        await Future.delayed(const Duration(milliseconds: 200));
        
        // Forçar atualização do serviço
        service.forceUpdate();
        
        if (context.mounted) {
          ScaffoldMessenger.of(context).clearSnackBars();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Nota ${nota.numeroNota} excluída e todas as alterações foram revertidas! Você pode processar a nota novamente.'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Erro ao cancelar nota: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }
}


class _NotaCard extends StatelessWidget {
  final NotaEntrada nota;
  final VoidCallback? onCarregar;
  final VoidCallback? onDeletar;
  final VoidCallback? onCancelar;
  final VoidCallback? onVerDetalhes;
  final DateFormat _formatoData = DateFormat('dd/MM/yyyy HH:mm');

  _NotaCard({
    required this.nota,
    this.onCarregar,
    this.onDeletar,
    this.onCancelar,
    this.onVerDetalhes,
  });

  @override
  Widget build(BuildContext context) {
    final isRascunho = nota.isRascunho;
    final isProcessada = nota.isProcessada;
    final isCancelada = nota.isCancelada;
    
    // Cores baseadas no status
    final corStatus = isCancelada 
        ? Colors.red 
        : isProcessada 
            ? Colors.green 
            : Colors.orange;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isCancelada
              ? [Colors.red.shade900, Colors.red.shade800]
              : isRascunho
                  ? [const Color(0xFF5D4037), const Color(0xFF795548)]
                  : [const Color(0xFF2C3E50), const Color(0xFF34495E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: corStatus.withOpacity(0.5),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: InkWell(
        onTap: onVerDetalhes,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Ícone do status
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: corStatus.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  isRascunho ? Icons.edit : isProcessada ? Icons.check_circle : Icons.cancel,
                  color: corStatus,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              // Informações da nota
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nota.numeroNota,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (nota.numeroNotaReal != null && nota.numeroNotaReal!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          'Nota Fiscal: ${nota.numeroNotaReal}',
                          style: TextStyle(
                            fontWeight: FontWeight.w500,
                            color: Colors.blueAccent,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    Text(
                      '${_formatoData.format(nota.dataCriacao)} | ${nota.tipo.toUpperCase()}',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.7),
                        fontSize: 12,
                      ),
                    ),
                    if (nota.dataProcessamento != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Processada em: ${_formatoData.format(nota.dataProcessamento!)}',
                          style: TextStyle(
                            color: Colors.greenAccent.withOpacity(0.8),
                            fontSize: 11,
                          ),
                        ),
                      ),
                    if (nota.fornecedorNome != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          nota.fornecedorNome!,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.6),
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '${nota.itens.length} item(ns)',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.7),
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Botões de ação
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (onVerDetalhes != null)
                    IconButton(
                      icon: Icon(Icons.info_outline, color: Colors.white.withOpacity(0.8)),
                      tooltip: 'Ver Detalhes',
                      onPressed: onVerDetalhes,
                    ),
                  if (isRascunho) ...[
                    IconButton(
                      icon: Icon(Icons.edit, color: Colors.white.withOpacity(0.8)),
                      tooltip: 'Continuar editando',
                      onPressed: onCarregar,
                    ),
                    IconButton(
                      icon: Icon(Icons.delete, color: Colors.redAccent),
                      tooltip: 'Excluir',
                      onPressed: onDeletar,
                    ),
                  ] else if (isProcessada && onCancelar != null)
                    IconButton(
                      icon: Icon(Icons.delete_forever, color: Colors.redAccent),
                      tooltip: 'Excluir e Reverter Alterações',
                      onPressed: onCancelar,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ItemEntrada {
  String codigo;
  String? codigoBarras;
  String nome;
  double quantidade; // Quantidade total calculada
  double quantidadeEmbalagens; // Quantidade de embalagens
  double quantidadePorEmbalagem; // Quantidade dentro de cada embalagem
  double precoCusto;
  double precoVenda;
  String unidade;
  String grupo; // Grupo/Categoria do produto
  Produto? produtoExistente;
  double? margemAtual;

  final TextEditingController _nomeController = TextEditingController();
  final TextEditingController _codigoController = TextEditingController();
  final TextEditingController _quantidadeEmbalagensController = TextEditingController();
  final TextEditingController _quantidadePorEmbalagemController = TextEditingController();
  final TextEditingController _quantidadeController = TextEditingController();
  final TextEditingController _precoCustoController = TextEditingController();
  final TextEditingController _precoVendaController = TextEditingController();
  final TextEditingController _unidadeController = TextEditingController();
  final TextEditingController _grupoController = TextEditingController();

  _ItemEntrada({
    required this.codigo,
    this.codigoBarras,
    required this.nome,
    required this.quantidade,
    double? quantidadeEmbalagens,
    double? quantidadePorEmbalagem,
    required this.precoCusto,
    double? precoVenda,
    required this.unidade,
    String? grupo,
    this.produtoExistente,
    double? margemAtual,
  }) : precoVenda = precoVenda ?? 0,
       margemAtual = margemAtual,
       quantidadeEmbalagens = quantidadeEmbalagens ?? 0,
       quantidadePorEmbalagem = quantidadePorEmbalagem ?? 1,
       grupo = grupo ?? 'Sem Grupo' {
    _nomeController.text = nome;
    _codigoController.text = codigo;
    _quantidadeEmbalagensController.text = (quantidadeEmbalagens ?? 0).toString();
    _quantidadePorEmbalagemController.text = (quantidadePorEmbalagem ?? 1).toString();
    _quantidadeController.text = quantidade.toString();
    _precoCustoController.text = precoCusto.toString();
    _precoVendaController.text = precoVenda.toString();
    _unidadeController.text = unidade;
    _grupoController.text = this.grupo;
    _calcularQuantidadeTotal();
  }

  void _calcularQuantidadeTotal() {
    final embalagens = double.tryParse(_quantidadeEmbalagensController.text) ?? 0;
    final porEmbalagem = double.tryParse(_quantidadePorEmbalagemController.text) ?? 1;
    
    quantidadeEmbalagens = embalagens;
    quantidadePorEmbalagem = porEmbalagem;
    quantidade = embalagens * porEmbalagem;
    _quantidadeController.text = quantidade.toString();
  }

  void dispose() {
    _nomeController.dispose();
    _codigoController.dispose();
    _quantidadeEmbalagensController.dispose();
    _quantidadePorEmbalagemController.dispose();
    _quantidadeController.dispose();
    _precoCustoController.dispose();
    _precoVendaController.dispose();
    _unidadeController.dispose();
    _grupoController.dispose();
  }
}

class _ItemEntradaWidget extends StatefulWidget {
  final _ItemEntrada item;
  final int index;
  final NumberFormat formatoMoeda;
  final NumberFormat formatoPercentual;
  final VoidCallback onBuscarProduto;
  final VoidCallback onRemover;

  const _ItemEntradaWidget({
    required this.item,
    required this.index,
    required this.formatoMoeda,
    required this.formatoPercentual,
    required this.onBuscarProduto,
    required this.onRemover,
  });

  @override
  State<_ItemEntradaWidget> createState() => _ItemEntradaWidgetState();
}

class _ItemEntradaWidgetState extends State<_ItemEntradaWidget> {
  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final produtoExistente = item.produtoExistente;
    final custoAnterior = produtoExistente?.precoCusto ?? 0;
    final custoNovo = double.tryParse(item._precoCustoController.text) ?? 0;
    final precoVenda = double.tryParse(item._precoVendaController.text) ?? 0;
    
    // Calcular margem
    double? margem;
    if (custoNovo > 0 && precoVenda > 0) {
      margem = ((precoVenda - custoNovo) / custoNovo) * 100;
    }

    // Verificar aumento de custo
    bool custoAumentou = false;
    double? aumentoPercentual;
    if (custoAnterior > 0 && custoNovo > custoAnterior) {
      custoAumentou = true;
      aumentoPercentual = ((custoNovo - custoAnterior) / custoAnterior) * 100;
    }

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header com botões
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Item ${widget.index + 1}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      if (item.nome.isNotEmpty)
                        Text(
                          item.nome,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                if (produtoExistente != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'PRODUTO EXISTENTE',
                      style: TextStyle(
                        color: Colors.green,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  )
                else if (item.codigo.isNotEmpty || item.nome.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'CADASTRO NOVO',
                      style: TextStyle(
                        color: Colors.blue,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: widget.onRemover,
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Buscar produto
            ElevatedButton.icon(
              onPressed: widget.onBuscarProduto,
              icon: const Icon(Icons.search),
              label: const Text('Buscar Produto Cadastrado'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
            const SizedBox(height: 16),
            // Divisor
            Divider(
              thickness: 2,
              color: Colors.grey[300],
            ),
            const SizedBox(height: 16),
            // Campos - Código com botão de gerar
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: item._codigoController,
                    decoration: const InputDecoration(
                      labelText: 'Código',
                      prefixIcon: Icon(Icons.qr_code),
                      helperText: 'Deixe vazio para gerar automaticamente',
                    ),
                    onChanged: (value) {
                      item.codigo = value;
                      // Verificar se existe produto quando código mudar
                      final service = Provider.of<DataService>(context, listen: false);
                      if (value.isNotEmpty) {
                        try {
                          final produto = service.produtos.firstWhere(
                            (p) => p.codigo == value || p.codigoBarras == value,
                          );
                          if (produto.id != item.produtoExistente?.id) {
                            setState(() {
                              item.produtoExistente = produto;
                              item.nome = produto.nome;
                              item._nomeController.text = produto.nome;
                              item.unidade = produto.unidade;
                              item._unidadeController.text = produto.unidade;
                              item.grupo = produto.grupo;
                              item._grupoController.text = produto.grupo;
                              if (item.precoCusto == 0 && produto.precoCusto != null) {
                                item.precoCusto = produto.precoCusto!;
                                item._precoCustoController.text = produto.precoCusto!.toString();
                              }
                              item.precoVenda = produto.preco;
                              item._precoVendaController.text = produto.preco.toString();
                              item.margemAtual = produto.margemLucroPercentual;
                            });
                          }
                        } catch (_) {
                          // Produto não encontrado
                          if (item.produtoExistente != null) {
                            setState(() {
                              item.produtoExistente = null;
                            });
                          }
                        }
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.autorenew),
                  tooltip: 'Gerar Código Automático',
                  color: Colors.blue,
                  onPressed: () {
                    final service = Provider.of<DataService>(context, listen: false);
                    final pageState = context.findAncestorStateOfType<_EntradaMercadoriasPageState>();
                    final itensList = pageState?._itens ?? [];
                    final codigosExistentes = [
                      ...service.produtos.map((p) => p.codigo),
                      ...itensList.map((i) => i.codigo).where((c) => c.isNotEmpty && c != item.codigo),
                    ];
                    final novoCodigo = CodigoService.gerarProximoCodigo(codigosExistentes);
                    // Verificar se existe produto com este código
                    Produto? produtoEncontrado;
                    try {
                      produtoEncontrado = service.produtos.firstWhere(
                        (p) => p.codigo == novoCodigo || p.codigoBarras == novoCodigo,
                      );
                    } catch (_) {
                      produtoEncontrado = null;
                    }
                    
                    setState(() {
                      item.codigo = novoCodigo;
                      item._codigoController.text = novoCodigo;
                      item.produtoExistente = produtoEncontrado;
                      if (produtoEncontrado != null) {
                        item.nome = produtoEncontrado.nome;
                        item._nomeController.text = produtoEncontrado.nome;
                        item.unidade = produtoEncontrado.unidade;
                        item._unidadeController.text = produtoEncontrado.unidade;
                        item.grupo = produtoEncontrado.grupo;
                        item._grupoController.text = produtoEncontrado.grupo;
                        if (item.precoCusto == 0 && produtoEncontrado.precoCusto != null) {
                          item.precoCusto = produtoEncontrado.precoCusto!;
                          item._precoCustoController.text = produtoEncontrado.precoCusto!.toString();
                        }
                        item.precoVenda = produtoEncontrado.preco;
                        item._precoVendaController.text = produtoEncontrado.preco.toString();
                        item.margemAtual = produtoEncontrado.margemLucroPercentual;
                      }
                    });
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Código gerado: $novoCodigo'),
                        backgroundColor: Colors.teal,
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: item._nomeController,
              decoration: const InputDecoration(
                labelText: 'Nome do Produto',
                prefixIcon: Icon(Icons.inventory_2),
              ),
              onChanged: (value) => item.nome = value,
            ),
            const SizedBox(height: 8),
            // Seção de Quantidade Inteligente
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.05),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.withOpacity(0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.inventory, color: Colors.blue, size: 20),
                      const SizedBox(width: 8),
                      const Text(
                        'Cálculo de Quantidade',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: item._quantidadeEmbalagensController,
                          decoration: InputDecoration(
                            labelText: 'Qtd. Embalagens',
                            prefixIcon: const Icon(Icons.layers),
                            helperText: 'Ex: 10 pacotes',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          keyboardType: TextInputType.number,
                          onChanged: (value) {
                            setState(() {
                              item._calcularQuantidadeTotal();
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        '×',
                        style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: item._quantidadePorEmbalagemController,
                          decoration: InputDecoration(
                            labelText: 'Qtd. por Embalagem',
                            prefixIcon: const Icon(Icons.inventory_2),
                            helperText: 'Ex: 50 itens',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          keyboardType: TextInputType.number,
                          onChanged: (value) {
                            setState(() {
                              item._calcularQuantidadeTotal();
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.green.withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.calculate, color: Colors.green, size: 20),
                        const SizedBox(width: 8),
                        const Text(
                          'Quantidade Total: ',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        Expanded(
                          child: TextField(
                            controller: item._quantidadeController,
                            decoration: InputDecoration(
                              suffixText: item.unidade,
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.zero,
                            ),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.green,
                            ),
                            textAlign: TextAlign.end,
                            keyboardType: TextInputType.number,
                            onChanged: (value) {
                              final qtdTotal = double.tryParse(value) ?? 0;
                              if (qtdTotal > 0 && item.quantidadePorEmbalagem > 0) {
                                item.quantidadeEmbalagens = qtdTotal / item.quantidadePorEmbalagem;
                                item._quantidadeEmbalagensController.text = item.quantidadeEmbalagens.toStringAsFixed(0);
                                item.quantidade = qtdTotal;
                              }
                              setState(() {});
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            // Unidade
            TextField(
              controller: item._unidadeController,
              decoration: const InputDecoration(
                labelText: 'Unidade',
                prefixIcon: Icon(Icons.straighten),
                helperText: 'Ex: UN, CX, PC, etc.',
              ),
              onChanged: (value) => item.unidade = value,
            ),
            const SizedBox(height: 8),
            // Grupo/Categoria com autocomplete
            _CampoGrupoAutocomplete(
              controller: item._grupoController,
              onChanged: (value) {
                item.grupo = value;
                // Cadastrar grupo se não existir
                final gruposManager = GruposManager();
                if (value.isNotEmpty && value != 'Sem Grupo' && !gruposManager.existeGrupo(value)) {
                  gruposManager.adicionarGrupo(value);
                }
              },
            ),
            const SizedBox(height: 8),
            // Preço de custo
            TextField(
              controller: item._precoCustoController,
              decoration: InputDecoration(
                labelText: 'Preço de Custo',
                prefixIcon: const Icon(Icons.shopping_cart),
                suffixText: custoAumentou
                    ? '↑ ${aumentoPercentual!.toStringAsFixed(1)}%'
                    : null,
                suffixStyle: TextStyle(
                  color: custoAumentou ? Colors.orange : null,
                  fontWeight: FontWeight.bold,
                ),
              ),
              keyboardType: TextInputType.number,
              onChanged: (value) {
                item.precoCusto = double.tryParse(value) ?? 0;
                setState(() {});
              },
            ),
            if (custoAumentou && custoAnterior > 0) ...[
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning, color: Colors.orange, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Custo anterior: ${widget.formatoMoeda.format(custoAnterior)}',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 8),
            // Preço de venda
            TextField(
              controller: item._precoVendaController,
              decoration: InputDecoration(
                labelText: 'Preço de Venda',
                prefixIcon: const Icon(Icons.attach_money),
                helperText: margem != null
                    ? 'Margem: ${margem.toStringAsFixed(2)}%'
                    : null,
              ),
              keyboardType: TextInputType.number,
              onChanged: (value) {
                item.precoVenda = double.tryParse(value) ?? 0;
                setState(() {});
              },
            ),
            if (margem != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: margem > 0
                      ? Colors.green.withOpacity(0.1)
                      : Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  children: [
                    Icon(
                      margem > 0 ? Icons.trending_up : Icons.trending_down,
                      color: margem > 0 ? Colors.green : Colors.red,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Margem de lucro: ${margem.toStringAsFixed(2)}%',
                        style: TextStyle(
                          color: margem > 0 ? Colors.green : Colors.red,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DialogBuscarProduto extends StatefulWidget {
  final String busca;

  const _DialogBuscarProduto({required this.busca});

  @override
  State<_DialogBuscarProduto> createState() => _DialogBuscarProdutoState();
}

class _DialogBuscarProdutoState extends State<_DialogBuscarProduto> {
  final TextEditingController _buscaController = TextEditingController();
  List<Produto> _produtosFiltrados = [];

  @override
  void initState() {
    super.initState();
    _buscaController.text = widget.busca;
    _buscar();
  }

  @override
  void dispose() {
    _buscaController.dispose();
    super.dispose();
  }

  void _buscar() {
    final service = Provider.of<DataService>(context, listen: false);
    final busca = _buscaController.text.toLowerCase();

    if (busca.isEmpty) {
      setState(() => _produtosFiltrados = service.produtos);
    } else {
      setState(() {
        _produtosFiltrados = service.produtos.where((p) {
          return p.nome.toLowerCase().contains(busca) ||
              (p.codigo != null && p.codigo!.toLowerCase().contains(busca)) ||
              (p.codigoBarras != null &&
                  p.codigoBarras!.toLowerCase().contains(busca));
        }).toList();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: 600,
        height: 600,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _buscaController,
              decoration: InputDecoration(
                labelText: 'Buscar produto',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _buscaController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _buscaController.clear();
                          _buscar();
                        },
                      )
                    : null,
              ),
              onChanged: (_) => _buscar(),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _produtosFiltrados.isEmpty
                  ? const Center(child: Text('Nenhum produto encontrado'))
                  : ListView.builder(
                      itemCount: _produtosFiltrados.length,
                      itemBuilder: (context, index) {
                        final produto = _produtosFiltrados[index];
                        return ListTile(
                          title: Text(produto.nome),
                          subtitle: Text(
                            'Código: ${produto.codigo ?? "N/A"} | '
                            'Preço: R\$ ${produto.preco.toStringAsFixed(2)} | '
                            'Custo: ${produto.precoCusto != null ? "R\$ ${produto.precoCusto!.toStringAsFixed(2)}" : "N/A"}',
                          ),
                          onTap: () => Navigator.pop(context, produto),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Widget customizado para autocomplete de grupos com ability de criar novo
class _CampoGrupoAutocomplete extends StatefulWidget {
  final TextEditingController controller;
  final Function(String) onChanged;

  const _CampoGrupoAutocomplete({
    required this.controller,
    required this.onChanged,
  });

  @override
  State<_CampoGrupoAutocomplete> createState() =>
      _CampoGrupoAutocompleteState();
}

class _CampoGrupoAutocompleteState extends State<_CampoGrupoAutocomplete> {
  late FocusNode _focusNode;
  List<String> _sugestoes = [];
  bool _mostrarSugestoes = false;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    _atualizarSugestoes(widget.controller.text);
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _atualizarSugestoes(String query) {
    final gruposManager = GruposManager();
    setState(() {
      _sugestoes = gruposManager.obterSugestoes(query);
      _mostrarSugestoes = query.isNotEmpty && _focusNode.hasFocus;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          controller: widget.controller,
          focusNode: _focusNode,
          decoration: InputDecoration(
            labelText: 'Grupo/Categoria',
            prefixIcon: const Icon(Icons.category),
            hintText: 'Ex: Periféricos, Hardware, Serviços',
            suffixIcon: _sugestoes.isNotEmpty && _mostrarSugestoes
                ? const Icon(Icons.arrow_drop_down)
                : null,
            helperText: 'Digite para buscar ou criar novo grupo',
          ),
          onChanged: (value) {
            widget.onChanged(value);
            _atualizarSugestoes(value);
          },
          onTap: () {
            _atualizarSugestoes(widget.controller.text);
          },
          textInputAction: TextInputAction.next,
        ),
        // Lista de sugestões
        if (_mostrarSugestoes && _sugestoes.isNotEmpty)
          Container(
            constraints: const BoxConstraints(maxHeight: 200),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(8),
              ),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 4),
              ],
            ),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _sugestoes.length,
              itemBuilder: (context, index) {
                final sugestao = _sugestoes[index];
                return ListTile(
                  leading: const Icon(Icons.label),
                  title: Text(sugestao),
                  onTap: () {
                    widget.controller.text = sugestao;
                    widget.onChanged(sugestao);
                    _focusNode.unfocus();
                    setState(() => _mostrarSugestoes = false);
                  },
                );
              },
            ),
          ),
        // Botão para criar novo grupo
        if (widget.controller.text.isNotEmpty &&
            !_sugestoes.contains(widget.controller.text) &&
            _focusNode.hasFocus)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: ElevatedButton.icon(
              icon: const Icon(Icons.add),
              label: Text('➕ Criar grupo "${widget.controller.text}"'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal,
                padding: const EdgeInsets.symmetric(vertical: 8),
              ),
              onPressed: () {
                final novoGrupo = widget.controller.text.trim();
                if (novoGrupo.isNotEmpty) {
                  final gruposManager = GruposManager();
                  gruposManager.adicionarGrupo(novoGrupo);
                  _atualizarSugestoes(novoGrupo);

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('✓ Grupo "$novoGrupo" criado!'),
                      backgroundColor: Colors.green,
                      duration: const Duration(seconds: 2),
                    ),
                  );
                }
              },
            ),
          ),
      ],
    );
  }
}

