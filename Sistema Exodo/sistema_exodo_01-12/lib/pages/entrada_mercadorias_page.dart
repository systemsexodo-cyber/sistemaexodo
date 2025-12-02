import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:xml/xml.dart' as xml;
import 'dart:convert';
import '../models/produto.dart';
import '../models/nota_entrada.dart';
import '../services/data_service.dart';
import '../services/codigo_service.dart';
import '../custom_app_bar.dart';
import '../theme.dart';
import 'package:intl/intl.dart';

class EntradaMercadoriasPage extends StatefulWidget {
  const EntradaMercadoriasPage({super.key});

  @override
  State<EntradaMercadoriasPage> createState() => _EntradaMercadoriasPageState();
}

class _EntradaMercadoriasPageState extends State<EntradaMercadoriasPage> {
  final _formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  final _formatoPercentual = NumberFormat.percentPattern('pt_BR');
  
  List<_ItemEntrada> _itens = [];
  bool _carregando = false;
  String _modo = 'xml'; // 'xml' ou 'manual'
  final TextEditingController _buscaController = TextEditingController();
  String _busca = '';
  int _abaAtiva = 0; // 0 = Itens, 1 = Notas
  String? _notaRascunhoId; // ID da nota rascunho atual
  String? _numeroNotaReal; // Número real da nota fiscal (do XML)

  @override
  void dispose() {
    _buscaController.dispose();
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

        // Verificar se nota já foi processada (apenas avisar, não impedir carregamento)
        // Nota: notas canceladas/excluídas não bloqueiam o processamento
        bool notaJaProcessada = false;
        if (numeroNotaReal != null && numeroNotaReal.isNotEmpty) {
          final service = Provider.of<DataService>(context, listen: false);
          try {
            // Verificar apenas notas processadas que NÃO foram canceladas
            service.notasEntrada.firstWhere(
              (n) => n.numeroNotaReal == numeroNotaReal && n.isProcessada && !n.isCancelada,
            );
            notaJaProcessada = true;
            print('>>> Nota $numeroNotaReal já foi processada anteriormente (mas pode ser processada novamente)');
          } catch (_) {
            // Nota não encontrada ou foi cancelada/excluída - pode processar normalmente
            print('>>> Nota $numeroNotaReal não encontrada ou foi excluída - pode processar normalmente');
          }
        } else {
          print('>>> Número da nota não encontrado no XML - processando normalmente');
        }

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
                
                // Calcular preço de venda (se não houver no XML, usar margem padrão de 50% sobre o custo)
                double precoVendaCalculado = valorUnitario > 0 
                    ? valorUnitario * 1.5  // Margem de 50% sobre o custo
                    : 0.0;
                
                // Se produto existe, usar o preço atual dele
                final produtoExistente = _buscarProdutoPorCodigo(codigoFinal);
                if (produtoExistente != null) {
                  precoVendaCalculado = produtoExistente.preco;
                }
                
                print('>>> Item processado (prod direto): $nome - Qtd: $quantidade - Código: $codigoFinal - Custo: $valorUnitario - Venda: $precoVendaCalculado');
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
            
            // Calcular preço de venda (se não houver no XML, usar margem padrão de 50% sobre o custo)
            double precoVendaCalculado = valorUnitario > 0 
                ? valorUnitario * 1.5  // Margem de 50% sobre o custo
                : 0.0;
            
            // Se produto existe, usar o preço atual dele
            final produtoExistente = _buscarProdutoPorCodigo(codigoFinal);
            if (produtoExistente != null) {
              precoVendaCalculado = produtoExistente.preco;
            }

            print('>>> Item processado: $nome - Qtd: $quantidade - Código: $codigoFinal - Custo: $valorUnitario - Venda: $precoVendaCalculado');
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

  Produto? _buscarProdutoPorCodigo(String codigo) {
    final service = Provider.of<DataService>(context, listen: false);
    try {
      return service.produtos.firstWhere(
        (p) => p.codigo == codigo || p.codigoBarras == codigo,
      );
    } catch (_) {
      return null;
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
        produtoExistente: null,
      ));
      _modo = 'manual';
    });
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
    );

    // Salvar a nota
    if (_notaRascunhoId != null) {
      service.updateNotaEntrada(nota);
      print('>>> Rascunho atualizado: $notaId');
    } else {
      await service.addNotaEntrada(nota);
      print('>>> Novo rascunho criado: $notaId');
    }

    // Garantir que está na aba de itens e manter os itens na tela
    setState(() {
      _notaRascunhoId = notaId; // Atualizar o ID mesmo se já existir
      _abaAtiva = 0; // Garantir que está na aba de itens para continuar editando
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
        item.unidade = produto.unidade;
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
      NotaEntrada? notaJaProcessada;
      try {
        // Verificar apenas notas processadas que não foram canceladas
        notaJaProcessada = service.notasEntrada.firstWhere(
          (n) => n.numeroNotaReal == _numeroNotaReal && n.isProcessada && !n.isCancelada,
        );
      } catch (_) {
        // Nota não encontrada ou foi cancelada, tudo bem - pode processar
      }
      
      if (notaJaProcessada != null) {
        final nota = notaJaProcessada; // Variável local não-nullable
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
          return; // Cancelar processamento
        }
      }
    }

    int processados = 0;
    int atualizados = 0;
    int criados = 0;
    
    // Lista para armazenar itens com valores anteriores para salvar na nota
    final List<ItemNotaEntrada> itensComValoresAnteriores = [];

    for (var item in _itens) {
      if (item.nome.isEmpty || item.quantidade <= 0) continue;

      try {
        // Verificar se código já existe (para produtos novos)
        if (item.produtoExistente == null && item.codigo.isNotEmpty) {
          final produtoComMesmoCodigo = service.produtos.firstWhere(
            (p) => p.codigo == item.codigo,
            orElse: () => throw StateError('Produto não encontrado'),
          );
          
          // Se encontrou produto com mesmo código, perguntar
          final confirmar = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Código Já Cadastrado'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('O código "${item.codigo}" já está cadastrado para o produto:'),
                  const SizedBox(height: 8),
                  Text(
                    '${produtoComMesmoCodigo.nome}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  const Text('Deseja lançar este item no produto existente?'),
                  const SizedBox(height: 8),
                  const Text(
                    'Se escolher "Sim", o estoque será adicionado ao produto existente.',
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
            // Usar produto existente
            item.produtoExistente = produtoComMesmoCodigo;
            item.nome = produtoComMesmoCodigo.nome;
            item._nomeController.text = produtoComMesmoCodigo.nome;
          } else {
            // Cancelar este item
            continue;
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
          final produtoAtualizado = produtoAtual.copyWith(
            precoCusto: item.precoCusto,
            preco: item.precoVenda,
            estoque: produtoAtual.estoque + item.quantidade.toInt(),
            updatedAt: DateTime.now(),
          );

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
          final novoProduto = Produto(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            codigo: item.codigo.isNotEmpty ? item.codigo : null,
            codigoBarras: item.codigoBarras,
            nome: item.nome,
            unidade: item.unidade,
            grupo: 'Sem Grupo',
            preco: item.precoVenda,
            precoCusto: item.precoCusto,
            estoque: item.quantidade.toInt(),
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
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

    // Atualizar nota se for rascunho ou criar nova como processada
    if (_notaRascunhoId != null) {
      // Atualizar nota existente como processada com itens que têm valores anteriores
      final notaExistente = service.notasEntrada.firstWhere((n) => n.id == _notaRascunhoId);
      final notaProcessada = notaExistente.copyWith(
        status: 'processada',
        dataProcessamento: DateTime.now(),
        numeroNotaReal: _numeroNotaReal ?? notaExistente.numeroNotaReal,
        itens: itensComValoresAnteriores, // Usar itens com valores anteriores
      );
      service.updateNotaEntrada(notaProcessada);
    } else if (itensComValoresAnteriores.isNotEmpty) {
      // Criar nova nota processada com itens que têm valores anteriores
      final notaId = DateTime.now().millisecondsSinceEpoch.toString();
      final notaProcessada = NotaEntrada(
        id: notaId,
        dataCriacao: DateTime.now(),
        dataProcessamento: DateTime.now(),
        tipo: _modo,
        status: 'processada',
        itens: itensComValoresAnteriores,
        numeroNotaReal: _numeroNotaReal,
      );
      await service.addNotaEntrada(notaProcessada);
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '✓ Entrada processada com sucesso!',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 4),
            Text(
              'Produtos processados: $processados | Atualizados: $atualizados | Criados: $criados',
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 4),
            const Text(
              'Os produtos foram salvos e o estoque foi atualizado.',
              style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
            ),
          ],
        ),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 5),
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
      _modo = 'xml'; // Resetar modo para o padrão
      _abaAtiva = 1; // Ir para a aba de notas para ver a nota processada
      _busca = ''; // Limpar busca
      _buscaController.clear(); // Limpar campo de busca
    });
  }

  @override
  Widget build(BuildContext context) {
    return AppTheme.appBackground(
      child: Scaffold(
        appBar: CustomAppBar(
          title: 'Entrada de Mercadorias',
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
        ),
        body: _carregando
            ? const Center(child: CircularProgressIndicator())
            : _abaAtiva == 1
                ? _buildAbaNotas()
                : Column(
                    children: [
                      // Botão para ver notas
                      Container(
                        padding: const EdgeInsets.all(8),
                        child: Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => setState(() => _abaAtiva = 1),
                                icon: const Icon(Icons.receipt_long),
                                label: const Text('Ver Notas'),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Conteúdo de itens
                      Expanded(child: _buildAbaItens()),
                    ],
                  ),
      ),
    );
  }

  Widget _buildAbaItens() {
    return Column(
      children: [
        // Filtro de busca
        if (_itens.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: TextField(
                        controller: _buscaController,
                        decoration: InputDecoration(
                          labelText: 'Buscar produto',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: _busca.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () {
                                    _buscaController.clear();
                                    setState(() => _busca = '');
                                  },
                                )
                              : null,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onChanged: (value) => setState(() => _busca = value),
                      ),
                    ),
                  // Lista de itens
                  Expanded(
                    child: _itens.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.inventory_2_outlined,
                                  size: 80,
                                  color: Colors.grey[400],
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'Nenhum item adicionado',
                                  style: TextStyle(
                                    fontSize: 18,
                                    color: Colors.grey[600],
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Carregue um XML ou adicione manualmente',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey[500],
                                  ),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
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

  Widget _buildAbaNotas() {
    return Consumer<DataService>(
      builder: (context, service, _) {
        final notas = service.notasEntrada
          ..sort((a, b) => b.dataCriacao.compareTo(a.dataCriacao));
        
        final notasRascunho = notas.where((n) => n.isRascunho).toList();
        final notasProcessadas = notas.where((n) => n.isProcessada).toList();

        if (notas.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.receipt_long, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(
                  'Nenhuma nota registrada',
                  style: TextStyle(color: Colors.grey[600], fontSize: 16),
                ),
              ],
            ),
          );
        }

        return Column(
          children: [
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
                    );
                  },
                ),
              ),
            ],
          ],
        );
      },
    );
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
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Nota ${nota.numeroNota} excluída e todas as alterações foram revertidas!'),
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
  final DateFormat _formatoData = DateFormat('dd/MM/yyyy HH:mm');

  _NotaCard({
    required this.nota,
    this.onCarregar,
    this.onDeletar,
    this.onCancelar,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: Icon(
          nota.isRascunho ? Icons.edit : Icons.check_circle,
          color: nota.isRascunho ? Colors.orange : Colors.green,
        ),
        title: Text(
          nota.numeroNota,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (nota.numeroNotaReal != null && nota.numeroNotaReal!.isNotEmpty)
              Text(
                'Nota Fiscal: ${nota.numeroNotaReal}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.blue,
                ),
              ),
            Text('${_formatoData.format(nota.dataCriacao)} | ${nota.tipo.toUpperCase()}'),
            if (nota.dataProcessamento != null)
              Text(
                'Processada em: ${_formatoData.format(nota.dataProcessamento!)}',
                style: TextStyle(color: Colors.green[700], fontSize: 11),
              ),
            Text('${nota.itens.length} item(ns)'),
          ],
        ),
        trailing: nota.isRascunho
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit, color: Colors.blue),
                    tooltip: 'Continuar editando',
                    onPressed: onCarregar,
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    tooltip: 'Excluir',
                    onPressed: onDeletar,
                  ),
                ],
              )
            : nota.isProcessada && onCancelar != null
                ? IconButton(
                    icon: const Icon(Icons.delete_forever, color: Colors.red),
                    tooltip: 'Excluir e Reverter Alterações',
                    onPressed: onCancelar,
                  )
                : null,
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
    this.produtoExistente,
    double? margemAtual,
  }) : precoVenda = precoVenda ?? 0,
       margemAtual = margemAtual,
       quantidadeEmbalagens = quantidadeEmbalagens ?? 0,
       quantidadePorEmbalagem = quantidadePorEmbalagem ?? 1 {
    _nomeController.text = nome;
    _codigoController.text = codigo;
    _quantidadeEmbalagensController.text = (quantidadeEmbalagens ?? 0).toString();
    _quantidadePorEmbalagemController.text = (quantidadePorEmbalagem ?? 1).toString();
    _quantidadeController.text = quantidade.toString();
    _precoCustoController.text = precoCusto.toString();
    _precoVendaController.text = precoVenda.toString();
    _unidadeController.text = unidade;
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

