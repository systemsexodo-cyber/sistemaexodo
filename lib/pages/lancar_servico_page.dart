import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'dart:io';
import '../services/data_service.dart';
import '../services/codigo_service.dart';
import '../models/pedido.dart';
import '../models/cliente.dart';
import '../models/pet.dart';
import '../models/servico.dart';
import '../models/item_servico.dart';
import '../models/item_material.dart';
import '../models/produto.dart';
import '../models/agendamento_servico.dart';
import '../models/funcionario.dart';
import '../models/forma_pagamento.dart';
import '../models/taxa_entrega.dart';
import '../widgets/pagamento_widget.dart';
import '../theme.dart';
import 'pdv_page.dart';
import 'package:flutter/services.dart';

/// Página de lançamento de serviços com cadastro integrado
class LancarServicoPage extends StatefulWidget {
  final Pedido? pedidoExistente;
  final Cliente? clienteInicial;

  const LancarServicoPage({
    super.key,
    this.pedidoExistente,
    this.clienteInicial,
  });

  @override
  State<LancarServicoPage> createState() => _LancarServicoPageState();
}

class _LancarServicoPageState extends State<LancarServicoPage> {
  final _formKey = GlobalKey<FormState>();
  final _nomeServicoController = TextEditingController();
  final _descricaoController = TextEditingController();
  final _precoBaseController = TextEditingController();
  final _valorAdicionalController = TextEditingController();
  final _descricaoAdicionalController = TextEditingController();
  final _observacoesController = TextEditingController();
  
  // Agendamento
  DateTime? _dataAgendamento;
  TimeOfDay? _horaAgendamento;
  final _duracaoController = TextEditingController(text: '60');
  
  // Funcionário e Comissão
  Funcionario? _funcionarioSelecionado;
  final _valorComissaoController = TextEditingController();
  bool _comissaoEmPorcentagem = false; // false = valor fixo, true = porcentagem

  // Materiais do serviço
  List<ItemMaterial> _materiaisSelecionados = [];

  // Estado do serviço
  Cliente? _clienteSelecionado;
  Pet? _petSelecionado; // Pet selecionado para o serviço
  List<ItemServico> _servicosSelecionados = [];
  List<PagamentoPedido> _pagamentos = [];
  String _statusPedido = 'Pendente';
  String _numeroPedido = '';
  
  // Controle de entrega (Taxi Dog)
  String? _tipoEntrega; // 'Taxi Dog' ou 'Cliente busca'
  String? _bairroEntrega;
  double? _valorTaxiDog;
  final _valorTaxiDogController = TextEditingController();
  final _ruaController = TextEditingController();
  final _numeroController = TextEditingController();
  final _complementoController = TextEditingController();
  final _referenciaController = TextEditingController();
  
  // Busca de cliente
  final _buscaClienteController = TextEditingController();
  final _buscaClienteFocusNode = FocusNode();
  bool _mostrarSugestoesCliente = false;
  List<Cliente> _clientesFiltrados = [];
  
  // Proteção contra duplicação de serviços
  bool _adicionandoServico = false;
  String? _ultimoServicoAdicionadoId;
  DateTime? _ultimaAdicaoServico;
  
  // Proteção contra múltiplos salvamentos
  bool _salvandoPedido = false;

  // Lista de status disponíveis
  final List<String> _statusDisponiveis = [
    'Pendente',
    'Em Andamento',
    'Concluído',
    'Cancelado',
  ];

  @override
  void initState() {
    super.initState();
    
    if (widget.pedidoExistente != null) {
      _carregarPedidoExistente();
    } else {
      if (widget.clienteInicial != null) {
        _clienteSelecionado = widget.clienteInicial;
        _buscaClienteController.text = widget.clienteInicial!.nome;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _gerarNumeroPedido();
      });
    }
  }

  @override
  void dispose() {
    _nomeServicoController.dispose();
    _descricaoController.dispose();
    _precoBaseController.dispose();
    _valorAdicionalController.dispose();
    _descricaoAdicionalController.dispose();
    _observacoesController.dispose();
    _duracaoController.dispose();
    _valorComissaoController.dispose();
    _buscaClienteController.dispose();
    _buscaClienteFocusNode.dispose();
    _valorTaxiDogController.dispose();
    _ruaController.dispose();
    _numeroController.dispose();
    _complementoController.dispose();
    _referenciaController.dispose();
    super.dispose();
  }

  void _gerarNumeroPedido() {
    final dataService = Provider.of<DataService>(context, listen: false);
    setState(() {
      _numeroPedido = dataService.getProximoNumeroServico();
    });
  }

  void _carregarPedidoExistente() {
    final pedido = widget.pedidoExistente!;
    final dataService = Provider.of<DataService>(context, listen: false);

    _numeroPedido = pedido.numero;

    if (pedido.clienteId != null) {
      _clienteSelecionado = dataService.clientes
          .where((c) => c.id == pedido.clienteId)
          .firstOrNull;
      if (_clienteSelecionado != null) {
        _buscaClienteController.text = _clienteSelecionado!.nome;
      }
    }

    _servicosSelecionados = List.from(pedido.servicos);
    _pagamentos = List.from(pedido.pagamentos);
    _statusPedido = pedido.status;
    _observacoesController.text = pedido.observacoes ?? '';
  }

  double get _totalServicos {
    final total = _servicosSelecionados.fold(
      0.0,
      (sum, item) => sum + item.valor + item.valorAdicional,
    );
    return total;
  }

  void _adicionarServico() async {
    // Mostrar popup de seleção de cliente se não houver cliente selecionado
    if (_clienteSelecionado == null) {
      final cliente = await _mostrarPopupSelecaoCliente();
      if (cliente == null) {
        // Usuário cancelou ou não selecionou cliente
        return;
      }
      setState(() {
        _clienteSelecionado = cliente;
        _petSelecionado = null; // Limpar pet ao selecionar novo cliente
        _buscaClienteController.text = cliente.nome;
      });
    }
    
    // Proteção contra múltiplos cliques rápidos
    if (_adicionandoServico) {
      debugPrint('>>> Adição de serviço já em andamento, ignorando clique duplicado');
      return;
    }

    if (_nomeServicoController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Informe o nome do serviço'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Limpar espaços e normalizar separador decimal
    final precoBaseTexto = _precoBaseController.text.trim().replaceAll(',', '.');
    final valorAdicionalTexto = _valorAdicionalController.text.trim().replaceAll(',', '.');
    
    final precoBase = double.tryParse(precoBaseTexto) ?? 0.0;
    final valorAdicional = double.tryParse(valorAdicionalTexto) ?? 0.0;
    
    // Atualizar valor do taxi dog do campo de texto (mas NÃO somar ao valor adicional)
    if (_tipoEntrega == 'Taxi Dog' && _valorTaxiDogController.text.isNotEmpty) {
      final valorTaxiTexto = _valorTaxiDogController.text.replaceAll(',', '.').trim();
      final valorTaxi = double.tryParse(valorTaxiTexto);
      if (valorTaxi != null && valorTaxi > 0) {
        _valorTaxiDog = valorTaxi;
      }
    }
    
    // Debug para verificar valores
    debugPrint('>>> Preço Base: $precoBaseTexto -> $precoBase');
    debugPrint('>>> Valor Adicional: $valorAdicionalTexto -> $valorAdicional');
    if (_valorTaxiDog != null && _valorTaxiDog! > 0) {
      debugPrint('>>> Taxi Dog: R\$ ${_valorTaxiDog!.toStringAsFixed(2)}');
    }

    if (precoBase <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Informe um preço válido'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Combinar data e hora se ambos estiverem definidos
    DateTime? dataHoraAgendamento;
    if (_dataAgendamento != null && _horaAgendamento != null) {
      dataHoraAgendamento = DateTime(
        _dataAgendamento!.year,
        _dataAgendamento!.month,
        _dataAgendamento!.day,
        _horaAgendamento!.hour,
        _horaAgendamento!.minute,
      );
    } else if (_dataAgendamento != null) {
      // Se só tiver data, usar hora atual
      final agora = DateTime.now();
      dataHoraAgendamento = DateTime(
        _dataAgendamento!.year,
        _dataAgendamento!.month,
        _dataAgendamento!.day,
        agora.hour,
        agora.minute,
      );
    }
    
    final duracao = int.tryParse(_duracaoController.text) ?? 60;

    // Normalizar descrição para comparação (considerar variações de separadores)
    String normalizarNomeParaComparacao(String nome) {
      return nome
          .toLowerCase()
          .trim()
          .replaceAll(RegExp(r'[+\-]'), ' ') // Substituir + e - por espaço
          .replaceAll(RegExp(r'\s+'), ' ') // Normalizar espaços múltiplos
          .trim();
    }
    
    final descricaoNormalizada = _nomeServicoController.text.trim();
    final descricaoAdicionalNormalizada = _descricaoAdicionalController.text.trim();
    
    // Criar nome completo para comparação
    String nomeCompleto = descricaoNormalizada;
    if (descricaoAdicionalNormalizada.isNotEmpty) {
      nomeCompleto = '$descricaoNormalizada $descricaoAdicionalNormalizada';
    }
    final nomeCompletoNormalizado = normalizarNomeParaComparacao(nomeCompleto);
    final precoTotal = precoBase + valorAdicional;

    // Verificar se já existe um serviço idêntico na lista (comparação mais robusta)
    final servicoJaExiste = _servicosSelecionados.any((item) {
      // Criar nome completo do item existente
      String nomeCompletoItem = item.descricao;
      if (item.descricaoAdicional != null && item.descricaoAdicional!.isNotEmpty) {
        nomeCompletoItem = '${item.descricao} ${item.descricaoAdicional}';
      }
      final nomeCompletoItemNormalizado = normalizarNomeParaComparacao(nomeCompletoItem);
      final precoTotalItem = item.valor + item.valorAdicional;
      
      // Comparar nomes normalizados e preços totais
      final nomeMatch = nomeCompletoItemNormalizado == nomeCompletoNormalizado;
      final precoTotalMatch = precoTotalItem == precoTotal;
      final funcionarioMatch = item.funcionarioId == _funcionarioSelecionado?.id;
      
      // Comparar data de agendamento (considerar apenas data, não hora exata)
      bool dataMatch = true;
      if (item.dataAgendamento != null && dataHoraAgendamento != null) {
        dataMatch = item.dataAgendamento!.year == dataHoraAgendamento.year &&
                    item.dataAgendamento!.month == dataHoraAgendamento.month &&
                    item.dataAgendamento!.day == dataHoraAgendamento.day;
      } else if (item.dataAgendamento != dataHoraAgendamento) {
        dataMatch = false;
      }

      return nomeMatch && precoTotalMatch && funcionarioMatch && dataMatch;
    });

    if (servicoJaExiste) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Este serviço já foi adicionado à lista!'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    // Marcar que está adicionando
    _adicionandoServico = true;

    final novoServico = ItemServico(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      descricao: _nomeServicoController.text,
      valor: precoBase,
      valorAdicional: valorAdicional,
      descricaoAdicional: _descricaoAdicionalController.text.isEmpty
          ? null
          : _descricaoAdicionalController.text,
      dataAgendamento: dataHoraAgendamento,
      duracaoMinutos: dataHoraAgendamento != null ? duracao : null,
      funcionarioId: _funcionarioSelecionado?.id,
      valorComissao: _calcularComissao(),
      materiais: List.from(_materiaisSelecionados), // Copiar lista de materiais
      tipoEntrega: _tipoEntrega,
      valorTaxiDog: _valorTaxiDog,
      bairroEntrega: _bairroEntrega,
      endereco: _ruaController.text.trim(),
      numeroEndereco: _numeroController.text.trim(),
      complemento: _complementoController.text.trim(),
      pontoReferencia: _referenciaController.text.trim(),
    );

    setState(() {
      _servicosSelecionados.add(novoServico);
    });

    // Mostrar mensagem de confirmação com os valores
    final totalServico = precoBase + valorAdicional;
    final mensagemMateriais = _materiaisSelecionados.isNotEmpty 
        ? ' com ${_materiaisSelecionados.length} material(is)' 
        : '';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          valorAdicional > 0
              ? 'Serviço adicionado$mensagemMateriais! Base: R\$ ${precoBase.toStringAsFixed(2)} + Adicional: R\$ ${valorAdicional.toStringAsFixed(2)} = Total: R\$ ${totalServico.toStringAsFixed(2)}'
              : 'Serviço adicionado$mensagemMateriais! Valor: R\$ ${precoBase.toStringAsFixed(2)}',
        ),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );

    // Limpar campos
    _nomeServicoController.clear();
    _descricaoController.clear();
    _precoBaseController.clear();
    _valorAdicionalController.clear();
    _descricaoAdicionalController.clear();
    _dataAgendamento = null;
    _horaAgendamento = null;
    _duracaoController.text = '60';
    _funcionarioSelecionado = null;
    _valorComissaoController.clear();
    _materiaisSelecionados.clear(); // Limpar materiais também
    _tipoEntrega = null;
    _bairroEntrega = null;
    _valorTaxiDog = null;
    _ruaController.clear();
    _numeroController.clear();
    _complementoController.clear();
    _referenciaController.clear();

    // Cadastrar serviço automaticamente para poder buscar depois (não bloqueia)
    _cadastrarServicoAutomaticamente(novoServico).then((_) {
      _adicionandoServico = false;
    }).catchError((e) {
      debugPrint('>>> Erro ao cadastrar serviço automaticamente: $e');
      _adicionandoServico = false;
    });
    
    // Resetar flag imediatamente (cadastro é assíncrono e não bloqueia a adição)
    _adicionandoServico = false;
  }

  Future<void> _cadastrarServicoAutomaticamente(ItemServico itemServico) async {
    final dataService = Provider.of<DataService>(context, listen: false);
    final precoBase = itemServico.valor;
    final valorAdicional = itemServico.valorAdicional;
    
    // Nome do serviço: usar SEMPRE o nome base para o template
    // para evitar poluição com bairros/taxi dog na lista global
    String nomeServico = itemServico.descricao;
    
    // A descrição adicional continua indo para o campo 'descricao' do template
    // para facilitar a identificação, mas o NOME permanece limpo.

    // Normalizar nome para comparação (remover diferenças de separadores: -, +, etc)
    String normalizarNomeParaComparacao(String nome) {
      return nome
          .toLowerCase()
          .trim()
          .replaceAll(RegExp(r'[+\-]'), ' ') // Substituir + e - por espaço
          .replaceAll(RegExp(r'\s+'), ' ') // Normalizar espaços múltiplos
          .trim();
    }
    
    final nomeNormalizado = normalizarNomeParaComparacao(nomeServico);
    final precoTotal = precoBase + valorAdicional;

    // Verificar se já existe um serviço similar (mesmo nome normalizado e mesmo preço total)
    final servicoExistente = dataService.servicos.firstWhere(
      (s) {
        final nomeExistenteNormalizado = normalizarNomeParaComparacao(s.nome);
        final precoTotalExistente = s.precoTotal;
        
        // Comparar nomes normalizados e preços totais
        return nomeExistenteNormalizado == nomeNormalizado && 
               precoTotalExistente == precoTotal;
      },
      orElse: () => Servico(
        id: '',
        nome: '',
        preco: 0,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );

    // Se não existe, cadastrar novo serviço
    if (servicoExistente.id.isEmpty) {
      final novoServico = Servico(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        nome: nomeServico,
        descricao: itemServico.descricaoAdicional ?? 
                  (valorAdicional > 0 
                    ? 'Serviço com valor adicional de R\$ ${valorAdicional.toStringAsFixed(2)}'
                    : null),
        preco: precoBase, // Preço base do serviço
        valorAdicional: valorAdicional > 0 ? valorAdicional : 0.0, // Valor adicional separado
        descricaoAdicional: itemServico.descricaoAdicional, // Descrição do adicional
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        materiais: List.from(itemServico.materiais), // Salvar materiais do serviço
      );
      await dataService.addTipoServico(novoServico);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Serviço "${nomeServico}" cadastrado para uso futuro'),
            backgroundColor: Colors.blue,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _salvarPedido() async {
    // Mostrar popup de seleção de cliente se não houver cliente selecionado
    if (_clienteSelecionado == null) {
      final cliente = await _mostrarPopupSelecaoCliente();
      if (cliente == null) {
        // Usuário cancelou ou não selecionou cliente
        return;
      }
      setState(() {
        _clienteSelecionado = cliente;
        _petSelecionado = null; // Limpar pet ao selecionar novo cliente
        _buscaClienteController.text = cliente.nome;
      });
    }
    
    // Proteção contra múltiplos cliques
    if (_salvandoPedido) {
      debugPrint('>>> Salvamento já em andamento, ignorando chamada duplicada');
      return;
    }

    if (_servicosSelecionados.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Adicione pelo menos um serviço'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    _salvandoPedido = true;

    try {
      final dataService = Provider.of<DataService>(context, listen: false);

      // Remover serviços duplicados antes de salvar
      final servicosUnicos = <ItemServico>[];
      final servicosJaAdicionados = <String>{};
      
      for (final servico in _servicosSelecionados) {
        // Criar chave única baseada em descrição, valor, adicional, funcionário e data
        final chaveUnica = '${servico.descricao}|${servico.valor}|${servico.valorAdicional}|${servico.funcionarioId ?? 'null'}|${servico.dataAgendamento?.toString() ?? 'null'}';
        
        if (!servicosJaAdicionados.contains(chaveUnica)) {
          servicosJaAdicionados.add(chaveUnica);
          servicosUnicos.add(servico);
        } else {
          debugPrint('>>> Serviço duplicado removido: ${servico.descricao}');
        }
      }

        // Se havia duplicados, atualizar a lista e mostrar aviso
        final quantidadeDuplicados = _servicosSelecionados.length - servicosUnicos.length;
        if (quantidadeDuplicados > 0) {
          setState(() {
            _servicosSelecionados = servicosUnicos;
          });
          
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  '$quantidadeDuplicados serviço(s) duplicado(s) removido(s)',
                ),
                backgroundColor: Colors.orange,
                duration: const Duration(seconds: 2),
              ),
            );
          }
        }

      // Coletar todos os materiais consumidos para histórico
      final materiaisConsumidos = _coletarMateriaisServicos(servicosUnicos);

      final pedido = Pedido(
        id: widget.pedidoExistente?.id ??
            DateTime.now().millisecondsSinceEpoch.toString(),
        numero: _numeroPedido,
        clienteId: _clienteSelecionado?.id,
        clienteNome: _clienteSelecionado?.nome,
        dataPedido: widget.pedidoExistente?.dataPedido ?? DateTime.now(),
        status: _statusPedido,
        total: servicosUnicos.fold(0.0, (sum, item) => sum + item.valor + item.valorAdicional),
        observacoes: _observacoesController.text.isNotEmpty
            ? _observacoesController.text
            : null,
        produtos: [],
        servicos: servicosUnicos,
        pagamentos: _pagamentos,
        materiaisConsumidos: materiaisConsumidos,
        createdAt: widget.pedidoExistente?.createdAt ?? DateTime.now(),
        updatedAt: DateTime.now(),
      );

      if (widget.pedidoExistente != null) {
        dataService.updatePedido(pedido);
        // Aguardar salvamento
        await Future.delayed(const Duration(milliseconds: 500));
        
        // Dar baixa no estoque dos materiais consumidos pelos serviços
        await _darBaixaMateriaisServico(servicosUnicos, dataService);
        
        // Criar agendamentos para vacinas que precisam de próxima dose
        await _criarAgendamentosVacinas(
          servicosUnicos,
          _clienteSelecionado,
          dataService,
        );
        
        if (mounted) {
          Navigator.of(context).pop(pedido);
        }
      } else {
        await dataService.addPedido(pedido);
        
        // Aguardar salvamento antes de continuar
        await Future.delayed(const Duration(milliseconds: 500));
        
        // Dar baixa no estoque dos materiais consumidos pelos serviços
        await _darBaixaMateriaisServico(servicosUnicos, dataService);
        
        // Criar agendamentos para vacinas que precisam de próxima dose
        await _criarAgendamentosVacinas(
          servicosUnicos,
          _clienteSelecionado,
          dataService,
        );
        
        // Criar agendamentos para serviços com data/hora (usando servicos únicos)
        for (final itemServico in servicosUnicos) {
          try {
            if (itemServico.temAgendamento && itemServico.dataAgendamento != null) {
              // Buscar o serviço cadastrado correspondente com tratamento de erro
              Servico? servicoCadastrado;
              
              try {
                servicoCadastrado = dataService.servicos.firstWhere(
                  (s) => s.nome == itemServico.descricao,
                  orElse: () => dataService.servicos.firstWhere(
                    (s) => s.nome.contains(itemServico.descricao) && 
                           (s.preco == itemServico.valor || s.precoTotal == (itemServico.valor + itemServico.valorAdicional)),
                    orElse: () => Servico(
                      id: '',
                      nome: '',
                      preco: 0,
                      createdAt: DateTime.now(),
                      updatedAt: DateTime.now(),
                    ),
                  ),
                );
              } catch (e) {
                debugPrint('>>> Erro ao buscar serviço cadastrado: $e');
                servicoCadastrado = null;
              }
              
              if (servicoCadastrado != null && servicoCadastrado.id.isNotEmpty) {
                // Preparar observações: combinar descricaoAdicional do serviço com observações gerais do pedido
                String? observacoesCombinadas;
                final observacoesPedido = _observacoesController.text.trim();
                final descricaoAdicional = itemServico.descricaoAdicional?.trim();
                
                if (descricaoAdicional != null && descricaoAdicional.isNotEmpty) {
                  if (observacoesPedido.isNotEmpty) {
                    // Se tem ambos, combinar
                    observacoesCombinadas = '$descricaoAdicional\n\n$observacoesPedido';
                  } else {
                    // Só tem descricaoAdicional
                    observacoesCombinadas = descricaoAdicional;
                  }
                } else if (observacoesPedido.isNotEmpty) {
                  // Só tem observações do pedido
                  observacoesCombinadas = observacoesPedido;
                }
                
                final agendamento = AgendamentoServico(
                  id: DateTime.now().millisecondsSinceEpoch.toString() + '_${itemServico.id}',
                  numero: '', // Será gerado automaticamente no addAgendamentoServico
                  servicoId: servicoCadastrado.id,
                  clienteId: _clienteSelecionado?.id,
                  cliente: _clienteSelecionado,
                  petId: _petSelecionado?.id,
                  pet: _petSelecionado, // Incluir pet selecionado
                  dataAgendamento: itemServico.dataAgendamento!,
                  duracaoMinutos: itemServico.duracaoMinutos ?? 60,
                  status: 'Agendado',
                  observacoes: observacoesCombinadas,
                  tipoEntrega: itemServico.tipoEntrega,
                  valorTaxiDog: itemServico.valorTaxiDog,
                  bairroEntrega: itemServico.bairroEntrega,
                  pedidoId: pedido.id, // ID do pedido relacionado
                  numeroPedido: pedido.numero, // Número do pedido (SRV-0001, etc.)
                  endereco: itemServico.endereco,
                  numeroEndereco: itemServico.numeroEndereco,
                  complemento: itemServico.complemento,
                  pontoReferencia: itemServico.pontoReferencia,
                );
                
                // Validação de conflito REMOVIDA - permitir múltiplos agendamentos no mesmo horário
                // A duração do serviço é mantida apenas para informação, sem bloquear outros agendamentos
                try {
                  await dataService.addAgendamentoServico(agendamento);
                } catch (e) {
                  // Se houver erro ao criar agendamento, mostrar mensagem
                  if (mounted) {
                    final mensagemErro = e.toString().replaceAll('Exception: ', '');
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(mensagemErro),
                        backgroundColor: Colors.red,
                        duration: const Duration(seconds: 5),
                      ),
                    );
                  }
                  debugPrint('>>> Erro ao criar agendamento: $e');
                  continue; // Pular este agendamento e continuar com os próximos
                }
              }
            }
          } catch (e) {
            debugPrint('>>> Erro ao criar agendamento para ${itemServico.descricao}: $e');
            // Continuar com os próximos serviços mesmo se houver erro
          }
        }
        
        // Mostrar mensagem de sucesso
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Serviço salvo com sucesso!'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
        }
        
        // Navegar para a tela de receber (PDV) após salvar
        if (mounted) {
          Navigator.of(context).pop(); // Fechar a tela de lançamento
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => PdvPage(
                pedidoInicial: pedido,
                abaInicial: 0, // Aba de receber
              ),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('>>> Erro ao salvar pedido: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao salvar pedido: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      // Sempre resetar a flag, mesmo em caso de erro
      _salvandoPedido = false;
    }
  }

  Color _getCorStatus(String status) {
    switch (status) {
      case 'Pendente':
        return Colors.orange;
      case 'Em Andamento':
        return Colors.blue;
      case 'Concluído':
        return Colors.green;
      case 'Cancelado':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final dataService = Provider.of<DataService>(context);
    final isModuloPet = dataService.empresaAtual?.moduloPet ?? false;
    final clientes = dataService.clientes;
    final isEdicao = widget.pedidoExistente != null;

    return AppTheme.appBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Column(
            children: [
              Text(isEdicao ? 'Editar Serviço' : 'Lançar Serviço'),
              if (_numeroPedido.isNotEmpty)
                Text(
                  _numeroPedido,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withOpacity(0.7),
                    fontWeight: FontWeight.normal,
                  ),
                ),
            ],
          ),
          centerTitle: true,
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
          actions: [
            TextButton.icon(
              onPressed: _servicosSelecionados.isNotEmpty ? _salvarPedido : null,
              icon: const Icon(Icons.save, color: Colors.white),
              label: Text(
                isEdicao ? 'Atualizar' : 'Salvar',
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Seleção de Cliente
                _buildSelecaoCliente(clientes),
                const SizedBox(height: 16),

                // Status
                _buildStatus(),
                const SizedBox(height: 16),

                // Seção de Buscar Serviço Cadastrado
                _buildBuscarServicoCadastrado(),
                const SizedBox(height: 16),

                // Divisor
                const Divider(),
                const SizedBox(height: 16),

                // Formulário de Cadastro de Serviço
                _buildFormularioServico(),
                const SizedBox(height: 16),

                // Botão Adicionar Serviço
                ElevatedButton.icon(
                  onPressed: _adicionarServico,
                  icon: const Icon(Icons.add),
                  label: const Text('Adicionar Serviço'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
                const SizedBox(height: 24),

                // Lista de Serviços Adicionados
                if (_servicosSelecionados.isNotEmpty) ...[
                  _buildListaServicos(),
                  const SizedBox(height: 24),
                ],

                // Tela de Pagamento
                _buildSecaoPagamentos(),

                // Observações
                const SizedBox(height: 16),
                _buildSecaoObservacoes(),
                
                // Informações do Cliente (parte de baixo)
                if (_clienteSelecionado != null) ...[
                  const SizedBox(height: 24),
                  _buildInfoCliente(),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
  
  Widget _buildSecaoObservacoes() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.note, color: Colors.white70, size: 20),
            const SizedBox(width: 8),
            const Text(
              'Observações',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Spacer(),
            if (_clienteSelecionado != null)
              TextButton.icon(
                onPressed: _adicionarDadosExtrasCliente,
                icon: const Icon(Icons.person_add, size: 16),
                label: const Text('Adicionar dados do cliente'),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.purpleAccent,
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _observacoesController,
          maxLines: 4,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            labelText: 'Observações e informações adicionais',
            labelStyle: const TextStyle(color: Colors.white70),
            hintText: _clienteSelecionado != null
                ? 'Digite observações ou clique em "Adicionar dados do cliente" para incluir informações do cliente'
                : 'Digite observações sobre o serviço...',
            hintStyle: const TextStyle(color: Colors.white38),
            filled: true,
            fillColor: Colors.black.withOpacity(0.3),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            prefixIcon: const Icon(Icons.note_outlined, color: Colors.white70),
          ),
        ),
      ],
    );
  }
  
  void _adicionarDadosExtrasCliente() {
    if (_clienteSelecionado == null) return;
    
    final cliente = _clienteSelecionado!;
    final dadosExtras = StringBuffer();
    
    // Adicionar informações básicas
    dadosExtras.writeln('=== DADOS DO CLIENTE ===');
    dadosExtras.writeln('Nome: ${cliente.nome}');
    
    if (cliente.cpfCnpj != null && cliente.cpfCnpj!.isNotEmpty) {
      dadosExtras.writeln('CPF/CNPJ: ${cliente.cpfCnpjFormatado ?? cliente.cpfCnpj}');
    }
    
    if (cliente.telefone.isNotEmpty) {
      dadosExtras.writeln('Telefone: ${cliente.telefone}');
    }
    
    if (cliente.telefone2 != null && cliente.telefone2!.isNotEmpty) {
      dadosExtras.writeln('Telefone 2: ${cliente.telefone2}');
    }
    
    if (cliente.whatsapp != null && cliente.whatsapp!.isNotEmpty) {
      dadosExtras.writeln('WhatsApp: ${cliente.whatsapp}');
    }
    
    if (cliente.email != null && cliente.email!.isNotEmpty) {
      dadosExtras.writeln('E-mail: ${cliente.email}');
    }
    
    // Adicionar endereço
    if (cliente.enderecoCompleto != 'Endereço não informado') {
      dadosExtras.writeln('Endereço: ${cliente.enderecoCompleto}');
    }
    
    if (cliente.pontoReferencia != null && cliente.pontoReferencia!.isNotEmpty) {
      dadosExtras.writeln('Ponto de Referência: ${cliente.pontoReferencia}');
    }
    
    // Adicionar outras informações
    if (cliente.profissao != null && cliente.profissao!.isNotEmpty) {
      dadosExtras.writeln('Profissão: ${cliente.profissao}');
    }
    
    if (cliente.observacoes != null && cliente.observacoes!.isNotEmpty) {
      dadosExtras.writeln('Observações do Cliente: ${cliente.observacoes}');
    }
    
    // Adicionar dados extras personalizados
    if (cliente.dadosExtras != null && cliente.dadosExtras!.isNotEmpty) {
      dadosExtras.writeln('\n=== DADOS EXTRAS ===');
      cliente.dadosExtras!.forEach((key, value) {
        dadosExtras.writeln('$key: $value');
      });
    }
    
    // Adicionar ao campo de observações
    final textoAtual = _observacoesController.text;
    if (textoAtual.isNotEmpty) {
      _observacoesController.text = '$textoAtual\n\n${dadosExtras.toString()}';
    } else {
      _observacoesController.text = dadosExtras.toString();
    }
    
    setState(() {});
    
    // Mostrar confirmação
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Dados do cliente adicionados às observações'),
        duration: Duration(seconds: 2),
        backgroundColor: Colors.green,
      ),
    );
  }
  
  Widget _buildInfoCliente() {
    final dataService = Provider.of<DataService>(context, listen: false);
    final isModuloPet = dataService.empresaAtual?.moduloPet ?? false;
    final cliente = _clienteSelecionado!;
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.purple.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.purpleAccent.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.person, color: Colors.purpleAccent, size: 24),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Cliente: ${cliente.nome}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white70),
                onPressed: () {
                  setState(() {
                    _clienteSelecionado = null;
                    _petSelecionado = null; // Limpar pet quando remover cliente
                    _buscaClienteController.clear();
                  });
                },
                tooltip: 'Remover cliente',
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (cliente.telefone.isNotEmpty)
            _buildInfoItem(Icons.phone, 'Telefone', cliente.telefone),
          if (cliente.whatsapp != null && cliente.whatsapp!.isNotEmpty)
            _buildInfoItem(Icons.chat, 'WhatsApp', cliente.whatsapp!),
          if (cliente.email != null && cliente.email!.isNotEmpty)
            _buildInfoItem(Icons.email, 'E-mail', cliente.email!),
          if (cliente.enderecoCompleto != 'Endereço não informado')
            _buildInfoItem(Icons.location_on, 'Endereço', cliente.enderecoCompleto),
          if (cliente.cpfCnpj != null && cliente.cpfCnpj!.isNotEmpty)
            _buildInfoItem(Icons.badge, 'CPF/CNPJ', cliente.cpfCnpjFormatado ?? cliente.cpfCnpj!),
          
          // Seleção de Pet
          if (isModuloPet && cliente.pets.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Divider(color: Colors.white24),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.pets, color: Colors.purpleAccent, size: 20),
                const SizedBox(width: 8),
                const Text(
                  'Pet:',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<Pet>(
              value: _petSelecionado,
              decoration: InputDecoration(
                labelText: 'Selecionar Pet (opcional)',
                labelStyle: const TextStyle(color: Colors.white70),
                filled: true,
                fillColor: const Color(0xFF181A1B),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.purpleAccent, width: 2),
                ),
              ),
              dropdownColor: const Color(0xFF23272A),
              style: const TextStyle(color: Colors.white),
              items: [
                const DropdownMenuItem<Pet>(
                  value: null,
                  child: Text('Sem pet', style: TextStyle(color: Colors.white70)),
                ),
                ...cliente.pets.map((pet) {
                  return DropdownMenuItem<Pet>(
                    value: pet,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (pet.fotoPath != null)
                          Container(
                            width: 30,
                            height: 30,
                            margin: const EdgeInsets.only(right: 8),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: Colors.white24),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: Image.file(
                                File(pet.fotoPath!),
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) => const Icon(Icons.pets, size: 20),
                              ),
                            ),
                          )
                        else
                          const Padding(
                            padding: EdgeInsets.only(right: 8),
                            child: Icon(Icons.pets, size: 20, color: Colors.white70),
                          ),
                        Flexible(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                pet.nome,
                                style: const TextStyle(color: Colors.white),
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (pet.especie != null || pet.raca != null)
                                Text(
                                  '${pet.especie ?? ''}${pet.especie != null && pet.raca != null ? ' - ' : ''}${pet.raca ?? ''}',
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.7),
                                    fontSize: 12,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
              onChanged: (pet) {
                setState(() {
                  _petSelecionado = pet;
                });
              },
            ),
            if (_petSelecionado != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    if (_petSelecionado!.fotoPath != null)
                      Container(
                        width: 40,
                        height: 40,
                        margin: const EdgeInsets.only(right: 12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: _petSelecionado!.fotoPath!.startsWith('http://') || 
                                 _petSelecionado!.fotoPath!.startsWith('https://') ||
                                 _petSelecionado!.fotoPath!.startsWith('blob:')
                              ? Image.network(
                                  _petSelecionado!.fotoPath!,
                                  fit: BoxFit.cover,
                                  width: 40,
                                  height: 40,
                                  cacheWidth: 40,
                                  cacheHeight: 40,
                                  errorBuilder: (context, error, stackTrace) => const Icon(Icons.pets, size: 24),
                                )
                              : Image.file(
                                  File(_petSelecionado!.fotoPath!),
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) => const Icon(Icons.pets, size: 24),
                                ),
                        ),
                      )
                    else
                      const Icon(Icons.pets, size: 24, color: Colors.orange),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _petSelecionado!.nome,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (_petSelecionado!.especie != null || _petSelecionado!.raca != null)
                            Text(
                              '${_petSelecionado!.especie ?? ''}${_petSelecionado!.especie != null && _petSelecionado!.raca != null ? ' - ' : ''}${_petSelecionado!.raca ?? ''}',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.7),
                                fontSize: 12,
                              ),
                            ),
                          if (_petSelecionado!.tamanho != null || _petSelecionado!.peso != null)
                            Text(
                              [
                                if (_petSelecionado!.tamanho != null) _petSelecionado!.tamanho!,
                                if (_petSelecionado!.peso != null) '${_petSelecionado!.peso}kg',
                              ].join(' • '),
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.7),
                                fontSize: 12,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
            // Seleção de tipo de entrega
            if (isModuloPet && _petSelecionado != null) ...[
              const SizedBox(height: 16),
              const Divider(color: Colors.white24),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.local_shipping, color: Colors.green, size: 20),
                  const SizedBox(width: 8),
                  const Text(
                    'Entrega do Animal:',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('Cliente busca'),
                    selected: _tipoEntrega == 'Cliente busca',
                    onSelected: (selected) {
                      if (selected) {
                        setState(() {
                          _tipoEntrega = 'Cliente busca';
                          _bairroEntrega = null;
                          _valorTaxiDog = null;
                          _valorTaxiDogController.clear();
                        });
                      }
                    },
                    selectedColor: Colors.blue.withOpacity(0.3),
                    labelStyle: TextStyle(
                      color: _tipoEntrega == 'Cliente busca' ? Colors.white : Colors.white70,
                      fontWeight: _tipoEntrega == 'Cliente busca' ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  ChoiceChip(
                    label: const Text('Taxi Dog'),
                    selected: _tipoEntrega == 'Taxi Dog',
                    onSelected: (selected) {
                      if (selected) {
                        setState(() {
                          _tipoEntrega = 'Taxi Dog';
                          _calcularValorTaxiDog();
                        });
                      }
                    },
                    selectedColor: Colors.green.withOpacity(0.3),
                    labelStyle: TextStyle(
                      color: _tipoEntrega == 'Taxi Dog' ? Colors.white : Colors.white70,
                      fontWeight: _tipoEntrega == 'Taxi Dog' ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  ChoiceChip(
                    label: const Text('Apenas Busca'),
                    selected: _tipoEntrega == 'Apenas Busca',
                    onSelected: (selected) {
                      if (selected) {
                        setState(() {
                          _tipoEntrega = 'Apenas Busca';
                          _calcularValorTaxiDog();
                        });
                      }
                    },
                    selectedColor: Colors.orange.withOpacity(0.3),
                    labelStyle: TextStyle(
                      color: _tipoEntrega == 'Apenas Busca' ? Colors.white : Colors.white70,
                      fontWeight: _tipoEntrega == 'Apenas Busca' ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  ChoiceChip(
                    label: const Text('Apenas Entrega'),
                    selected: _tipoEntrega == 'Apenas Entrega',
                    onSelected: (selected) {
                      if (selected) {
                        setState(() {
                          _tipoEntrega = 'Apenas Entrega';
                          _calcularValorTaxiDog();
                        });
                      }
                    },
                    selectedColor: Colors.orange.withOpacity(0.3),
                    labelStyle: TextStyle(
                      color: _tipoEntrega == 'Apenas Entrega' ? Colors.white : Colors.white70,
                      fontWeight: _tipoEntrega == 'Apenas Entrega' ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ],
              ),
              if (_tipoEntrega == 'Taxi Dog' || _tipoEntrega == 'Apenas Busca' || _tipoEntrega == 'Apenas Entrega') ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green.withOpacity(0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_clienteSelecionado != null && _clienteSelecionado!.bairro != null && _clienteSelecionado!.bairro!.isNotEmpty) ...[
                        Text(
                          'Bairro: ${_clienteSelecionado!.bairro}',
                          style: const TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                        const SizedBox(height: 8),
                      ],
                      Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: TextField(
                              controller: _ruaController,
                              style: const TextStyle(color: Colors.white, fontSize: 13),
                              decoration: const InputDecoration(
                                labelText: 'Rua',
                                labelStyle: TextStyle(color: Colors.white70),
                                isDense: true,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 1,
                            child: TextField(
                              controller: _numeroController,
                              style: const TextStyle(color: Colors.white, fontSize: 13),
                              decoration: const InputDecoration(
                                labelText: 'Nº',
                                labelStyle: TextStyle(color: Colors.white70),
                                isDense: true,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _complementoController,
                              style: const TextStyle(color: Colors.white, fontSize: 13),
                              decoration: const InputDecoration(
                                labelText: 'Complemento',
                                labelStyle: TextStyle(color: Colors.white70),
                                isDense: true,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _referenciaController,
                              style: const TextStyle(color: Colors.white, fontSize: 13),
                              decoration: const InputDecoration(
                                labelText: 'Referência',
                                labelStyle: TextStyle(color: Colors.white70),
                                isDense: true,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _valorTaxiDogController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                        decoration: InputDecoration(
                          labelText: 'Taxa Taxi Dog (R\$)',
                          labelStyle: const TextStyle(color: Colors.white70),
                          hintText: 'Digite o valor da taxa',
                          hintStyle: const TextStyle(color: Colors.white38),
                          prefixText: 'R\$ ',
                          prefixStyle: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                          filled: true,
                          fillColor: Colors.black.withOpacity(0.3),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: Colors.green, width: 1.5),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: Colors.green.withOpacity(0.5), width: 1),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: Colors.green, width: 2),
                          ),
                        ),
                        onChanged: (value) {
                          final valorTexto = value.replaceAll(',', '.').trim();
                          final valor = double.tryParse(valorTexto);
                          setState(() {
                            _valorTaxiDog = valor != null && valor > 0 ? valor : null;
                          });
                        },
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'^\d+[,.]?\d{0,2}')),
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: () async {
                          if (_valorTaxiDog != null && _valorTaxiDog! > 0 && _bairroEntrega != null && _bairroEntrega!.isNotEmpty) {
                            final dataService = Provider.of<DataService>(context, listen: false);
                            // Verificar se já existe taxa para este bairro
                            try {
                              final taxaExistente = dataService.taxasEntrega.firstWhere(
                                (t) => t.bairro.toLowerCase().trim() == _bairroEntrega!.toLowerCase().trim(),
                              );
                              // Atualizar taxa existente
                              dataService.updateTaxaEntrega(taxaExistente.copyWith(
                                valor: _valorTaxiDog!,
                                ativo: true,
                                updatedAt: DateTime.now(),
                              ));
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Taxa atualizada para ${_bairroEntrega}: R\$ ${_valorTaxiDog!.toStringAsFixed(2)}'),
                                    backgroundColor: Colors.green,
                                  ),
                                );
                              }
                            } catch (e) {
                              // Não existe, criar nova taxa
                              final novaTaxa = TaxaEntrega(
                                id: DateTime.now().millisecondsSinceEpoch.toString(),
                                bairro: _bairroEntrega!,
                                valor: _valorTaxiDog!,
                                cidade: _clienteSelecionado?.cidade,
                                ativo: true,
                                createdAt: DateTime.now(),
                                updatedAt: DateTime.now(),
                              );
                              await dataService.addTaxaEntrega(novaTaxa);
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Taxa salva para ${_bairroEntrega}: R\$ ${_valorTaxiDog!.toStringAsFixed(2)}'),
                                    backgroundColor: Colors.green,
                                  ),
                                );
                              }
                            }
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Informe um valor válido e um bairro para salvar a taxa'),
                                backgroundColor: Colors.orange,
                              ),
                            );
                          }
                        },
                        icon: const Icon(Icons.save, size: 16),
                        label: const Text('Salvar taxa para uso futuro'),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.green,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ],
        ],
      ),
    );
  }
  
  void _calcularValorTaxiDog() {
    if (_clienteSelecionado == null) {
      _valorTaxiDog = null;
      _bairroEntrega = null;
      return;
    }
    
    final bairro = _clienteSelecionado!.bairro;
    if (bairro == null || bairro.isEmpty) {
      _valorTaxiDog = null;
      _bairroEntrega = null;
      return;
    }
    
    final dataService = Provider.of<DataService>(context, listen: false);
    final empresa = dataService.empresaAtual;
    
    try {
      // Buscar configurações de bairro na empresa
      final config = empresa?.configuracoes ?? {};
      final agendamentoConfig = config['agendamento'] as Map<String, dynamic>? ?? {};
      final bairrosConfig = (agendamentoConfig['bairrosTaxiDogV2'] ?? config['bairrosTaxiDogV2']) as List<dynamic>?;

      if (bairrosConfig != null) {
        final bConfig = bairrosConfig.firstWhere((e) => e['bairro'].toString().toLowerCase().trim() == bairro.toLowerCase().trim(), orElse: () => null);
        
        if (bConfig != null) {
          double valor = 0.0;
          if (_tipoEntrega == 'Taxi Dog') {
            valor = (bConfig['taxa'] as num?)?.toDouble() ?? 0.0;
          } else if (_tipoEntrega == 'Apenas Busca') {
            valor = (bConfig['taxaBusca'] as num?)?.toDouble() ?? (bConfig['taxa'] as num?)?.toDouble() ?? 0.0;
          } else if (_tipoEntrega == 'Apenas Entrega') {
            valor = (bConfig['taxaSoleva'] as num?)?.toDouble() ?? (bConfig['taxa'] as num?)?.toDouble() ?? 0.0;
          }

          setState(() {
            _valorTaxiDog = valor > 0 ? valor : null;
            _bairroEntrega = bConfig['bairro'];
            if (valor > 0) {
              _valorTaxiDogController.text = valor.toStringAsFixed(2).replaceAll('.', ',');
            } else {
              _valorTaxiDogController.clear();
            }
            // Preencher endereço do cliente
            _ruaController.text = _clienteSelecionado?.endereco ?? '';
            _numeroController.text = _clienteSelecionado?.numero ?? '';
            _complementoController.text = _clienteSelecionado?.complemento ?? '';
            _referenciaController.text = _clienteSelecionado?.pontoReferencia ?? '';
          });
          return;
        }
      }

      // Fallback para taxas de entrega legadas se não encontrar na V2
      final taxa = dataService.taxasEntrega.firstWhere(
        (t) => t.bairro.toLowerCase().trim() == bairro.toLowerCase().trim() && t.ativo,
      );
      setState(() {
        _valorTaxiDog = taxa.valor;
        _bairroEntrega = taxa.bairro;
        _valorTaxiDogController.text = taxa.valor.toStringAsFixed(2).replaceAll('.', ',');
        // Preencher endereço do cliente
        _ruaController.text = _clienteSelecionado?.endereco ?? '';
        _numeroController.text = _clienteSelecionado?.numero ?? '';
        _complementoController.text = _clienteSelecionado?.complemento ?? '';
        _referenciaController.text = _clienteSelecionado?.pontoReferencia ?? '';
      });
    } catch (e) {
      setState(() {
        _valorTaxiDog = null;
        _bairroEntrega = bairro;
        _valorTaxiDogController.clear();
        // Limpar campos de endereço ou preencher se cliente tiver
        _ruaController.text = _clienteSelecionado?.endereco ?? '';
        _numeroController.text = _clienteSelecionado?.numero ?? '';
        _complementoController.text = _clienteSelecionado?.complemento ?? '';
        _referenciaController.text = _clienteSelecionado?.pontoReferencia ?? '';
      });
    }
  }
  
  Widget _buildInfoItem(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, color: Colors.purpleAccent, size: 16),
          const SizedBox(width: 8),
          Text(
            '$label: ',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 14,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  Future<Cliente?> _mostrarPopupSelecaoCliente() async {
    final dataService = Provider.of<DataService>(context, listen: false);
    final clientes = dataService.clientes.where((c) => c.ativo).toList();
    
    final TextEditingController buscaController = TextEditingController();
    List<Cliente> clientesFiltrados = List.from(clientes);
    
    return showDialog<Cliente?>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          void filtrarClientes(String busca) {
            setDialogState(() {
              if (busca.isEmpty) {
                clientesFiltrados = List.from(clientes);
              } else {
                final buscaLower = busca.toLowerCase().trim();
                clientesFiltrados = clientes.where((cliente) {
                  final nomeMatch = cliente.nome.toLowerCase().contains(buscaLower);
                  final telefoneMatch = cliente.telefone.isNotEmpty &&
                      cliente.telefone.toLowerCase().contains(buscaLower);
                  final cpfCnpjMatch = cliente.cpfCnpj != null &&
                      cliente.cpfCnpj!.toLowerCase().contains(buscaLower);
                  return nomeMatch || telefoneMatch || cpfCnpjMatch;
                }).toList();
              }
            });
          }
          
          return Dialog(
            backgroundColor: const Color(0xFF23272A),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Container(
              width: MediaQuery.of(context).size.width * 0.9,
              height: MediaQuery.of(context).size.height * 0.7,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.person, color: Colors.purpleAccent, size: 28),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Selecionar Cliente',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white70),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: buscaController,
                    autofocus: true,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Buscar cliente',
                      labelStyle: const TextStyle(color: Colors.white70),
                      hintText: 'Digite nome, telefone ou CPF/CNPJ...',
                      hintStyle: const TextStyle(color: Colors.white38),
                      prefixIcon: const Icon(Icons.search, color: Colors.white70),
                      filled: true,
                      fillColor: const Color(0xFF181A1B),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onChanged: filtrarClientes,
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: clientesFiltrados.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.person_off, color: Colors.white38, size: 64),
                                const SizedBox(height: 16),
                                Text(
                                  buscaController.text.isEmpty
                                      ? 'Nenhum cliente cadastrado'
                                      : 'Nenhum cliente encontrado',
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            itemCount: clientesFiltrados.length + 1, // +1 para "Sem cliente"
                            itemBuilder: (context, index) {
                              if (index == 0) {
                                return ListTile(
                                  leading: const Icon(Icons.person_outline, color: Colors.white70),
                                  title: const Text(
                                    'Continuar sem cliente',
                                    style: TextStyle(color: Colors.white70),
                                  ),
                                  onTap: () => Navigator.of(context).pop<Cliente?>(null),
                                );
                              }
                              
                              final cliente = clientesFiltrados[index - 1];
                              
                              return Card(
                                margin: const EdgeInsets.only(bottom: 8),
                                color: const Color(0xFF181A1B),
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: Colors.purple.withOpacity(0.3),
                                    child: Text(
                                      cliente.nome.isNotEmpty
                                          ? cliente.nome[0].toUpperCase()
                                          : '?',
                                      style: const TextStyle(color: Colors.purpleAccent),
                                    ),
                                  ),
                                  title: Text(
                                    cliente.nome,
                                    style: const TextStyle(color: Colors.white),
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      if (cliente.telefone.isNotEmpty)
                                        Text(
                                          '📞 ${cliente.telefone}',
                                          style: const TextStyle(color: Colors.white70),
                                        ),
                                      if (cliente.cpfCnpj != null && cliente.cpfCnpj!.isNotEmpty)
                                        Text(
                                          '🆔 ${cliente.cpfCnpjFormatado ?? cliente.cpfCnpj}',
                                          style: const TextStyle(color: Colors.white70),
                                        ),
                                    ],
                                  ),
                                  trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.white54),
                                  onTap: () => Navigator.of(context).pop<Cliente?>(cliente),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSelecaoCliente(List<Cliente> clientes) {
    // Função para filtrar clientes
    void filtrarClientes(String busca) {
      if (busca.isEmpty) {
        _clientesFiltrados = clientes;
      } else {
        final buscaLower = busca.toLowerCase().trim();
        _clientesFiltrados = clientes.where((cliente) {
          final nomeMatch = cliente.nome.toLowerCase().contains(buscaLower);
          final telefoneMatch = cliente.telefone.isNotEmpty &&
              cliente.telefone.toLowerCase().contains(buscaLower);
          return nomeMatch || telefoneMatch;
        }).toList();
      }
    }
    
    // Filtrar inicialmente se necessário
    if (_clientesFiltrados.isEmpty) {
      _clientesFiltrados = clientes;
    }
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _buscaClienteController,
          focusNode: _buscaClienteFocusNode,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            labelText: 'Cliente (opcional)',
            labelStyle: const TextStyle(color: Colors.white70),
            hintText: 'Buscar por nome ou telefone...',
            hintStyle: const TextStyle(color: Colors.white54),
            prefixIcon: const Icon(Icons.person, color: Colors.white70),
            suffixIcon: _clienteSelecionado != null
                ? IconButton(
                    icon: const Icon(Icons.clear, color: Colors.white70),
                    onPressed: () {
                      _buscaClienteController.clear();
                      setState(() {
                        _clienteSelecionado = null;
                        _mostrarSugestoesCliente = false;
                        _clientesFiltrados = clientes;
                      });
                      _buscaClienteFocusNode.unfocus();
                    },
                  )
                : null,
            filled: true,
            fillColor: const Color(0xFF181A1B),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.purpleAccent, width: 2),
            ),
          ),
          onChanged: (value) {
            filtrarClientes(value);
            setState(() {
              _clienteSelecionado = null;
              _mostrarSugestoesCliente = value.isNotEmpty;
            });
          },
          onTap: () {
            if (_buscaClienteController.text.isNotEmpty) {
              setState(() {
                _mostrarSugestoesCliente = true;
              });
            }
          },
        ),
        // Lista de sugestões
        if (_mostrarSugestoesCliente && _clientesFiltrados.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            constraints: const BoxConstraints(maxHeight: 300),
            decoration: BoxDecoration(
              color: const Color(0xFF23272A),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.purple.withOpacity(0.3)),
            ),
            child: ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: _clientesFiltrados.length + 1, // +1 para "Sem cliente"
              itemBuilder: (context, index) {
                if (index == 0) {
                  return ListTile(
                    leading: const Icon(Icons.person_outline, color: Colors.white70),
                    title: const Text(
                      'Sem cliente',
                      style: TextStyle(color: Colors.white70),
                    ),
                    onTap: () {
                      _buscaClienteController.clear();
                      setState(() {
                        _clienteSelecionado = null;
                        _mostrarSugestoesCliente = false;
                        _clientesFiltrados = clientes;
                      });
                      _buscaClienteFocusNode.unfocus();
                    },
                  );
                }
                
                final cliente = _clientesFiltrados[index - 1];
                
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.purple.withOpacity(0.3),
                    child: Text(
                      cliente.nome.isNotEmpty
                          ? cliente.nome[0].toUpperCase()
                          : '?',
                      style: const TextStyle(color: Colors.purpleAccent),
                    ),
                  ),
                  title: Text(
                    cliente.nome,
                    style: const TextStyle(color: Colors.white),
                  ),
                  subtitle: cliente.telefone.isNotEmpty
                      ? Text(
                          cliente.telefone,
                          style: const TextStyle(color: Colors.white70),
                        )
                      : null,
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.white54),
                  onTap: () {
                    _buscaClienteController.text = cliente.nome;
                    setState(() {
                      _clienteSelecionado = cliente;
                      _petSelecionado = null; // Limpar pet ao selecionar novo cliente
                      _mostrarSugestoesCliente = false;
                    });
                    _buscaClienteFocusNode.unfocus();
                  },
                );
              },
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildStatus() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: _getCorStatus(_statusPedido),
        borderRadius: BorderRadius.circular(20),
      ),
      child: DropdownButton<String>(
        value: _statusPedido,
        underline: const SizedBox(),
        dropdownColor: const Color(0xFF23272A),
        isDense: true,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 14,
        ),
        icon: const Icon(Icons.arrow_drop_down, color: Colors.white, size: 20),
        items: _statusDisponiveis.map(
          (status) => DropdownMenuItem(
            value: status,
            child: Text(status, style: const TextStyle(fontSize: 14)),
          ),
        ).toList(),
        onChanged: (status) {
          if (status != null) {
            setState(() {
              _statusPedido = status;
            });
          }
        },
      ),
    );
  }

  Widget _buildBuscarServicoCadastrado() {
    final dataService = Provider.of<DataService>(context);
    final servicosCadastrados = dataService.servicos;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.green.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Buscar Serviço Cadastrado',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Autocomplete<Servico>(
            optionsBuilder: (TextEditingValue textEditingValue) {
              if (textEditingValue.text.isEmpty) {
                return servicosCadastrados;
              }
              return servicosCadastrados.where(
                (Servico s) => s.nome.toLowerCase().contains(
                      textEditingValue.text.toLowerCase(),
                    ),
              );
            },
            displayStringForOption: (Servico s) {
              if (s.temAdicional) {
                return '${s.nome} + R\$ ${s.preco.toStringAsFixed(2)} + R\$ ${s.valorAdicional.toStringAsFixed(2)} = R\$ ${s.precoTotal.toStringAsFixed(2)}';
              }
              return '${s.nome} + R\$ ${s.preco.toStringAsFixed(2)}';
            },
            fieldViewBuilder:
                (context, controller, focusNode, onFieldSubmitted) {
              return TextField(
                controller: controller,
                focusNode: focusNode,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Buscar serviço...',
                  labelStyle: const TextStyle(color: Colors.white70),
                  hintText: 'Digite o nome do serviço',
                  hintStyle: const TextStyle(color: Colors.white54),
                  prefixIcon: const Icon(Icons.search, color: Colors.white70),
                  filled: true,
                  fillColor: const Color(0xFF181A1B),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              );
            },
            onSelected: (Servico servico) async {
              // Proteção contra chamadas duplicadas
              final agora = DateTime.now();
              if (_adicionandoServico) {
                debugPrint('>>> Serviço já está sendo adicionado, ignorando chamada duplicada');
                return;
              }
              
              // Verificar se o mesmo serviço foi adicionado há menos de 2 segundos
              if (_ultimoServicoAdicionadoId == servico.id && 
                  _ultimaAdicaoServico != null &&
                  agora.difference(_ultimaAdicaoServico!).inSeconds < 2) {
                debugPrint('>>> Serviço "${servico.nome}" foi adicionado recentemente, ignorando duplicação');
                return;
              }
              
              // Usar diretamente os campos do serviço
              final valorBase = servico.preco;
              final valorAdicional = servico.valorAdicional;

              // Preencher os campos do formulário quando selecionar um serviço cadastrado
              setState(() {
                _nomeServicoController.text = servico.nome;
                _descricaoController.text = servico.descricao ?? '';
                _precoBaseController.text = valorBase.toStringAsFixed(2).replaceAll('.', ',');
                _valorAdicionalController.text = valorAdicional > 0 
                    ? valorAdicional.toStringAsFixed(2).replaceAll('.', ',')
                    : '';
                _descricaoAdicionalController.text = servico.descricaoAdicional ?? '';
                // Carregar materiais do serviço cadastrado
                _materiaisSelecionados = List.from(servico.materiais);
                
                debugPrint('>>> Serviço selecionado: ${servico.nome}');
                debugPrint('>>> Materiais carregados: ${servico.materiais.length}');
                for (var material in servico.materiais) {
                  debugPrint('>>>   - ${material.produtoNome}: ${material.quantidade} ${material.unidade ?? "UN"}');
                }
              });

              final mensagemMateriais = servico.materiais.isNotEmpty 
                  ? '\n${servico.materiais.length} material(is) cadastrado(s) carregado(s). Veja na seção "Materiais do Serviço" abaixo.' 
                  : '';
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Serviço "${servico.nome}" carregado!$mensagemMateriais\n\nRevise as informações e clique em "Adicionar Serviço"',
                  ),
                  backgroundColor: servico.materiais.isNotEmpty ? Colors.green : Colors.blue,
                  duration: Duration(seconds: servico.materiais.isNotEmpty ? 5 : 3),
                ),
              );
            },
            optionsViewBuilder: (context, onSelected, options) {
              return Align(
                alignment: Alignment.topLeft,
                child: Material(
                  color: const Color(0xFF23272A),
                  borderRadius: BorderRadius.circular(12),
                  elevation: 4,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 200),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: options.length,
                      itemBuilder: (context, index) {
                        final servico = options.elementAt(index);
                        return ListTile(
                          title: Text(
                            servico.nome,
                            style: const TextStyle(color: Colors.white),
                          ),
                          subtitle: Text(
                            'R\$ ${NumberFormat.currency(locale: 'pt_BR', symbol: '').format(servico.preco)}',
                            style: const TextStyle(color: Colors.white70),
                          ),
                          onTap: () => onSelected(servico),
                        );
                      },
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildFormularioServico() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.blue.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Cadastrar Novo Serviço',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _nomeServicoController,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: 'Nome do Serviço *',
              labelStyle: const TextStyle(color: Colors.white70),
              filled: true,
              fillColor: const Color(0xFF181A1B),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _descricaoController,
            style: const TextStyle(color: Colors.white),
            maxLines: 2,
            decoration: InputDecoration(
              labelText: 'Descrição',
              labelStyle: const TextStyle(color: Colors.white70),
              filled: true,
              fillColor: const Color(0xFF181A1B),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _precoBaseController,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Preço Base (R\$) *',
                    labelStyle: const TextStyle(color: Colors.white70),
                    filled: true,
                    fillColor: const Color(0xFF181A1B),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _valorAdicionalController,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Valor Adicional (R\$)',
                    labelStyle: const TextStyle(color: Colors.white70),
                    filled: true,
                    fillColor: const Color(0xFF181A1B),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _descricaoAdicionalController,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: 'Descrição do Valor Adicional',
              labelStyle: const TextStyle(color: Colors.white70),
              filled: true,
              fillColor: const Color(0xFF181A1B),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Divider(color: Colors.white24),
          const SizedBox(height: 16),
          // Seção de Funcionário e Comissão
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange.withOpacity(0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.person, color: Colors.orange, size: 20),
                    const SizedBox(width: 8),
                    const Text(
                      'Quem vai fazer o serviço?',
                      style: TextStyle(
                        color: Colors.orange,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: DropdownButtonFormField<Funcionario?>(
                        value: _funcionarioSelecionado,
                        decoration: InputDecoration(
                          labelText: 'Funcionário (opcional)',
                          labelStyle: const TextStyle(color: Colors.white70),
                          filled: true,
                          fillColor: const Color(0xFF181A1B),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          prefixIcon: const Icon(Icons.person, color: Colors.white70),
                        ),
                        dropdownColor: const Color(0xFF23272A),
                        style: const TextStyle(color: Colors.white),
                        items: [
                          const DropdownMenuItem<Funcionario?>(
                            value: null,
                            child: Text('Sem funcionário (opcional)', style: TextStyle(color: Colors.white70)),
                          ),
                          ...Provider.of<DataService>(context, listen: false)
                              .funcionarios
                              .where((f) => f.ativo)
                              .map((funcionario) {
                            return DropdownMenuItem(
                              value: funcionario,
                              child: Text(funcionario.nome),
                            );
                          }),
                        ],
                        onChanged: (funcionario) {
                          setState(() {
                            _funcionarioSelecionado = funcionario;
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 1,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: ChoiceChip(
                                  label: const Text('R\$', style: TextStyle(fontSize: 12)),
                                  selected: !_comissaoEmPorcentagem,
                                  onSelected: (selected) {
                                    setState(() {
                                      _comissaoEmPorcentagem = false;
                                      _valorComissaoController.clear();
                                    });
                                  },
                                  selectedColor: Colors.orange,
                                  labelStyle: TextStyle(
                                    color: _comissaoEmPorcentagem ? Colors.white70 : Colors.white,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: ChoiceChip(
                                  label: const Text('%', style: TextStyle(fontSize: 12)),
                                  selected: _comissaoEmPorcentagem,
                                  onSelected: (selected) {
                                    setState(() {
                                      _comissaoEmPorcentagem = true;
                                      _valorComissaoController.clear();
                                    });
                                  },
                                  selectedColor: Colors.orange,
                                  labelStyle: TextStyle(
                                    color: _comissaoEmPorcentagem ? Colors.white : Colors.white70,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _valorComissaoController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            style: const TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                              labelText: _comissaoEmPorcentagem ? 'Comissão (%)' : 'Comissão (R\$)',
                              hintText: _comissaoEmPorcentagem ? '0.00' : '0.00',
                              labelStyle: const TextStyle(color: Colors.white70),
                              hintStyle: const TextStyle(color: Colors.white38),
                              filled: true,
                              fillColor: const Color(0xFF181A1B),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                              prefixText: _comissaoEmPorcentagem ? '' : 'R\$ ',
                              suffixText: _comissaoEmPorcentagem ? '%' : null,
                            ),
                            onChanged: (value) {
                              setState(() {});
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                // Preview da comissão calculada
                if (_comissaoEmPorcentagem && _valorComissaoController.text.isNotEmpty && _funcionarioSelecionado != null) ...[
                  const SizedBox(height: 8),
                  Builder(
                    builder: (context) {
                      final porcentagem = double.tryParse(_valorComissaoController.text.replaceAll(',', '.')) ?? 0.0;
                      final precoBase = double.tryParse(_precoBaseController.text.replaceAll(',', '.')) ?? 0.0;
                      final valorAdicional = double.tryParse(_valorAdicionalController.text.replaceAll(',', '.')) ?? 0.0;
                      final totalServico = precoBase + valorAdicional;
                      final comissaoCalculada = (totalServico * porcentagem) / 100;
                      
                      return Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.info_outline, size: 16, color: Colors.orange),
                            const SizedBox(width: 8),
                            Text(
                              'Comissão calculada: ${NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(comissaoCalculada)} (${porcentagem.toStringAsFixed(2)}% de ${NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(totalServico)})',
                              style: const TextStyle(color: Colors.orange, fontSize: 12),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () async {
                    final resultado = await _mostrarDialogoFuncionarioComissao(context);
                    if (resultado != null && mounted) {
                      setState(() {
                        _funcionarioSelecionado = resultado['funcionario'] as Funcionario?;
                        _valorComissaoController.text = (resultado['comissao'] as double).toStringAsFixed(2);
                      });
                    }
                  },
                  icon: const Icon(Icons.person_add, color: Colors.orange, size: 18),
                  label: const Text(
                    'Cadastrar Novo Funcionário',
                    style: TextStyle(color: Colors.orange, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Divider(color: Colors.white24),
          const SizedBox(height: 16),
          
          // Seção de Materiais
          _buildSecaoMateriais(),
          
          const SizedBox(height: 16),
          const Divider(color: Colors.white24),
          const SizedBox(height: 16),
          const Text(
            'Agendamento (Opcional)',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () async {
                    final data = await showDatePicker(
                      context: context,
                      initialDate: _dataAgendamento ?? DateTime.now(),
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (data != null) {
                      setState(() {
                        _dataAgendamento = data;
                      });
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF181A1B),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_today, color: Colors.white70),
                        const SizedBox(width: 8),
                        Text(
                          _dataAgendamento == null
                              ? 'Selecionar Data'
                              : DateFormat('dd/MM/yyyy').format(_dataAgendamento!),
                          style: TextStyle(
                            color: _dataAgendamento == null
                                ? Colors.white54
                                : Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: InkWell(
                  onTap: () async {
                    final hora = await showTimePicker(
                      context: context,
                      initialTime: _horaAgendamento ?? TimeOfDay.now(),
                    );
                    if (hora != null) {
                      setState(() {
                        _horaAgendamento = hora;
                      });
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF181A1B),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.access_time, color: Colors.white70),
                        const SizedBox(width: 8),
                        Text(
                          _horaAgendamento == null
                              ? 'Selecionar Hora'
                              : _horaAgendamento!.format(context),
                          style: TextStyle(
                            color: _horaAgendamento == null
                                ? Colors.white54
                                : Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _duracaoController,
            keyboardType: TextInputType.number,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: 'Duração (minutos)',
              labelStyle: const TextStyle(color: Colors.white70),
              filled: true,
              fillColor: const Color(0xFF181A1B),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Seção de Materiais
  Widget _buildSecaoMateriais() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.inventory_2, color: Colors.blueAccent, size: 20),
              const SizedBox(width: 8),
              Text(
                'Materiais do Serviço',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_materiaisSelecionados.isEmpty)
            Text(
              'Nenhum material cadastrado. Adicione materiais que serão consumidos ao executar este serviço.',
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            )
          else ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green.withOpacity(0.5)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.green, size: 16),
                  const SizedBox(width: 8),
                  Text(
                    '${_materiaisSelecionados.length} material(is) já cadastrado(s) no serviço',
                    style: const TextStyle(
                      color: Colors.green,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            ..._materiaisSelecionados.asMap().entries.map((entry) {
              final index = entry.key;
              final material = entry.value;
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                color: theme.cardColor,
                child: ListTile(
                  title: Text(
                    material.produtoNome,
                    style: TextStyle(color: colorScheme.onSurface),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Quantidade: ${material.quantidade.toStringAsFixed(2)} ${material.unidade ?? "UN"}',
                        style: TextStyle(color: colorScheme.onSurfaceVariant),
                      ),
                      if (material.precoCusto != null)
                        Text(
                          'Custo: R\$ ${material.precoCusto!.toStringAsFixed(2)}',
                          style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12),
                        ),
                    ],
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () {
                      setState(() {
                        _materiaisSelecionados.removeAt(index);
                      });
                    },
                  ),
                ),
              );
            }),
          ],
          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: () => _mostrarDialogoAdicionarMaterial(context),
            icon: const Icon(Icons.add),
            label: const Text('Adicionar Material'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blueAccent,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  void _mostrarDialogoAdicionarMaterial(BuildContext context) {
    final dataService = Provider.of<DataService>(context, listen: false);
    final produtos = dataService.produtos;
    
    Produto? produtoSelecionado;
    final quantidadeController = TextEditingController();
    final observacaoController = TextEditingController();
    bool isVacina = false;
    DateTime? dataProximaAplicacao;
    final intervaloDiasController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Adicionar Material'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<Produto>(
                            decoration: const InputDecoration(
                              labelText: 'Produto/Material *',
                              border: OutlineInputBorder(),
                            ),
                            items: produtos.map((produto) {
                              return DropdownMenuItem<Produto>(
                                value: produto,
                                child: Text('${produto.nome} (Estoque: ${produto.estoque})'),
                              );
                            }).toList(),
                            onChanged: (produto) {
                              setState(() {
                                produtoSelecionado = produto;
                              });
                            },
                            value: produtoSelecionado,
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.add_circle_outline, color: Colors.blue),
                          tooltip: 'Cadastrar Novo Produto',
                          onPressed: () => _mostrarDialogoCadastroRapidoMaterial(context, setState, (novoProduto) {
                            setState(() {
                              produtoSelecionado = novoProduto;
                            });
                          }),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: quantidadeController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Quantidade *',
                        border: OutlineInputBorder(),
                        helperText: 'Quantidade a ser consumida (permite decimais)',
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (produtoSelecionado != null)
                      Text(
                        'Estoque atual: ${produtoSelecionado!.estoque} ${produtoSelecionado!.unidade}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.blue,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: observacaoController,
                      decoration: const InputDecoration(
                        labelText: 'Observação (opcional)',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 16),
                    // Opções para vacinas
                    CheckboxListTile(
                      title: const Text('É uma vacina (requer agendamento)'),
                      value: isVacina,
                      onChanged: (value) {
                        setState(() {
                          isVacina = value ?? false;
                          if (!isVacina) {
                            dataProximaAplicacao = null;
                            intervaloDiasController.clear();
                          }
                        });
                      },
                    ),
                    if (isVacina) ...[
                      const SizedBox(height: 8),
                      InkWell(
                        onTap: () async {
                          final data = await showDatePicker(
                            context: context,
                            initialDate: dataProximaAplicacao ?? DateTime.now().add(const Duration(days: 30)),
                            firstDate: DateTime.now(),
                            lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
                          );
                          if (data != null) {
                            setState(() {
                              dataProximaAplicacao = data;
                            });
                          }
                        },
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Data da Próxima Aplicação (opcional se informar intervalo)',
                            border: OutlineInputBorder(),
                            suffixIcon: Icon(Icons.calendar_today),
                            helperText: 'Deixe em branco se usar apenas o intervalo de dias',
                          ),
                          child: Text(
                            dataProximaAplicacao != null
                                ? DateFormat('dd/MM/yyyy').format(dataProximaAplicacao!)
                                : 'Selecionar data (opcional)',
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: intervaloDiasController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Intervalo entre doses (dias) *',
                          border: OutlineInputBorder(),
                          helperText: 'Ex: 1 para amanhã, 21 para 3 semanas. Obrigatório se não informar data',
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    quantidadeController.dispose();
                    observacaoController.dispose();
                    Navigator.pop(context);
                  },
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (produtoSelecionado == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Selecione um produto'),
                          backgroundColor: Colors.red,
                        ),
                      );
                      return;
                    }
                    
                    final quantidade = double.tryParse(
                      quantidadeController.text.replaceAll(',', '.'),
                    );
                    
                    if (quantidade == null || quantidade <= 0) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Informe uma quantidade válida'),
                          backgroundColor: Colors.red,
                        ),
                      );
                      return;
                    }

                    final intervaloDias = intervaloDiasController.text.isNotEmpty
                        ? int.tryParse(intervaloDiasController.text)
                        : null;

                    // Validar se é vacina: precisa ter data OU intervalo de dias
                    if (isVacina && dataProximaAplicacao == null && (intervaloDias == null || intervaloDias <= 0)) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Para vacinas, é necessário informar a data da próxima aplicação OU o intervalo em dias'),
                          backgroundColor: Colors.red,
                        ),
                      );
                      return;
                    }

                    this.setState(() {
                      _materiaisSelecionados.add(ItemMaterial(
                        produtoId: produtoSelecionado!.id,
                        produtoNome: produtoSelecionado!.nome,
                        quantidade: quantidade,
                        unidade: produtoSelecionado!.unidade,
                        precoCusto: produtoSelecionado!.precoCusto,
                        precoVenda: produtoSelecionado!.preco,
                        observacao: observacaoController.text.isEmpty
                            ? null
                            : observacaoController.text,
                        isVacina: isVacina,
                        dataProximaAplicacao: dataProximaAplicacao,
                        intervaloDias: intervaloDias,
                      ));
                    });
                    
                    quantidadeController.dispose();
                    observacaoController.dispose();
                    intervaloDiasController.dispose();
                    Navigator.pop(context);
                  },
                  child: const Text('Adicionar'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _mostrarDialogoCadastroRapidoMaterial(
    BuildContext context,
    StateSetter setStateDialogo,
    Function(Produto) onProdutoCriado,
  ) async {
    final dataService = Provider.of<DataService>(context, listen: false);
    final nomeController = TextEditingController();
    final precoCustoController = TextEditingController();
    final estoqueController = TextEditingController(text: '0');
    final unidadeController = TextEditingController(text: 'UN');
    final grupoController = TextEditingController();

    final novoProduto = await showDialog<Produto>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Cadastrar Novo Produto'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: nomeController,
                  decoration: const InputDecoration(
                    labelText: 'Nome do Produto *',
                    border: OutlineInputBorder(),
                  ),
                  autofocus: true,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: precoCustoController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Preço de Custo (R\$) *',
                    border: OutlineInputBorder(),
                    prefixText: 'R\$ ',
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: estoqueController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Estoque Inicial',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: unidadeController,
                        decoration: const InputDecoration(
                          labelText: 'Unidade',
                          border: OutlineInputBorder(),
                          hintText: 'UN',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: grupoController,
                  decoration: const InputDecoration(
                    labelText: 'Grupo/Categoria (opcional)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                nomeController.dispose();
                precoCustoController.dispose();
                estoqueController.dispose();
                unidadeController.dispose();
                grupoController.dispose();
                Navigator.pop(context);
              },
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (nomeController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Informe o nome do produto'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }

                final precoCusto = double.tryParse(
                  precoCustoController.text.replaceAll(',', '.'),
                );
                
                if (precoCusto == null || precoCusto <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Informe um preço de custo válido'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }

                final estoque = int.tryParse(estoqueController.text) ?? 0;
                final unidade = unidadeController.text.trim().isEmpty 
                    ? 'UN' 
                    : unidadeController.text.trim();
                final grupo = grupoController.text.trim().isEmpty 
                    ? 'Sem Grupo' 
                    : grupoController.text.trim();

                // Gerar código automático
                final codigosExistentes = dataService.produtos
                    .map((p) => p.codigo)
                    .toList();
                final codigo = CodigoService.gerarProximoCodigo(codigosExistentes);

                // Para cadastro rápido, definir preço de venda igual ao custo (pode ser alterado depois)
                final produto = Produto(
                  id: DateTime.now().millisecondsSinceEpoch.toString(),
                  codigo: codigo,
                  nome: nomeController.text.trim(),
                  descricao: null,
                  unidade: unidade,
                  grupo: grupo,
                  preco: precoCusto, // Preço de venda inicial igual ao custo
                  precoCusto: precoCusto,
                  estoque: estoque,
                  createdAt: DateTime.now(),
                  updatedAt: DateTime.now(),
                );

                await dataService.addProduto(produto);
                
                nomeController.dispose();
                precoCustoController.dispose();
                estoqueController.dispose();
                unidadeController.dispose();
                grupoController.dispose();
                
                Navigator.pop(context, produto);
                
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Produto "${produto.nome}" cadastrado com sucesso!'),
                    backgroundColor: Colors.green,
                  ),
                );
              },
              child: const Text('Cadastrar'),
            ),
          ],
        );
      },
    );

    if (novoProduto != null) {
      setStateDialogo(() {
        // O produto já foi selecionado no callback
      });
      onProdutoCriado(novoProduto);
    }
  }

  Widget _buildListaServicos() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.3),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Serviços Adicionados',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          ..._servicosSelecionados.map(
            (item) => Card(
              color: const Color(0xFF181A1B),
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.descricao,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                    if (item.descricaoAdicional != null && item.descricaoAdicional!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        item.descricaoAdicional!,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ],
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),
                    Text(
                      'Base: ${NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(item.valor)}',
                      style: const TextStyle(color: Colors.white70),
                    ),
                    if (item.valorAdicional > 0) ...[
                      Text(
                        'Adicional: ${NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(item.valorAdicional)}',
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ],
                    Text(
                      'Total: ${NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(item.valor + item.valorAdicional)}',
                      style: const TextStyle(
                        color: Colors.greenAccent,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (item.funcionarioId != null) ...[
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: FutureBuilder<Funcionario?>(
                          future: _getFuncionarioPorId(item.funcionarioId!),
                          builder: (context, snapshot) {
                            if (snapshot.hasData && snapshot.data != null) {
                              return Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.person, size: 14, color: Colors.orange),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Funcionário: ${snapshot.data!.nome}',
                                    style: const TextStyle(color: Colors.orange, fontSize: 12, fontWeight: FontWeight.w500),
                                  ),
                                ],
                              );
                            }
                            return const SizedBox.shrink();
                          },
                        ),
                      ),
                    ],
                    if (item.valorComissao > 0) ...[
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.account_balance_wallet, size: 14, color: Colors.orange),
                            const SizedBox(width: 4),
                            Text(
                              'Comissão: ${NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(item.valorComissao)}',
                              style: const TextStyle(color: Colors.orange, fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit, color: Colors.blue),
                      tooltip: 'Editar',
                      onPressed: () => _editarServico(item),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      tooltip: 'Remover',
                      onPressed: () {
                        setState(() {
                          _servicosSelecionados.remove(item);
                        });
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
          const Divider(color: Colors.white24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Total:',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(_totalServicos),
                style: const TextStyle(
                  color: Colors.greenAccent,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSecaoPagamentos() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.purple.withOpacity(0.3)),
      ),
      child: PagamentoWidget(
        totalPedido: _totalServicos,
        pagamentos: _pagamentos,
        clienteId: _clienteSelecionado?.id,
        onPagamentosChanged: (novosPagamentos) {
          setState(() {
            _pagamentos = novosPagamentos;
          });
        },
      ),
    );
  }

  // Diálogo para selecionar/cadastrar funcionário e definir comissão
  Future<Map<String, dynamic>?> _mostrarDialogoFuncionarioComissao(BuildContext context) async {
    final dataService = Provider.of<DataService>(context, listen: false);
    Funcionario? funcionarioSelecionado;
    final comissaoController = TextEditingController(text: '0.00');
    final nomeFuncionarioController = TextEditingController();
    final telefoneFuncionarioController = TextEditingController();
    bool cadastrarNovo = false;
    bool comissaoEmPorcentagem = false;
    
    // Calcular total do serviço atual para preview
    final precoBase = double.tryParse(_precoBaseController.text.replaceAll(',', '.')) ?? 0.0;
    final valorAdicional = double.tryParse(_valorAdicionalController.text.replaceAll(',', '.')) ?? 0.0;
    final totalServico = precoBase + valorAdicional;

    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E2E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.person, color: Colors.orange),
              SizedBox(width: 12),
              Text('Funcionário e Comissão', style: TextStyle(color: Colors.white)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: ChoiceChip(
                        label: const Text('Selecionar Existente'),
                        selected: !cadastrarNovo,
                        onSelected: (selected) {
                          setDialogState(() {
                            cadastrarNovo = false;
                            nomeFuncionarioController.clear();
                            telefoneFuncionarioController.clear();
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ChoiceChip(
                        label: const Text('Cadastrar Novo'),
                        selected: cadastrarNovo,
                        onSelected: (selected) {
                          setDialogState(() {
                            cadastrarNovo = true;
                            funcionarioSelecionado = null;
                          });
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (!cadastrarNovo) ...[
                  // Selecionar funcionário existente
                  DropdownButtonFormField<Funcionario?>(
                    value: funcionarioSelecionado,
                    decoration: InputDecoration(
                      labelText: 'Funcionário (opcional)',
                      labelStyle: const TextStyle(color: Colors.white70),
                      filled: true,
                      fillColor: const Color(0xFF181A1B),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    dropdownColor: const Color(0xFF23272A),
                    style: const TextStyle(color: Colors.white),
                    items: [
                      const DropdownMenuItem<Funcionario?>(
                        value: null,
                        child: Text('Nenhum (opcional)', style: TextStyle(color: Colors.white70)),
                      ),
                      ...dataService.funcionarios.where((f) => f.ativo).map((funcionario) {
                        return DropdownMenuItem(
                          value: funcionario,
                          child: Text(funcionario.nome),
                        );
                      }),
                    ],
                    onChanged: (funcionario) {
                      setDialogState(() {
                        funcionarioSelecionado = funcionario;
                      });
                    },
                  ),
                ] else ...[
                  // Cadastrar novo funcionário
                  TextField(
                    controller: nomeFuncionarioController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Nome do Funcionário *',
                      labelStyle: const TextStyle(color: Colors.white70),
                      filled: true,
                      fillColor: const Color(0xFF181A1B),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: telefoneFuncionarioController,
                    style: const TextStyle(color: Colors.white),
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      labelText: 'Telefone (Opcional)',
                      labelStyle: const TextStyle(color: Colors.white70),
                      filled: true,
                      fillColor: const Color(0xFF181A1B),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: ChoiceChip(
                        label: const Text('Valor Fixo (R\$)'),
                        selected: !comissaoEmPorcentagem,
                        onSelected: (selected) {
                          setDialogState(() {
                            comissaoEmPorcentagem = false;
                            comissaoController.clear();
                          });
                        },
                        selectedColor: Colors.orange,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ChoiceChip(
                        label: const Text('Porcentagem (%)'),
                        selected: comissaoEmPorcentagem,
                        onSelected: (selected) {
                          setDialogState(() {
                            comissaoEmPorcentagem = true;
                            comissaoController.clear();
                          });
                        },
                        selectedColor: Colors.orange,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: comissaoController,
                  style: const TextStyle(color: Colors.white),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: comissaoEmPorcentagem ? 'Porcentagem da Comissão (%)' : 'Valor da Comissão (R\$)',
                    labelStyle: const TextStyle(color: Colors.white70),
                    hintText: '0.00',
                    hintStyle: const TextStyle(color: Colors.white38),
                    filled: true,
                    fillColor: const Color(0xFF181A1B),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    prefixText: comissaoEmPorcentagem ? '' : 'R\$ ',
                    suffixText: comissaoEmPorcentagem ? '%' : null,
                  ),
                  onChanged: (value) {
                    setDialogState(() {});
                  },
                ),
                // Preview da comissão calculada
                if (comissaoEmPorcentagem && comissaoController.text.isNotEmpty && totalServico > 0) ...[
                  const SizedBox(height: 12),
                  Builder(
                    builder: (context) {
                      final porcentagem = double.tryParse(comissaoController.text.replaceAll(',', '.')) ?? 0.0;
                      final comissaoCalculada = (totalServico * porcentagem) / 100;
                      
                      return Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Preview da Comissão:',
                              style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${porcentagem.toStringAsFixed(2)}% de ${NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(totalServico)} = ${NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(comissaoCalculada)}',
                              style: const TextStyle(color: Colors.orange, fontSize: 14),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, {
                'funcionario': null,
                'comissao': 0.0,
                'continuar': true, // Flag para indicar que deve continuar
              }), // Retorna resultado vazio para continuar sem funcionário
              child: const Text('Continuar sem funcionário', style: TextStyle(color: Colors.white70)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, null), // Cancelar completamente - retorna null
              child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              onPressed: () async {
                if (cadastrarNovo) {
                  if (nomeFuncionarioController.text.trim().isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Informe o nome do funcionário'),
                        backgroundColor: Colors.red,
                      ),
                    );
                    return;
                  }
                  
                  // Cadastrar novo funcionário
                  final novoFuncionario = Funcionario(
                    id: DateTime.now().millisecondsSinceEpoch.toString(),
                    nome: nomeFuncionarioController.text.trim(),
                    telefone: telefoneFuncionarioController.text.trim().isEmpty
                        ? null
                        : telefoneFuncionarioController.text.trim(),
                    createdAt: DateTime.now(),
                    updatedAt: DateTime.now(),
                  );
                  
                  await dataService.addFuncionario(novoFuncionario);
                  funcionarioSelecionado = novoFuncionario;
                }
                
                // Funcionário agora é opcional - não precisa mais validar
                
                double comissao = 0.0;
                if (comissaoEmPorcentagem && totalServico > 0) {
                  // Calcular comissão baseada na porcentagem
                  final porcentagem = double.tryParse(comissaoController.text.replaceAll(',', '.')) ?? 0.0;
                  comissao = (totalServico * porcentagem) / 100;
                } else {
                  // Valor fixo
                  comissao = double.tryParse(comissaoController.text.replaceAll(',', '.')) ?? 0.0;
                }
                
                Navigator.pop(dialogContext, {
                  'funcionario': funcionarioSelecionado,
                  'comissao': comissao,
                });
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
              ),
              child: const Text('Confirmar'),
            ),
          ],
        ),
      ),
    );
  }

  // Buscar funcionário por ID
  Future<Funcionario?> _getFuncionarioPorId(String id) async {
    final dataService = Provider.of<DataService>(context, listen: false);
    try {
      return dataService.funcionarios.firstWhere((f) => f.id == id);
    } catch (_) {
      return null;
    }
  }

  // Dar baixa no estoque dos materiais dos serviços
  /// Coleta todos os materiais dos serviços para histórico
  List<ItemMaterial> _coletarMateriaisServicos(List<ItemServico> servicos) {
    final materiais = <ItemMaterial>[];
    for (final servico in servicos) {
      if (servico.temMateriais) {
        materiais.addAll(servico.materiais);
      }
    }
    return materiais;
  }

  /// Cria agendamento para próxima dose de vacina
  Future<void> _criarAgendamentoVacina(
    ItemMaterial vacina,
    Cliente? cliente,
    DataService dataService,
  ) async {
    if (!vacina.isVacina) {
      debugPrint('>>> ⚠ Material não é vacina');
      return;
    }

    // Calcular data da próxima aplicação
    DateTime? dataProximaAplicacao = vacina.dataProximaAplicacao;
    
    // Se não há data definida mas há intervalo de dias, calcular automaticamente
    // IMPORTANTE: intervaloDias é sempre em DIAS, não meses
    if (dataProximaAplicacao == null && vacina.intervaloDias != null && vacina.intervaloDias! > 0) {
      // Garantir que estamos usando dias, não meses
      final diasAdicionar = vacina.intervaloDias!; // Já está em dias
      dataProximaAplicacao = DateTime.now().add(Duration(days: diasAdicionar));
      debugPrint('>>>   Data calculada automaticamente: hoje (${DateFormat('dd/MM/yyyy').format(DateTime.now())}) + $diasAdicionar DIA(S) = ${DateFormat('dd/MM/yyyy').format(dataProximaAplicacao)}');
    }
    
    if (dataProximaAplicacao == null) {
      debugPrint('>>> ⚠ Vacina sem data de próxima aplicação e sem intervalo de dias definido');
      return;
    }

    try {
      debugPrint('>>> Criando agendamento para vacina: ${vacina.produtoNome}');
      debugPrint('>>>   Data próxima aplicação: ${DateFormat('dd/MM/yyyy').format(dataProximaAplicacao)}');
      if (vacina.intervaloDias != null) {
        debugPrint('>>>   Intervalo: ${vacina.intervaloDias} DIA(S)');
      }
      
      // Para vacinas, não usamos serviço - apenas os dados da vacina nas observações
      // Usamos um ID especial que identifica como vacina
      final servicoVacinaId = 'vacina_${vacina.produtoId}_${DateTime.now().millisecondsSinceEpoch}';
      debugPrint('>>> Agendamento de vacina (sem serviço cadastrado)');

      // Buscar cliente completo se não foi passado mas temos o ID
      Cliente? clienteCompleto = cliente;
      if (clienteCompleto == null) {
        debugPrint('>>> ⚠ ATENÇÃO: Cliente não fornecido ao criar agendamento de vacina');
        debugPrint('>>>   O agendamento será criado sem cliente associado');
      } else {
        debugPrint('>>> Cliente associado: ${clienteCompleto.nome} (ID: ${clienteCompleto.id})');
      }

      // Garantir que a data tenha uma hora definida (padrão 09:00)
      DateTime dataAgendamentoComHora = dataProximaAplicacao;
      if (dataAgendamentoComHora.hour == 0 && dataAgendamentoComHora.minute == 0) {
        dataAgendamentoComHora = DateTime(
          dataAgendamentoComHora.year,
          dataAgendamentoComHora.month,
          dataAgendamentoComHora.day,
          9, // Hora padrão: 09:00
          0, // Minutos: 00
        );
      }

      // Criar descrição da vacina para usar nas observações (que será exibida ao invés do serviço)
      final descricaoVacina = vacina.intervaloDias != null 
          ? 'Aplicar ${vacina.produtoNome} (intervalo: ${vacina.intervaloDias} dia(s))'
          : 'Aplicar ${vacina.produtoNome}';

      final agendamento = AgendamentoServico(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        numero: '', // Será gerado automaticamente
        servicoId: servicoVacinaId, // ID especial que identifica como vacina
        clienteId: clienteCompleto?.id,
        cliente: clienteCompleto, // Incluir objeto cliente completo com todos os dados
        petId: null, // Vacinas não têm pet específico (será definido quando criar o serviço)
        pet: null,
        dataAgendamento: dataAgendamentoComHora,
        duracaoMinutos: 30, // 30 minutos padrão para vacinação
        observacoes: descricaoVacina, // Descrição da vacina (será exibida ao invés do nome do serviço)
        status: 'Agendado',
      );

      debugPrint('>>> Salvando agendamento na agenda...');
      final agendamentoSalvo = await dataService.addAgendamentoServico(agendamento);
      debugPrint('>>> ✓✓✓ Agendamento SALVO com sucesso! ✓✓✓');
      debugPrint('>>>   Vacina: ${vacina.produtoNome}');
      debugPrint('>>>   Data/Hora: ${DateFormat('dd/MM/yyyy HH:mm').format(dataAgendamentoComHora)}');
      debugPrint('>>>   Cliente: ${clienteCompleto?.nome ?? "Não informado"}');
      debugPrint('>>>   Número: ${agendamentoSalvo.numero}');
      debugPrint('>>>   ID: ${agendamentoSalvo.id}');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Agendamento criado para próxima dose de ${vacina.produtoNome} em ${DateFormat('dd/MM/yyyy').format(dataProximaAplicacao)}'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      debugPrint('>>> ✗ Erro ao criar agendamento de vacina: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao criar agendamento de vacina: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _darBaixaMateriaisServico(
    List<ItemServico> servicos,
    DataService dataService,
  ) async {
    debugPrint('');
    debugPrint('╔════════════════════════════════════════════════╗');
    debugPrint('║  DANDO BAIXA NO ESTOQUE - MATERIAIS SERVIÇOS  ║');
    debugPrint('╚════════════════════════════════════════════════╝');

    int totalMateriais = 0;
    int materiaisComBaixa = 0;
    int materiaisSemEstoque = 0;

    for (final servico in servicos) {
      if (!servico.temMateriais) {
        continue;
      }

      debugPrint('');
      debugPrint('>>> Serviço: ${servico.descricao}');
      
      for (final material in servico.materiais) {
        totalMateriais++;
        
        try {
          // Buscar o produto no estoque
          final produto = dataService.produtos.firstWhere(
            (p) => p.id == material.produtoId,
            orElse: () => throw Exception('Produto não encontrado: ${material.produtoId}'),
          );

          final estoqueAnterior = produto.estoque;
          
          // Para estoque int, considerar a quantidade arredondada para verificação
          // Mas permitir baixas fracionadas na documentação
          final quantidadeParaBaixa = material.quantidade; // Pode ser fracionada
          
          // Verificar se há estoque suficiente (considerando baixas fracionadas)
          // Como o estoque é int, comparamos com a quantidade arredondada para cima
          final quantidadeArredondada = material.quantidade.ceil();
          if (produto.estoque < quantidadeArredondada) {
            debugPrint('>>> ⚠ ATENÇÃO: Estoque insuficiente para ${material.produtoNome}');
            debugPrint('>>>   Estoque disponível: $estoqueAnterior ${produto.unidade}');
            debugPrint('>>>   Quantidade solicitada: ${material.quantidade} ${material.unidade ?? "UN"} (arredondado para cima: $quantidadeArredondada)');
            materiaisSemEstoque++;
            
            // Ainda assim dar a baixa (pode ficar negativo em casos especiais)
            // Mas avisar o usuário
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Atenção: Estoque insuficiente para ${material.produtoNome}. '
                    'Estoque: $estoqueAnterior ${produto.unidade}, '
                    'Necessário: ${material.quantidade} ${material.unidade ?? "UN"}',
                  ),
                  backgroundColor: Colors.orange,
                  duration: const Duration(seconds: 4),
                ),
              );
            }
          }

          // Calcular novo estoque
          // Para baixas fracionadas, subtrair a quantidade exata e arredondar o resultado
          // Usar round() para arredondar corretamente (0.5 vai para cima)
          final novoEstoqueDouble = produto.estoque - quantidadeParaBaixa;
          final novoEstoque = novoEstoqueDouble < 0 ? 0 : novoEstoqueDouble.round();

          // Atualizar produto no estoque
          await dataService.updateProduto(
            produto.copyWith(
              estoque: novoEstoque,
              updatedAt: DateTime.now(),
            ),
          );

          materiaisComBaixa++;
          
          debugPrint('>>> ✓ Baixa no estoque:');
          debugPrint('>>>   Produto: ${material.produtoNome}');
          debugPrint('>>>   Estoque anterior: $estoqueAnterior ${produto.unidade}');
          debugPrint('>>>   Quantidade consumida: ${material.quantidade} ${material.unidade ?? "UN"}');
          debugPrint('>>>   Novo estoque: $novoEstoque ${produto.unidade}');
          
        } catch (e) {
          debugPrint('>>> ✗ ERRO ao dar baixa no material ${material.produtoNome}: $e');
          
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Erro ao dar baixa no estoque de ${material.produtoNome}: $e'),
                backgroundColor: Colors.red,
                duration: const Duration(seconds: 3),
              ),
            );
          }
        }
      }
    }

    debugPrint('');
    debugPrint('>>> RESUMO DA BAIXA NO ESTOQUE:');
    debugPrint('>>>   Total de materiais processados: $totalMateriais');
    debugPrint('>>>   Materiais com baixa realizada: $materiaisComBaixa');
    debugPrint('>>>   Materiais com estoque insuficiente: $materiaisSemEstoque');
    debugPrint('╚════════════════════════════════════════════════╝');
  }

  /// Cria agendamentos para vacinas que precisam de próxima dose
  Future<void> _criarAgendamentosVacinas(
    List<ItemServico> servicos,
    Cliente? cliente,
    DataService dataService,
  ) async {
    debugPrint('');
    debugPrint('╔════════════════════════════════════════════════╗');
    debugPrint('║  CRIANDO AGENDAMENTOS DE RECORRÊNCIA VACINAS  ║');
    debugPrint('╚════════════════════════════════════════════════╝');
    debugPrint('>>> Cliente: ${cliente?.nome ?? "NÃO INFORMADO"}');
    debugPrint('>>> Total de serviços: ${servicos.length}');
    
    int totalVacinas = 0;
    int agendamentosCriados = 0;
    
    for (final servico in servicos) {
      if (!servico.temMateriais) {
        debugPrint('>>> Serviço "${servico.descricao}" não tem materiais');
        continue;
      }

      debugPrint('>>> Serviço "${servico.descricao}" tem ${servico.materiais.length} material(is)');

      for (final material in servico.materiais) {
        debugPrint('>>> Material: ${material.produtoNome}');
        debugPrint('>>>   - isVacina: ${material.isVacina}');
        debugPrint('>>>   - dataProximaAplicacao: ${material.dataProximaAplicacao}');
        debugPrint('>>>   - intervaloDias: ${material.intervaloDias}');
        
        if (material.isVacina) {
          totalVacinas++;
          // Criar agendamento se houver data de próxima aplicação OU intervalo de dias definido
          if (material.dataProximaAplicacao != null || (material.intervaloDias != null && material.intervaloDias! > 0)) {
            debugPrint('>>>   ✓ Vacina com recorrência encontrada!');
            await _criarAgendamentoVacina(material, cliente, dataService);
            agendamentosCriados++;
          } else {
            debugPrint('>>>   ⚠ Vacina sem data de próxima aplicação e sem intervalo de dias');
          }
        }
      }
    }
    
    debugPrint('');
    debugPrint('>>> RESUMO:');
    debugPrint('>>>   - Total de vacinas encontradas: $totalVacinas');
    debugPrint('>>>   - Agendamentos criados: $agendamentosCriados');
    debugPrint('╚════════════════════════════════════════════════╝');
  }

  // Calcular comissão (valor fixo ou porcentagem)
  double _calcularComissao() {
    if (_valorComissaoController.text.isEmpty || _funcionarioSelecionado == null) {
      return 0.0;
    }
    
    final valorDigitado = double.tryParse(_valorComissaoController.text.replaceAll(',', '.')) ?? 0.0;
    
    if (_comissaoEmPorcentagem) {
      // Calcular comissão baseada na porcentagem do total do serviço
      final precoBase = double.tryParse(_precoBaseController.text.replaceAll(',', '.')) ?? 0.0;
      final valorAdicional = double.tryParse(_valorAdicionalController.text.replaceAll(',', '.')) ?? 0.0;
      final totalServico = precoBase + valorAdicional;
      return (totalServico * valorDigitado) / 100;
    } else {
      // Valor fixo
      return valorDigitado;
    }
  }


  void _editarServico(ItemServico itemServico) {
    final index = _servicosSelecionados.indexOf(itemServico);
    if (index == -1) return;

    // Preencher campos com valores atuais
    final nomeController = TextEditingController(text: itemServico.descricao);
    final precoController = TextEditingController(
      text: itemServico.valor.toStringAsFixed(2).replaceAll('.', ','),
    );
    final valorAdicionalController = TextEditingController(
      text: itemServico.valorAdicional > 0 
        ? itemServico.valorAdicional.toStringAsFixed(2).replaceAll('.', ',')
        : '',
    );
    final descricaoAdicionalController = TextEditingController(
      text: itemServico.descricaoAdicional ?? '',
    );
    final duracaoController = TextEditingController(
      text: itemServico.duracaoMinutos?.toString() ?? '60',
    );
    
    DateTime? dataAgendamento = itemServico.dataAgendamento;
    TimeOfDay? horaAgendamento = itemServico.dataAgendamento != null
      ? TimeOfDay.fromDateTime(itemServico.dataAgendamento!)
      : null;
    
    Funcionario? funcionarioSelecionado;
    if (itemServico.funcionarioId != null) {
      final dataService = Provider.of<DataService>(context, listen: false);
      funcionarioSelecionado = dataService.funcionarios
          .firstWhere(
            (f) => f.id == itemServico.funcionarioId,
            orElse: () => Funcionario(
              id: '',
              nome: '',
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ),
          );
      if (funcionarioSelecionado.id.isEmpty) {
        funcionarioSelecionado = null;
      }
    }
    
    final valorComissaoController = TextEditingController(
      text: itemServico.valorComissao > 0
        ? itemServico.valorComissao.toStringAsFixed(2).replaceAll('.', ',')
        : '',
    );

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          insetPadding: EdgeInsets.symmetric(
            horizontal: 16,
            vertical: MediaQuery.of(context).viewInsets.bottom + 24,
          ),
          title: const Row(
            children: [
              Icon(Icons.edit, color: Colors.blue),
              SizedBox(width: 8),
              Text('Editar Serviço'),
            ],
          ),
          content: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: nomeController,
                  decoration: const InputDecoration(
                    labelText: 'Nome do Serviço',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: precoController,
                  decoration: const InputDecoration(
                    labelText: 'Preço Base',
                    prefixText: 'R\$ ',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: valorAdicionalController,
                  decoration: const InputDecoration(
                    labelText: 'Valor Adicional (opcional)',
                    prefixText: 'R\$ ',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: descricaoAdicionalController,
                  decoration: const InputDecoration(
                    labelText: 'Descrição do Valor Adicional',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 16),
                // Data de agendamento
                InkWell(
                  onTap: () async {
                    final data = await showDatePicker(
                      context: context,
                      initialDate: dataAgendamento ?? DateTime.now(),
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (data != null) {
                      setState(() {
                        dataAgendamento = data;
                      });
                    }
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Data de Agendamento (opcional)',
                      border: OutlineInputBorder(),
                      suffixIcon: Icon(Icons.calendar_today),
                    ),
                    child: Text(
                      dataAgendamento != null
                        ? DateFormat('dd/MM/yyyy').format(dataAgendamento!)
                        : 'Não agendado',
                    ),
                  ),
                ),
                if (dataAgendamento != null) ...[
                  const SizedBox(height: 16),
                  // Hora de agendamento
                  InkWell(
                    onTap: () async {
                      final hora = await showTimePicker(
                        context: context,
                        initialTime: horaAgendamento ?? TimeOfDay.now(),
                      );
                      if (hora != null) {
                        setState(() {
                          horaAgendamento = hora;
                        });
                      }
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Hora de Agendamento',
                        border: OutlineInputBorder(),
                        suffixIcon: Icon(Icons.access_time),
                      ),
                      child: Text(
                        horaAgendamento != null
                          ? horaAgendamento!.format(context)
                          : 'Selecionar hora',
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: duracaoController,
                    decoration: const InputDecoration(
                      labelText: 'Duração (minutos)',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ],
                const SizedBox(height: 16),
                // Funcionário
                DropdownButtonFormField<Funcionario?>(
                  decoration: const InputDecoration(
                    labelText: 'Funcionário (opcional)',
                    border: OutlineInputBorder(),
                  ),
                  value: funcionarioSelecionado,
                  items: [
                    const DropdownMenuItem<Funcionario?>(
                      value: null,
                      child: Text('Nenhum'),
                    ),
                    ...Provider.of<DataService>(context, listen: false)
                        .funcionarios
                        .map((f) => DropdownMenuItem<Funcionario?>(
                              value: f,
                              child: Text(f.nome),
                            )),
                  ],
                  onChanged: (value) {
                    setState(() {
                      funcionarioSelecionado = value;
                    });
                  },
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: valorComissaoController,
                  decoration: const InputDecoration(
                    labelText: 'Comissão (opcional)',
                    prefixText: 'R\$ ',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () {
                // Validar campos
                if (nomeController.text.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Informe o nome do serviço'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }

                // Processar valores
                final precoBaseTexto = precoController.text.trim().replaceAll(',', '.');
                final valorAdicionalTexto = valorAdicionalController.text.trim().replaceAll(',', '.');
                
                final precoBase = double.tryParse(precoBaseTexto) ?? 0.0;
                final valorAdicional = valorAdicionalTexto.isEmpty 
                  ? 0.0 
                  : (double.tryParse(valorAdicionalTexto) ?? 0.0);
                final comissao = valorComissaoController.text.trim().isEmpty
                  ? 0.0
                  : (double.tryParse(valorComissaoController.text.trim().replaceAll(',', '.')) ?? 0.0);
                final duracao = int.tryParse(duracaoController.text) ?? 60;

                if (precoBase <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Informe um preço válido'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }

                // Combinar data e hora
                DateTime? dataHoraAgendamento;
                if (dataAgendamento != null && horaAgendamento != null) {
                  dataHoraAgendamento = DateTime(
                    dataAgendamento!.year,
                    dataAgendamento!.month,
                    dataAgendamento!.day,
                    horaAgendamento!.hour,
                    horaAgendamento!.minute,
                  );
                } else if (dataAgendamento != null) {
                  final agora = DateTime.now();
                  dataHoraAgendamento = DateTime(
                    dataAgendamento!.year,
                    dataAgendamento!.month,
                    dataAgendamento!.day,
                    agora.hour,
                    agora.minute,
                  );
                }

                // Atualizar o serviço
                final servicoAtualizado = ItemServico(
                  id: itemServico.id,
                  descricao: nomeController.text,
                  valor: precoBase,
                  valorAdicional: valorAdicional,
                  descricaoAdicional: descricaoAdicionalController.text.isEmpty
                    ? null
                    : descricaoAdicionalController.text,
                  dataAgendamento: dataHoraAgendamento,
                  duracaoMinutos: dataHoraAgendamento != null ? duracao : null,
                  funcionarioId: funcionarioSelecionado?.id,
                  valorComissao: comissao,
                );

                setState(() {
                  _servicosSelecionados[index] = servicoAtualizado;
                });

                Navigator.pop(context);
                
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Serviço atualizado com sucesso!'),
                    backgroundColor: Colors.green,
                    duration: Duration(seconds: 2),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
              child: const Text('Salvar Alterações'),
            ),
          ],
        ),
      ),
    );
  }
}

