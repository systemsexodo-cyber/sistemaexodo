import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import '../services/data_service.dart';
import '../services/firebase_service.dart';
import '../services/agendamento_pdf_service.dart';
import '../models/agendamento_servico.dart';
import '../models/servico.dart';
import '../models/cliente.dart';
import '../models/pet.dart';
import '../models/pedido.dart';
import '../models/item_material.dart';
import '../models/produto.dart';
import '../models/item_servico.dart';
import '../models/empresa.dart';
import '../services/codigo_service.dart';
import '../services/auth_service.dart';

import '../theme.dart';
import 'cliente_detalhes_page.dart';
import 'configuracoes_agenda_page.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
// Import condicional para Web
import 'html_helper_stub.dart' if (dart.library.html) 'html_helper_web.dart' as html_helper;

const uuid = Uuid();

class AgendaServicosPage extends StatefulWidget {
  const AgendaServicosPage({super.key});

  @override
  State<AgendaServicosPage> createState() => _AgendaServicosPageState();
}

class _AgendaServicosPageState extends State<AgendaServicosPage> {
  DateTime _dataSelecionada = DateTime.now();
  String _visualizacao = 'Dia'; // 'Dia', 'Semana', 'Mês'
  DateFormat? _formatoData;
  DateFormat? _formatoHora;
  DateFormat? _formatoDataHora;
  final TextEditingController _buscaController = TextEditingController();
  String _termoBusca = '';
  bool _localeInicializado = false;
  String _filtroTipo = 'Todos'; // 'Todos', 'Banho', 'Vacina', 'Tosa', 'Outros'
  String? _filtroStatus; // null = todos, ou 'Agendado', 'Em Andamento', etc.
  bool _filtrosExpandidos = false; // Controle de visibilidade dos filtros
  bool _mostrarPendentes = true; // Filtro mestre para "Aguardando Confirmação"

  @override
  void initState() {
    super.initState();
    // Inicializar locale
    _inicializarLocale();
  }

  Future<void> _inicializarLocale() async {
    await initializeDateFormatting('pt_BR', null);
    if (mounted) {
      setState(() {
        _formatoData = DateFormat('dd/MM/yyyy', 'pt_BR');
        _formatoHora = DateFormat('HH:mm', 'pt_BR'); // Formato 24 horas (13:00 = 1 hora da tarde)
        _formatoDataHora = DateFormat('dd/MM/yyyy HH:mm', 'pt_BR');
        _localeInicializado = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Mostrar loading enquanto o locale não está inicializado
    if (!_localeInicializado) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: const Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF9800)),
          ),
        ),
      );
    }
    
    return AppTheme.appBackground(
      child: Consumer<DataService>(
        builder: (context, dataService, _) {
          return Scaffold(
            backgroundColor: Colors.transparent,
            appBar: AppBar(
              title: const Text('Agenda de Serviços'),
              backgroundColor: Colors.transparent,
              elevation: 0,
              foregroundColor: Colors.white,
              actions: [
                IconButton(
                  icon: const Icon(Icons.link),
                  onPressed: () => _gerarLinkAgendamento(dataService),
                  tooltip: 'Link de Agendamento Online',
                ),
                // Notificações de Solicitações Online
                Stack(
                  alignment: Alignment.center,
                  children: [
                    IconButton(
                      icon: Icon(
                        Icons.notifications_active, 
                        color: dataService.agendamentosServico.any((a) => a.status == 'Aguardando Confirmação') 
                          ? Colors.amber 
                          : Colors.white70
                      ),
                      tooltip: 'Solicitações de Agendamento',
                      onPressed: () => _mostrarSolicitacoesAgendamento(context, dataService),
                    ),
                    if (dataService.agendamentosServico.any((a) => a.status == 'Aguardando Confirmação'))
                      Positioned(
                        right: 8,
                        top: 8,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                          constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                          child: Text(
                            '${dataService.agendamentosServico.where((a) => a.status == 'Aguardando Confirmação').length}',
                            style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                  ],
                ),
                IconButton(
                  icon: Icon(
                    Icons.sync,
                    color: dataService.firebaseHabilitado ? Colors.green[300] : Colors.red[300],
                  ),
                  onPressed: () => dataService.forceSync(),
                  tooltip: 'Sincronizar Agora',
                ),
                IconButton(
                  icon: const Icon(Icons.map_outlined, color: Colors.lightGreenAccent),
                  onPressed: () => _mostrarMapaDisponibilidade(context, dataService),
                  tooltip: 'Mapa de Disponibilidade',
                ),
                IconButton(
                  icon: const Icon(Icons.settings),
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ConfiguracoesAgendaPage())),
                  tooltip: 'Configurações de Agendamento',
                ),
                IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: () => _mostrarDialogNovoAgendamento(context, dataService),
                  tooltip: 'Novo Agendamento',
                ),
              ],
            ),
            body: Column(
              children: [
                // Controles de navegação
                _buildControlesNavegacao(dataService),
                // Visualização
                Expanded(
                  child: _buildVisualizacao(dataService),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildControlesNavegacao(DataService dataService) {
    // 1. Agendamentos no período respeitando EXCLUSIVAMENTE a BUSCA (Base para contagens)
    final inicio = _visualizacao == 'Dia' 
        ? DateTime(_dataSelecionada.year, _dataSelecionada.month, _dataSelecionada.day)
        : _visualizacao == 'Semana'
            ? _dataSelecionada.subtract(Duration(days: _dataSelecionada.weekday - 1))
            : DateTime(_dataSelecionada.year, _dataSelecionada.month, 1);
    
    final fim = _visualizacao == 'Dia'
        ? inicio.add(const Duration(days: 1))
        : _visualizacao == 'Semana'
            ? inicio.add(const Duration(days: 7))
            : DateTime(_dataSelecionada.year, _dataSelecionada.month + 1, 1);

    final agendamentosNoPeriodo = dataService.getAgendamentosPorPeriodo(inicio, fim);
    
    final agendamentosBase = agendamentosNoPeriodo.where((a) {
      if (_termoBusca.isEmpty) return true;
      final nome = (a.cliente?.nome ?? a.clienteNome ?? '').toLowerCase();
      final pet = (a.pet?.nome ?? a.petNome ?? '').toLowerCase();
      final tsv = _getTipoServico(a).toLowerCase();
      return nome.contains(_termoBusca) || pet.contains(_termoBusca) || tsv.contains(_termoBusca);
    }).toList();

    // 2. Contagens para chips de TIPO (respeitando FILTRO DE STATUS ATUAL)
    final agendamentosParaContarTipo = agendamentosBase.where((a) {
        if (_filtroStatus == null) return true;
        return a.status == _filtroStatus;
    }).toList();
    
    final countsTipo = <String, int>{};
    for (var a in agendamentosParaContarTipo) {
      final tipo = _getTipoServico(a);
      // Normalizar para contagem
      countsTipo[tipo] = (countsTipo[tipo] ?? 0) + 1;
    }

    // 3. Contagens para chips de STATUS (respeitando FILTRO DE TIPO ATUAL)
    final agendamentosParaContarStatus = agendamentosBase.where((a) {
        if (_filtroTipo == 'Todos') return true;
        return _getTipoServico(a) == _filtroTipo;
    }).toList();
    
    final countsStatus = <String, int>{};
    for (var a in agendamentosParaContarStatus) {
      countsStatus[a.status] = (countsStatus[a.status] ?? 0) + 1;
    }

    final isModuloPet = dataService.empresaAtual?.moduloPet ?? false;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.3),
        border: Border(
          bottom: BorderSide(color: Colors.white.withOpacity(0.1)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Campo de busca e Botão de Filtro
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _buscaController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Buscar por nome do cliente...',
                    hintStyle: TextStyle(color: Colors.white.withOpacity(0.6)),
                    prefixIcon: const Icon(Icons.search, color: Colors.white70),
                    suffixIcon: _termoBusca.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, color: Colors.white70),
                            onPressed: () {
                              setState(() {
                                _buscaController.clear();
                                _termoBusca = '';
                              });
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.1),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.white, width: 2),
                    ),
                  ),
                  onChanged: (value) {
                    setState(() {
                      _termoBusca = value.toLowerCase();
                    });
                  },
                ),
              ),
              const SizedBox(width: 8),
              // Botão de Toggle para Pendentes (Aguardando Confirmação)
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => setState(() => _mostrarPendentes = !(_mostrarPendentes ?? true)),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                    decoration: BoxDecoration(
                      color: (_mostrarPendentes ?? true) ? Colors.amber.withOpacity(0.2) : Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: (_mostrarPendentes ?? true) ? Colors.amber : Colors.white.withOpacity(0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          (_mostrarPendentes ?? true) ? Icons.notifications_active : Icons.notifications_off,
                          color: (_mostrarPendentes ?? true) ? Colors.amber : Colors.white70,
                          size: 18,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Pendentes',
                          style: TextStyle(
                            color: (_mostrarPendentes ?? true) ? Colors.white : Colors.white70,
                            fontSize: 11,
                            fontWeight: (_mostrarPendentes ?? true) ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Botão Compacto para Filtros
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => setState(() => _filtrosExpandidos = !_filtrosExpandidos),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _filtrosExpandidos ? Colors.orange.withOpacity(0.2) : Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _filtrosExpandidos ? Colors.orange : Colors.white.withOpacity(0.3),
                      ),
                    ),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Icon(
                          _filtrosExpandidos ? Icons.filter_list_off : Icons.filter_list,
                          color: _filtrosExpandidos ? Colors.orange : Colors.white70,
                        ),
                        if (!_filtrosExpandidos && (_filtroStatus != null || _filtroTipo != 'Todos'))
                          Positioned(
                            top: -2,
                            right: -2,
                            child: Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: Colors.orange,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          
          if (_filtrosExpandidos) ...[
            const SizedBox(height: 12),
            // FILA 1: STATUS
            const Text('Filtrar por Status:', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildChipFiltro(
                    'Todos', 
                    _filtroStatus == null, 
                    () => setState(() => _filtroStatus = null),
                    color: Colors.blue
                  ),
                  const SizedBox(width: 8),
                  if (isModuloPet) ...[
                    _buildChipFiltro(
                      'Pendentes (${countsStatus['Aguardando Confirmação'] ?? 0})', 
                      _filtroStatus == 'Aguardando Confirmação', 
                      () => setState(() => _filtroStatus = 'Aguardando Confirmação'),
                      color: Colors.orange
                    ),
                    const SizedBox(width: 8),
                  ],
                  _buildChipFiltro(
                    'Agendados (${countsStatus['Agendado'] ?? 0})', 
                    _filtroStatus == 'Agendado', 
                    () => setState(() => _filtroStatus = 'Agendado'),
                    color: Colors.blueAccent
                  ),
                  const SizedBox(width: 8),
                  _buildChipFiltro(
                    'Em Andamento (${countsStatus['Em Andamento'] ?? 0})', 
                    _filtroStatus == 'Em Andamento', 
                    () => setState(() => _filtroStatus = 'Em Andamento'),
                    color: Colors.amber
                  ),
                  const SizedBox(width: 8),
                  _buildChipFiltro(
                    'Concluídos (${countsStatus['Concluído'] ?? 0})', 
                    _filtroStatus == 'Concluído', 
                    () => setState(() => _filtroStatus = 'Concluído'),
                    color: Colors.green
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // FILA 2: SERVIÇOS
            const Text('Filtrar por Serviço:', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildChipFiltro(
                    'Todos', 
                    _filtroTipo == 'Todos', 
                    () => setState(() => _filtroTipo = 'Todos')
                  ),
                  if (isModuloPet) ...[
                    const SizedBox(width: 8),
                    _buildChipFiltro(
                      'Banho (${countsTipo['Banho'] ?? 0})', 
                      _filtroTipo == 'Banho', 
                      () => setState(() => _filtroTipo = 'Banho'),
                      color: Colors.cyan
                    ),
                    const SizedBox(width: 8),
                    _buildChipFiltro(
                      'Tosa (${countsTipo['Tosa'] ?? 0})', 
                      _filtroTipo == 'Tosa', 
                      () => setState(() => _filtroTipo = 'Tosa'),
                      color: Colors.purpleAccent
                    ),
                    const SizedBox(width: 8),
                    _buildChipFiltro(
                      'Vacina (${countsTipo['Vacina'] ?? 0})', 
                      _filtroTipo == 'Vacina', 
                      () => setState(() => _filtroTipo = 'Vacina'),
                      color: Colors.redAccent
                    ),
                  ],
                  // Serviços cadastrados que não sejam os básicos acima
                  ...dataService.servicos
                      .where((s) {
                        final n = s.nome.toLowerCase().trim();
                        // Não mostrar serviços básicos que já possuem chips fixos (normalizado)
                        if (n == 'banho' || n == 'tosa' || n == 'vacina') return false;
                        // Não mostrar serviços poluídos com Taxi Dog ou Entrega no nome
                        if (n.contains('taxi dog') || n.contains('entrega')) return false;
                        return true;
                      })
                      .map((servico) {
                    final qte = countsTipo[servico.nome] ?? 0;
                    return Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: _buildChipFiltro(
                        '${servico.nome} ($qte)',
                        _filtroTipo == servico.nome,
                        () => setState(() => _filtroTipo = servico.nome),
                      ),
                    );
                  }),
                  const SizedBox(width: 8),
                  _buildChipFiltro(
                    'Outros (${countsTipo['Outros'] ?? 0})', 
                    _filtroTipo == 'Outros', 
                    () => setState(() => _filtroTipo = 'Outros')
                  ),
                ],
              ),
            ),
            
            if (_filtroStatus != null || _filtroTipo != 'Todos' || _termoBusca.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _filtroStatus = null;
                      _filtroTipo = 'Todos';
                      _termoBusca = '';
                      _buscaController.clear();
                    });
                  },
                  icon: const Icon(Icons.filter_list_off, size: 16, color: Colors.white70),
                  label: const Text('Limpar Filtros', style: TextStyle(color: Colors.white70, fontSize: 12)),
                ),
              ),
          ],
          const SizedBox(height: 10),
          // Seletor de visualização e Navegação
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Lado Esquerdo: Seletor (Compacto)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildBotaoVisualizacao('Dia', Icons.view_day),
                  const SizedBox(width: 4),
                  _buildBotaoVisualizacao('Semana', Icons.view_week),
                  const SizedBox(width: 4),
                  _buildBotaoVisualizacao('Mês', Icons.calendar_month),
                ],
              ),
              
              // Lado Direito: Navegador de Data (Destaque)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left, color: Colors.white70, size: 20),
                    onPressed: () {
                      setState(() {
                        if (_visualizacao == 'Dia') {
                          _dataSelecionada = _dataSelecionada.subtract(const Duration(days: 1));
                        } else if (_visualizacao == 'Semana') {
                          _dataSelecionada = _dataSelecionada.subtract(const Duration(days: 7));
                        } else {
                          _dataSelecionada = DateTime(_dataSelecionada.year, _dataSelecionada.month - 1);
                        }
                      });
                    },
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => _selecionarData(context),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.blueAccent.withOpacity(0.4), Colors.blue.withOpacity(0.2)],
                        ),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.blueAccent.withOpacity(0.5), width: 1.5),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.blue.withOpacity(0.1),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Text(
                        _getTextoData(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.chevron_right, color: Colors.white70, size: 20),
                    onPressed: () {
                      setState(() {
                        if (_visualizacao == 'Dia') {
                          _dataSelecionada = _dataSelecionada.add(const Duration(days: 1));
                        } else if (_visualizacao == 'Semana') {
                          _dataSelecionada = _dataSelecionada.add(const Duration(days: 7));
                        } else {
                          _dataSelecionada = DateTime(_dataSelecionada.year, _dataSelecionada.month + 1);
                        }
                      });
                    },
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBotaoVisualizacao(String tipo, IconData icon) {
    final isSelecionado = _visualizacao == tipo;
    return GestureDetector(
      onTap: () => setState(() => _visualizacao = tipo),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelecionado 
              ? Colors.blue.withOpacity(0.3)
              : Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelecionado 
                ? Colors.blueAccent
                : Colors.white.withOpacity(0.1),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: isSelecionado ? Colors.blueAccent : Colors.white60, size: 14),
            const SizedBox(width: 4),
            Text(
              tipo,
              style: TextStyle(
                color: isSelecionado ? Colors.white : Colors.white60,
                fontWeight: isSelecionado ? FontWeight.bold : FontWeight.normal,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getTextoData() {
    if (_visualizacao == 'Dia') {
      return _formatoData!.format(_dataSelecionada);
    } else if (_visualizacao == 'Semana') {
      final inicioSemana = _dataSelecionada.subtract(Duration(days: _dataSelecionada.weekday - 1));
      final fimSemana = inicioSemana.add(const Duration(days: 6));
      return '${_formatoData!.format(inicioSemana)} - ${_formatoData!.format(fimSemana)}';
    } else {
      return DateFormat('MMMM yyyy', 'pt_BR').format(_dataSelecionada);
    }
  }

  Future<void> _selecionarData(BuildContext context) async {
    final data = await showDatePicker(
      context: context,
      initialDate: _dataSelecionada,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (data != null) {
      setState(() => _dataSelecionada = data);
    }
  }

  Widget _buildChipFiltro(String label, bool selecionado, VoidCallback onTap, {Color? color}) {
    final primaryColor = color ?? const Color(0xFFFF9800);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selecionado 
              ? primaryColor.withOpacity(0.3)
              : Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selecionado 
                ? primaryColor
                : Colors.white.withOpacity(0.3),
            width: selecionado ? 2 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selecionado ? Colors.white : Colors.white70,
            fontSize: 12,
            fontWeight: selecionado ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildVisualizacao(DataService dataService) {
    final agendamentos = _getAgendamentosPeriodo(dataService);
    
    if (_visualizacao == 'Dia') {
      return _buildVisualizacaoDia(agendamentos, dataService);
    } else if (_visualizacao == 'Semana') {
      return _buildVisualizacaoSemana(agendamentos, dataService);
    } else {
      return _buildVisualizacaoMes(agendamentos, dataService);
    }
  }

  // Retorna o tipo de serviço baseado no nome
  String _getTipoServico(AgendamentoServico agendamento) {
    // 1. Tentar identificar por nome do serviço de forma normalizada
    final nomeServico = (agendamento.servico?.nome ?? agendamento.servicoNome ?? '').toLowerCase().trim();
    
    if (nomeServico == 'banho' || nomeServico.contains('banho ') || nomeServico.startsWith('banho')) { // Ex: "Banho", "Banho e Tosa" (inicia com banho)
       // Se for exatamente "banho" ou começar com banho, podemos agrupar se o usuário preferir, 
       // mas se for "Banho e Tosa", talvez seja melhor categorizar como preferir.
       // Seguindo a lógica atual de agendamento_publico_page:
       if (nomeServico.contains('banho')) return 'Banho';
    }
    
    if (nomeServico == 'vacina' || nomeServico.contains('vacinar')) return 'Vacina';
    if (nomeServico == 'tosa' && !nomeServico.contains('comp')) return 'Tosa'; // Apenas "Tosa" simples
    
    // 2. Se for um serviço cadastrado e não for um dos básicos acima, retornar nome original para chip dinâmico
    if (agendamento.servico != null) {
      final n = agendamento.servico!.nome;
      final nl = n.toLowerCase();
      // Se for um dos básicos em qualquer case, retornar Capitalizado
      if (nl == 'banho') return 'Banho';
      if (nl == 'tosa') return 'Tosa';
      if (nl == 'vacina') return 'Vacina';
      return n;
    }
    
    final dataService = Provider.of<DataService>(context, listen: false);
    final isModuloPet = dataService.empresaAtual?.moduloPet ?? false;
    
    if (!isModuloPet) {
      return 'Serviço';
    }

    final observacoes = agendamento.observacoes?.toLowerCase() ?? '';
    final textoCompleto = '$nomeServico $observacoes';
    
    if (_isAgendamentoVacina(agendamento) || textoCompleto.contains('vacina')) {
      return 'Vacina';
    } else if (textoCompleto.contains('banho') || textoCompleto.contains('bath')) {
      return 'Banho';
    } else if (textoCompleto.contains('tosa') || textoCompleto.contains('grooming')) {
      return 'Tosa';
    } else {
      return 'Outros';
    }
  }

  // Retorna o ícone apropriado para o tipo de serviço
  IconData _getIconeTipoServico(AgendamentoServico agendamento) {
    final tipo = _getTipoServico(agendamento);
    switch (tipo) {
      case 'Vacina':
        return Icons.vaccines;
      case 'Banho':
        return Icons.shower;
      case 'Tosa':
        return Icons.content_cut;
      case 'Serviço':
        return Icons.miscellaneous_services;
      default:
        return Icons.calendar_today;
    }
  }

  List<AgendamentoServico> _getAgendamentosPeriodo(DataService dataService, {String? tipoFiltroOverride}) {
    DateTime inicio, fim;
    
    if (_visualizacao == 'Dia') {
      inicio = DateTime(_dataSelecionada.year, _dataSelecionada.month, _dataSelecionada.day);
      fim = inicio.add(const Duration(days: 1));
    } else if (_visualizacao == 'Semana') {
      inicio = _dataSelecionada.subtract(Duration(days: _dataSelecionada.weekday - 1));
      inicio = DateTime(inicio.year, inicio.month, inicio.day);
      fim = inicio.add(const Duration(days: 7));
    } else {
      inicio = DateTime(_dataSelecionada.year, _dataSelecionada.month, 1);
      fim = DateTime(_dataSelecionada.year, _dataSelecionada.month + 1, 1);
    }
    
    var agendamentos = dataService.getAgendamentosPorPeriodo(inicio, fim);
    
    // Filtro Mestre: Mostrar ou não pendentes
    if (!(_mostrarPendentes ?? true)) {
      agendamentos = agendamentos.where((a) => a.status != 'Aguardando Confirmação').toList();
    }
    
    // Filtrar por tipo de serviço
    final filtroParaUsar = tipoFiltroOverride ?? _filtroTipo;
    if (filtroParaUsar != 'Todos') {
      agendamentos = agendamentos.where((a) {
        return _getTipoServico(a) == filtroParaUsar;
      }).toList();
    }
    
    // Filtrar por status
    if (_filtroStatus != null) {
      agendamentos = agendamentos.where((a) {
        return a.status == _filtroStatus;
      }).toList();
    }
    
    // Aplicar filtro de busca (agora inclui tipo de serviço)
    if (_termoBusca.isNotEmpty) {
      agendamentos = agendamentos.where((a) {
        final nomeCliente = (a.cliente?.nome ?? a.clienteNome ?? '').toLowerCase();
        final nomePet = (a.pet?.nome ?? a.petNome ?? '').toLowerCase();
        final nomeServico = (a.servico?.nome ?? '').toLowerCase();
        final observacoes = (a.observacoes ?? '').toLowerCase();
        final tipoServico = _getTipoServico(a).toLowerCase();
        return nomeCliente.contains(_termoBusca) || 
               nomePet.contains(_termoBusca) ||
               nomeServico.contains(_termoBusca) ||
               observacoes.contains(_termoBusca) ||
               tipoServico.contains(_termoBusca);
      }).toList();
    }
    
    return agendamentos;
  }

  Widget _buildVisualizacaoDia(List<AgendamentoServico> agendamentos, DataService dataService) {
    // Agrupar por hora
    final agendamentosPorHora = <int, List<AgendamentoServico>>{};
    for (final agendamento in agendamentos) {
      final hora = agendamento.dataAgendamento.hour;
      agendamentosPorHora.putIfAbsent(hora, () => []).add(agendamento);
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: 24, // 24 horas do dia
      itemBuilder: (context, index) {
        final hora = index;
        final agendamentosHora = agendamentosPorHora[hora] ?? [];
        
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Hora
              SizedBox(
                width: 60,
                child: Text(
                  '${hora.toString().padLeft(2, '0')}:00',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.6),
                    fontSize: 12,
                  ),
                ),
              ),
              // Agendamentos
              Expanded(
                child: Column(
                  children: agendamentosHora.isEmpty
                      ? [
                          GestureDetector(
                            onTap: () {
                              // Criar agendamento ao clicar no horário vazio
                              final dataHora = DateTime(
                                _dataSelecionada.year,
                                _dataSelecionada.month,
                                _dataSelecionada.day,
                                hora,
                                0,
                              );
                              _mostrarDialogNovoAgendamento(context, dataService, dataHoraPreSelecionada: dataHora);
                            },
                            child: Container(
                              height: 40,
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.1),
                                  width: 1,
                                ),
                                borderRadius: BorderRadius.circular(8),
                                color: Colors.transparent,
                              ),
                              child: Center(
                                child: Icon(
                                  Icons.add_circle_outline,
                                  color: Colors.white.withOpacity(0.3),
                                  size: 20,
                                ),
                              ),
                            ),
                          ),
                        ]
                      : _buildAgendamentosAgrupados(agendamentosHora, dataService, hora),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Agrupa agendamentos do mesmo cliente quando houver 3 ou mais
  List<Widget> _buildAgendamentosAgrupados(
    List<AgendamentoServico> agendamentos,
    DataService dataService,
    int hora,
  ) {
    // Agrupar por cliente
    final agendamentosPorCliente = <String?, List<AgendamentoServico>>{};
    for (final agendamento in agendamentos) {
      final clienteId = agendamento.clienteId;
      agendamentosPorCliente.putIfAbsent(clienteId, () => []).add(agendamento);
    }

    final widgets = <Widget>[];

    for (final entry in agendamentosPorCliente.entries) {
      final clienteId = entry.key;
      final agendamentosCliente = entry.value;

      // Se houver 3 ou mais agendamentos do mesmo cliente, mostrar indicador de grupo
      if (agendamentosCliente.length >= 3 && clienteId != null) {
        // Adicionar indicador de grupo antes dos agendamentos
        widgets.add(
          Container(
            margin: const EdgeInsets.only(bottom: 4),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.amber.withOpacity(0.2),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: Colors.amber.withOpacity(0.5),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.group,
                  size: 14,
                  color: Colors.amber,
                ),
                const SizedBox(width: 6),
                Text(
                  '${agendamentosCliente.length} animais - ${agendamentosCliente.first.cliente?.nome ?? "Cliente"}',
                  style: const TextStyle(
                    color: Colors.amber,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        );
      }
      
      // Exibir todos os agendamentos normalmente (mantendo padrão)
      for (final agendamento in agendamentosCliente) {
        widgets.add(_buildCardAgendamento(agendamento, dataService));
      }
    }

    // Adicionar botão para adicionar mais agendamentos
    widgets.add(
      Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              // Criar agendamento ao clicar no botão de adicionar
              final dataHora = DateTime(
                _dataSelecionada.year,
                _dataSelecionada.month,
                _dataSelecionada.day,
                hora,
                0,
              );
              _mostrarDialogNovoAgendamento(context, dataService, dataHoraPreSelecionada: dataHora);
            },
            borderRadius: BorderRadius.circular(6),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              decoration: BoxDecoration(
                border: Border.all(
                  color: Colors.blue.withOpacity(0.3),
                  width: 1,
                ),
                borderRadius: BorderRadius.circular(6),
                color: Colors.blue.withOpacity(0.1),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.add,
                    color: Colors.blue.withOpacity(0.7),
                    size: 16,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Adicionar',
                    style: TextStyle(
                      color: Colors.blue.withOpacity(0.7),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    return widgets;
  }


  Widget _buildVisualizacaoSemana(List<AgendamentoServico> agendamentos, DataService dataService) {
    final inicioSemana = _dataSelecionada.subtract(Duration(days: _dataSelecionada.weekday - 1));
    
    return Row(
      children: List.generate(7, (index) {
        final dia = inicioSemana.add(Duration(days: index));
        final agendamentosDia = agendamentos.where((a) {
          return a.dataAgendamento.year == dia.year &&
                 a.dataAgendamento.month == dia.month &&
                 a.dataAgendamento.day == dia.day;
        }).toList();
        
        return Expanded(
          child: Container(
            margin: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: Column(
              children: [
                // Cabeçalho do dia
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    gradient: _isHoje(dia)
                        ? LinearGradient(
                            colors: [
                              const Color(0xFF2196F3).withOpacity(0.4),
                              const Color(0xFF42A5F5).withOpacity(0.2),
                            ],
                          )
                        : null,
                    color: _isHoje(dia) ? null : Colors.transparent,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                    border: _isHoje(dia)
                        ? Border.all(
                            color: const Color(0xFF2196F3).withOpacity(0.6),
                            width: 2,
                          )
                        : null,
                  ),
                  child: Column(
                    children: [
                      Text(
                        DateFormat('EEE', 'pt_BR').format(dia),
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.7),
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        dia.day.toString(),
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                // Agendamentos do dia
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(4),
                    itemCount: agendamentosDia.length,
                    itemBuilder: (context, index) {
                      return _buildCardAgendamentoCompacto(agendamentosDia[index], dataService);
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }

  Widget _buildVisualizacaoMes(List<AgendamentoServico> agendamentos, DataService dataService) {
    final primeiroDia = DateTime(_dataSelecionada.year, _dataSelecionada.month, 1);
    final ultimoDia = DateTime(_dataSelecionada.year, _dataSelecionada.month + 1, 0);
    final diasNoMes = ultimoDia.day;
    final primeiroDiaSemana = primeiroDia.weekday;
    
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        childAspectRatio: 1,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
      ),
      itemCount: 7 + diasNoMes, // 7 cabeçalhos + dias do mês
      itemBuilder: (context, index) {
        if (index < 7) {
          // Cabeçalhos dos dias da semana
          final diasSemana = ['Dom', 'Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb'];
          return Center(
            child: Text(
              diasSemana[index],
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          );
        }
        
        final diaIndex = index - 7;
        if (diaIndex < primeiroDiaSemana - 1 || diaIndex >= primeiroDiaSemana - 1 + diasNoMes) {
          return const SizedBox.shrink();
        }
        
        final dia = primeiroDia.add(Duration(days: diaIndex - (primeiroDiaSemana - 1)));
        final agendamentosDia = agendamentos.where((a) {
          return a.dataAgendamento.year == dia.year &&
                 a.dataAgendamento.month == dia.month &&
                 a.dataAgendamento.day == dia.day;
        }).toList();
        
        return GestureDetector(
          onTap: () {
            setState(() {
              _dataSelecionada = dia;
              _visualizacao = 'Dia';
            });
          },
          child: Container(
            decoration: BoxDecoration(
              gradient: _isHoje(dia)
                  ? LinearGradient(
                      colors: [
                        const Color(0xFF2196F3).withOpacity(0.4),
                        const Color(0xFF42A5F5).withOpacity(0.2),
                      ],
                    )
                  : null,
              color: _isHoje(dia) ? null : const Color(0xFF1E1E2E).withOpacity(0.6),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: _isHoje(dia)
                    ? const Color(0xFF2196F3).withOpacity(0.8)
                    : Colors.white.withOpacity(0.2),
                width: _isHoje(dia) ? 2 : 1,
              ),
              boxShadow: _isHoje(dia)
                  ? [
                      BoxShadow(
                        color: const Color(0xFF2196F3).withOpacity(0.3),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.all(4),
                  child: Text(
                    dia.day.toString(),
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: _isHoje(dia) ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ),
                if (agendamentosDia.isNotEmpty)
                  Expanded(
                    child: ListView.builder(
                      padding: EdgeInsets.zero,
                      itemCount: agendamentosDia.length > 3 ? 3 : agendamentosDia.length,
                      itemBuilder: (context, index) {
                        final agendamento = agendamentosDia[index];
                        final isVacina = (agendamento.servicoId?.startsWith('vacina_') ?? false) || 
                                        (agendamento.observacoes != null && agendamento.observacoes!.toLowerCase().contains('aplicar'));
                        final corStatus = isVacina ? const Color(0xFFFF9800) : _getCorStatus(agendamento.status);
                        final corFundo = isVacina ? const Color(0xFF663C00) : _getCorFundoStatus(agendamento.status);
                        
                        return Container(
                          margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                corFundo,
                                Color.lerp(corFundo, corStatus, 0.4)!,
                              ],
                            ),
                            borderRadius: BorderRadius.circular(3),
                            border: Border.all(
                              color: corStatus.withOpacity(0.7),
                              width: 1,
                            ),
                          ),
                          child: Text(
                            '${_formatoHora!.format(agendamento.dataAgendamento)}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 8,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      },
                    ),
                  ),
                if (agendamentosDia.length > 3)
                  Padding(
                    padding: const EdgeInsets.all(2),
                    child: Text(
                      '+${agendamentosDia.length - 3}',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.6),
                        fontSize: 8,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  bool _isHoje(DateTime data) {
    final hoje = DateTime.now();
    return data.year == hoje.year &&
           data.month == hoje.month &&
           data.day == hoje.day;
  }

  Color _getCorStatus(String status) {
    switch (status) {
      case 'Aguardando Confirmação':
        return Colors.purpleAccent;
      case 'Agendado':
        return const Color(0xFF2196F3); // Azul vibrante do tema
      case 'Em Andamento':
        return const Color(0xFFFF9800); // Laranja vibrante
      case 'Concluído':
        return const Color(0xFF4CAF50); // Verde vibrante
      case 'Cancelado':
        return const Color(0xFFF44336); // Vermelho vibrante
      default:
        return const Color(0xFF757575); // Cinza
    }
  }

  Color _getCorFundoStatus(String status) {
    switch (status) {
      case 'Aguardando Confirmação':
        return Colors.purple.shade900;
      case 'Agendado':
        return const Color(0xFF1E3A5F); // Azul escuro
      case 'Em Andamento':
        return const Color(0xFF663C00); // Laranja escuro
      case 'Concluído':
        return const Color(0xFF1B5E20); // Verde escuro
      case 'Cancelado':
        return const Color(0xFF5D1F1F); // Vermelho escuro
      default:
        return const Color(0xFF2C2C2C); // Cinza escuro
    }
  }

  // Verifica se o agendamento é de vacina
  bool _isAgendamentoVacina(AgendamentoServico agendamento) {
    return (agendamento.servicoId?.startsWith('vacina_') ?? false) || 
           (agendamento.observacoes != null && agendamento.observacoes!.toLowerCase().contains('aplicar'));
  }

  // Obtém cor para agendamentos de vacina (laranja)
  Color _getCorVacina() {
    return const Color(0xFFFF9800); // Laranja
  }

  Color _getCorFundoVacina() {
    return const Color(0xFF663C00); // Laranja escuro
  }

  Widget _buildCardAgendamento(AgendamentoServico agendamento, DataService dataService) {
    final isVacina = _isAgendamentoVacina(agendamento);
    final corStatus = isVacina ? _getCorVacina() : _getCorStatus(agendamento.status);
    final tipoServico = _getTipoServico(agendamento);
    final iconeServico = _getIconeTipoServico(agendamento);
    final nomeCliente = agendamento.cliente?.nome ?? agendamento.clienteNome;
    final nomePet = agendamento.pet?.nome ?? agendamento.petNome;
    final racaPet = agendamento.pet?.raca;
    final nomeServico = isVacina 
        ? (agendamento.observacoes ?? 'Vacina')
        : (agendamento.servico?.nome ?? 'Serviço');
    final isTaxiDog = agendamento.tipoEntrega == 'Taxi Dog' || 
        agendamento.tipoEntrega == 'Apenas Busca' || 
        agendamento.tipoEntrega == 'Apenas Entrega';
    
    // Verificar se faz parte de um grupo de múltiplos pets no mesmo horário
    final isGrupoMultiPet = dataService.agendamentosServico.any((a) => 
        a.id != agendamento.id &&
        a.clienteId != null &&
        a.clienteId == agendamento.clienteId &&
        a.dataAgendamento.isAtSameMomentAs(agendamento.dataAgendamento) &&
        a.status != 'Cancelado'
    );

    return GestureDetector(
      onTap: () => _mostrarDetalhesAgendamento(context, agendamento, dataService),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A2E),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isGrupoMultiPet ? Colors.orange.withOpacity(0.3) : Colors.white.withOpacity(0.06),
            width: isGrupoMultiPet ? 1.5 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: isGrupoMultiPet ? Colors.orange.withOpacity(0.05) : Colors.black.withOpacity(0.2),
              blurRadius: isGrupoMultiPet ? 10 : 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Barra lateral colorida (estilo Google Calendar)
                Container(
                  width: 5,
                  decoration: BoxDecoration(
                    color: corStatus,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(14),
                      bottomLeft: Radius.circular(14),
                    ),
                  ),
                ),
                // Conteúdo principal
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Linha 1: Serviço + Horário + Ação
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Ícone do serviço
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: corStatus.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(iconeServico, color: corStatus, size: 18),
                            ),
                            const SizedBox(width: 10),
                            // Nome do serviço e tipo
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    nomeServico,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.2,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 3),
                                  // Badges: tipo + valor
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: corStatus.withOpacity(0.15),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          tipoServico,
                                          style: TextStyle(
                                            color: corStatus,
                                            fontSize: 9,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                      if (agendamento.servico != null && agendamento.servico!.preco > 0) ...[
                                        const SizedBox(width: 6),
                                        Text(
                                          'R\$ ${agendamento.servico!.precoTotal.toStringAsFixed(2)}',
                                          style: TextStyle(
                                            color: Colors.white.withOpacity(0.6),
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            // Coluna direita: Horário + Ação rápida
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                // Horário
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: corStatus.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    _formatoHora!.format(agendamento.dataAgendamento),
                                    style: TextStyle(
                                      color: corStatus,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                // Ação rápida
                                if (agendamento.status == 'Agendado')
                                  _buildQuickActionButton(
                                    icon: Icons.play_arrow_rounded,
                                    color: Colors.amber,
                                    tooltip: 'Iniciar',
                                    onPressed: () => _marcarEmAndamento(agendamento, dataService),
                                  ),
                                if (agendamento.status == 'Em Andamento')
                                  _buildQuickActionButton(
                                    icon: Icons.check_circle_rounded,
                                    color: Colors.green,
                                    tooltip: 'Concluir',
                                    onPressed: () => _marcarConcluido(agendamento, dataService),
                                  ),
                              ],
                            ),
                          ],
                        ),
                        // Linha 2: Cliente + Pet (compacta)
                        if (nomeCliente != null || nomePet != null) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              if (nomeCliente != null) ...[
                                Icon(Icons.person_rounded, size: 13, color: Colors.white.withOpacity(0.5)),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    nomeCliente,
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.85),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                              if (nomeCliente != null && nomePet != null)
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 6),
                                  child: Text('•', style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 12)),
                                ),
                              if (nomePet != null) ...[
                                Icon(Icons.pets_rounded, size: 13, color: Colors.orange.withOpacity(0.7)),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Builder(
                                    builder: (context) {
                                      // Buscar outros agendamentos do mesmo cliente no mesmo horário
                                      final agendamentosMesmoHorario = dataService.agendamentosServico.where((a) => 
                                        a.clienteId != null && 
                                        a.clienteId == agendamento.clienteId && 
                                        a.dataAgendamento.isAtSameMomentAs(agendamento.dataAgendamento) &&
                                        a.status != 'Cancelado'
                                      ).toList();

                                      // Ordenar por ID para garantir ordem consistente
                                      agendamentosMesmoHorario.sort((a, b) => a.id.compareTo(b.id));
                                      
                                      final totalPets = agendamentosMesmoHorario.length;
                                      final indicePet = agendamentosMesmoHorario.indexWhere((a) => a.id == agendamento.id) + 1;

                                      return Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Flexible(
                                            child: Text(
                                              '$nomePet${racaPet != null ? ' ($racaPet)' : ''}',
                                              style: TextStyle(
                                                color: Colors.white.withOpacity(0.85),
                                                fontSize: 12,
                                                fontWeight: FontWeight.w500,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          if (totalPets > 1) ...[
                                            const SizedBox(width: 6),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                              decoration: BoxDecoration(
                                                color: Colors.orange.withOpacity(0.2),
                                                borderRadius: BorderRadius.circular(4),
                                                border: Border.all(color: Colors.orange.withOpacity(0.4), width: 0.5),
                                              ),
                                              child: Text(
                                                'PET $indicePet DE $totalPets',
                                                style: const TextStyle(
                                                  color: Colors.orange,
                                                  fontSize: 8,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      );
                                    }
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                        // Observações do pet (se houver, muito compacto)
                        if (agendamento.pet?.observacoes != null && agendamento.pet!.observacoes!.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Padding(
                            padding: const EdgeInsets.only(left: 17),
                            child: Text(
                              agendamento.pet!.observacoes!,
                              style: TextStyle(
                                color: Colors.orange.withOpacity(0.5),
                                fontSize: 10,
                                fontStyle: FontStyle.italic,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                        // Endereço de Entrega (Muito importante para visualização rápida)
                        if (isTaxiDog && agendamento.endereco != null && agendamento.endereco!.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.green.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.green.withOpacity(0.2), width: 0.5),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: Colors.green.withOpacity(0.2),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.location_on_rounded, size: 10, color: Colors.green),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    '${agendamento.endereco}${agendamento.numeroEndereco != null && agendamento.numeroEndereco!.isNotEmpty ? ', ${agendamento.numeroEndereco}' : ''}${agendamento.bairroEntrega != null ? ' - ${agendamento.bairroEntrega}' : ''}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        // Materiais (compacto, inline)
                        Builder(
                          builder: (context) {
                            final todosMateriais = [
                              ...agendamento.materiais,
                              if (agendamento.servico != null) ...agendamento.servico!.materiais,
                            ];
                            if (todosMateriais.isEmpty) return const SizedBox.shrink();
                            return Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Wrap(
                                spacing: 4,
                                runSpacing: 3,
                                children: todosMateriais.take(3).map((material) {
                                  return Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: (material.isVacina ? Colors.green : Colors.blue).withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          material.isVacina ? Icons.vaccines : Icons.inventory_2,
                                          size: 9,
                                          color: material.isVacina ? Colors.green : Colors.blue,
                                        ),
                                        const SizedBox(width: 3),
                                        Flexible(
                                          child: Text(
                                            '${material.produtoNome} (${material.quantidade.toStringAsFixed(material.quantidade % 1 == 0 ? 0 : 2)}${material.unidade != null ? ' ${material.unidade}' : ''})',
                                            style: TextStyle(
                                              color: Colors.white.withOpacity(0.7),
                                              fontSize: 9,
                                              fontWeight: FontWeight.w500,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }).toList(),
                              ),
                            );
                          },
                        ),
                        // Linha 3: Footer - Status + Taxi Dog + Receber
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            // Status pill
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: corStatus.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                agendamento.status.toUpperCase(),
                                style: TextStyle(
                                  color: corStatus,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                            // Taxi Dog badge
                            if (agendamento.tipoEntrega != null) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                decoration: BoxDecoration(
                                  color: (isTaxiDog ? Colors.green : Colors.blue).withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      isTaxiDog ? Icons.local_shipping_rounded : Icons.person_rounded,
                                      size: 11,
                                      color: isTaxiDog ? Colors.green : Colors.blue,
                                    ),
                                    const SizedBox(width: 3),
                                    Text(
                                      agendamento.tipoEntrega!,
                                      style: TextStyle(
                                        color: isTaxiDog ? Colors.green : Colors.blue,
                                        fontSize: 9,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    if (isTaxiDog && agendamento.valorTaxiDog != null && agendamento.valorTaxiDog! > 0) ...[
                                      const SizedBox(width: 3),
                                      Text(
                                        'R\$ ${agendamento.valorTaxiDog!.toStringAsFixed(2)}',
                                        style: TextStyle(
                                          color: Colors.green.withOpacity(0.8),
                                          fontSize: 8,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                            const Spacer(),
                            // Recebido / Receber
                            if (agendamento.recebido == true)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Colors.green.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.check_circle_rounded, size: 11, color: Colors.green.withOpacity(0.8)),
                                    const SizedBox(width: 3),
                                    Text(
                                      'Recebido',
                                      style: TextStyle(
                                        color: Colors.green.withOpacity(0.8),
                                        fontSize: 9,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            else if (agendamento.status != 'Cancelado')
                              InkWell(
                                onTap: () => _marcarComoRecebido(context, agendamento, dataService),
                                borderRadius: BorderRadius.circular(6),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: Colors.green.withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: Colors.green.withOpacity(0.25)),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.payment_rounded, size: 12, color: Colors.green.withOpacity(0.8)),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Receber',
                                        style: TextStyle(
                                          color: Colors.green.withOpacity(0.8),
                                          fontSize: 9,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Botão de ação rápida compacto para o card
  Widget _buildQuickActionButton({
    required IconData icon,
    required Color color,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Icon(icon, color: color, size: 16),
        ),
      ),
    );
  }

  Widget _buildCardAgendamentoCompacto(AgendamentoServico agendamento, DataService dataService) {
    final isVacina = _isAgendamentoVacina(agendamento);
    final corStatus = isVacina ? _getCorVacina() : _getCorStatus(agendamento.status);
    final corFundo = isVacina ? _getCorFundoVacina() : _getCorFundoStatus(agendamento.status);
    
    return GestureDetector(
      onTap: () => _mostrarDetalhesAgendamento(context, agendamento, dataService),
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              corFundo,
              Color.lerp(corFundo, corStatus, 0.3)!,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: corStatus.withOpacity(0.6),
            width: 1.5,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _formatoHora!.format(agendamento.dataAgendamento),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isVacina 
                      ? (agendamento.observacoes ?? 'Vacina') // Para vacinas, usar observações
                      : (agendamento.servico?.nome ?? 'Serviço'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                // Mostrar valor do serviço (compacto)
                if (agendamento.servico != null && agendamento.servico!.preco > 0)
                  Text(
                    'R\$ ${agendamento.servico!.precoTotal.toStringAsFixed(2)}',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.7),
                      fontSize: 8,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                // Mostrar materiais do agendamento e do serviço (compacto - apenas ícone se houver)
                Builder(
                  builder: (context) {
                    final todosMateriaisCompacto = [
                      ...agendamento.materiais,
                      if (agendamento.servico != null) ...agendamento.servico!.materiais,
                    ];
                    if (todosMateriaisCompacto.isEmpty) return const SizedBox.shrink();
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          todosMateriaisCompacto.any((m) => m.isVacina) 
                              ? Icons.vaccines 
                              : Icons.inventory_2,
                          size: 8,
                          color: Colors.white.withOpacity(0.7),
                        ),
                        const SizedBox(width: 2),
                        Text(
                          '${todosMateriaisCompacto.length} mat.',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.7),
                            fontSize: 7,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
            if (agendamento.cliente != null)
              Text(
                agendamento.cliente!.nome,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.8),
                  fontSize: 8,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            // Indicador de tipo de entrega (compacto)
            if (agendamento.tipoEntrega != null)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    agendamento.tipoEntrega == 'Taxi Dog'
                        ? Icons.local_shipping
                        : Icons.person,
                    size: 8,
                    color: agendamento.tipoEntrega == 'Taxi Dog'
                        ? Colors.green
                        : Colors.blue,
                  ),
                  const SizedBox(width: 2),
                  Text(
                    agendamento.tipoEntrega == 'Taxi Dog' ? 'TD' : 'CB',
                    style: TextStyle(
                      color: agendamento.tipoEntrega == 'Taxi Dog'
                          ? Colors.green
                          : Colors.blue,
                      fontSize: 7,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            // Indicador de recebido (compacto)
            if (agendamento.recebido == true)
              const Icon(
                Icons.check_circle,
                size: 8,
                color: Colors.green,
              ),
          ],
        ),
      ),
    );
  }

  Color _getCorAgendamento(AgendamentoServico agendamento) {
    if (_isAgendamentoVacina(agendamento)) {
      return _getCorVacina();
    }
    return _getCorStatus(agendamento.status);
  }

  void _mostrarDetalhesAgendamento(
    BuildContext context,
    AgendamentoServico agendamento,
    DataService dataService,
  ) {
    bool localProcessando = false;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _getCorAgendamento(agendamento).withOpacity(0.3),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                _isAgendamentoVacina(agendamento) ? Icons.vaccines : Icons.event,
                color: _getCorAgendamento(agendamento),
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Detalhes do Agendamento',
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildInfoLinha('Número', agendamento.numero),
              if (agendamento.numeroPedido != null && agendamento.numeroPedido!.isNotEmpty)
                _buildInfoLinha('Número do Serviço', agendamento.numeroPedido!),
              _buildInfoLinha('Serviço', agendamento.servico?.nome ?? 'N/A'),
              if (agendamento.servico != null && agendamento.servico!.preco > 0)
                _buildInfoLinha('Valor', 'R\$ ${agendamento.servico!.precoTotal.toStringAsFixed(2)}'),
              // Materiais do agendamento e do serviço
              Builder(
                builder: (context) {
                  final todosMateriaisDetalhes = [
                    ...agendamento.materiais, // Materiais do agendamento (prioridade)
                    if (agendamento.servico != null) ...agendamento.servico!.materiais, // Materiais do serviço
                  ];
                  if (todosMateriaisDetalhes.isEmpty) return const SizedBox.shrink();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 12),
                      Text(
                        agendamento.materiais.isNotEmpty 
                            ? 'Materiais do Agendamento:'
                            : 'Materiais do Serviço:',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...todosMateriaisDetalhes.map((material) {
                        return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: material.isVacina 
                            ? Colors.green.withOpacity(0.5)
                            : Colors.blue.withOpacity(0.5),
                        width: 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              material.isVacina ? Icons.vaccines : Icons.inventory_2,
                              size: 18,
                              color: material.isVacina ? Colors.green : Colors.blue,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                material.produtoNome,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Quantidade: ${material.quantidade.toStringAsFixed(material.quantidade % 1 == 0 ? 0 : 2)}${material.unidade != null ? ' ${material.unidade}' : ''}',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.8),
                            fontSize: 12,
                          ),
                        ),
                        if (material.precoCusto != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Custo: R\$ ${material.precoCusto!.toStringAsFixed(2)}',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.7),
                              fontSize: 11,
                            ),
                          ),
                        ],
                        if (material.observacao != null && material.observacao!.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Obs: ${material.observacao}',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.7),
                              fontSize: 11,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                        if (material.isVacina && material.dataProximaAplicacao != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Próxima aplicação: ${_formatoData!.format(material.dataProximaAplicacao!)}',
                            style: TextStyle(
                              color: Colors.green.withOpacity(0.9),
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                        }).toList(),
                    ],
                  );
                },
              ),
              _buildInfoLinha('Cliente', agendamento.cliente?.nome ?? agendamento.clienteNome ?? 'N/A'),
              Builder(
                builder: (context) {
                  final telefone = agendamento.clienteTelefone ?? agendamento.cliente?.telefone ?? 'N/A';
                  return _buildInfoLinhaComBotoes(
                    'Telefone',
                    telefone,
                    onWhatsApp: telefone != 'N/A' ? () => _abrirWhatsAppComDados(telefone, agendamento) : null,
                    onCopy: telefone != 'N/A' ? () => _copiarTelefoneClipboard(telefone) : null,
                  );
                },
              ),
              if (agendamento.pet != null || agendamento.petNome != null) ...[
                if (agendamento.pet != null)
                  InkWell(
                    onTap: () {
                      // Fechar diálogo de detalhes
                      Navigator.pop(context);
                      // Navegar para página de detalhes do cliente na aba Pet
                      if (agendamento.cliente != null) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ClienteDetalhesPage(
                              cliente: agendamento.cliente,
                              abaInicial: 3, // Índice 3 = aba Pet
                              petIdParaEditar: agendamento.petId, // ID do pet para editar
                            ),
                          ),
                        );
                      }
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 100,
                            child: Text(
                              'Pet:',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.7),
                                fontSize: 14,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '${agendamento.pet!.nome}${agendamento.pet!.especie != null ? ' (${agendamento.pet!.especie}${agendamento.pet!.raca != null ? ' - ${agendamento.pet!.raca}' : ''})' : ''}${agendamento.pet!.tamanho != null || agendamento.pet!.peso != null ? ' - ${[if (agendamento.pet!.tamanho != null) agendamento.pet!.tamanho, if (agendamento.pet!.peso != null) '${agendamento.pet!.peso!.toStringAsFixed(2)}kg'].join(' • ')}' : ''}',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                          decoration: TextDecoration.underline,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Icon(
                                      Icons.edit,
                                      size: 16,
                                      color: Colors.orange.withOpacity(0.7),
                                    ),
                                  ],
                                ),
                                if (agendamento.pet!.observacoes != null && agendamento.pet!.observacoes!.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    agendamento.pet!.observacoes!,
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.7),
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  _buildInfoLinha('Pet', agendamento.petNome ?? 'N/A'),
              ],
              _buildInfoLinha('Data/Hora', _formatoDataHora!.format(agendamento.dataAgendamento)),
              _buildInfoLinha('Duração', '${agendamento.duracaoMinutos} minutos'),
              _buildInfoLinha('Status', agendamento.status),
              if (agendamento.tipoEntrega != null || (agendamento.endereco != null && agendamento.endereco!.isNotEmpty)) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: (agendamento.tipoEntrega == 'Taxi Dog' || agendamento.tipoEntrega == 'Apenas Busca' || agendamento.tipoEntrega == 'Apenas Entrega')
                        ? Colors.green.withOpacity(0.1)
                        : Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: (agendamento.tipoEntrega == 'Taxi Dog' || agendamento.tipoEntrega == 'Apenas Busca' || agendamento.tipoEntrega == 'Apenas Entrega')
                          ? Colors.green.withOpacity(0.3)
                          : Colors.blue.withOpacity(0.3),
                      width: 1.5,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(
                                (agendamento.tipoEntrega == 'Taxi Dog' || agendamento.tipoEntrega == 'Apenas Busca' || agendamento.tipoEntrega == 'Apenas Entrega')
                                    ? Icons.local_shipping_rounded
                                    : (agendamento.endereco != null ? Icons.location_on_rounded : Icons.person_rounded),
                                color: (agendamento.tipoEntrega == 'Taxi Dog' || agendamento.tipoEntrega == 'Apenas Busca' || agendamento.tipoEntrega == 'Apenas Entrega')
                                    ? Colors.green
                                    : Colors.blue,
                                size: 22,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                agendamento.tipoEntrega != null ? 'DADOS DE ENTREGA' : 'ENDEREÇO INFORMADO',
                                style: TextStyle(
                                  color: (agendamento.tipoEntrega == 'Taxi Dog' || agendamento.tipoEntrega == 'Apenas Busca' || agendamento.tipoEntrega == 'Apenas Entrega')
                                      ? Colors.green
                                      : Colors.blue,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 12,
                                  letterSpacing: 1.2,
                                ),
                              ),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: (agendamento.tipoEntrega == 'Taxi Dog' || agendamento.tipoEntrega == 'Apenas Busca' || agendamento.tipoEntrega == 'Apenas Entrega')
                                  ? Colors.green.withOpacity(0.2)
                                  : Colors.blue.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              agendamento.tipoEntrega ?? 'Dados de Endereço',
                              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (agendamento.tipoEntrega != 'Retirada na Loja' && agendamento.tipoEntrega != 'Cliente busca') ...[
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Builder(
                                builder: (context) {
                                  final enderecoExibicao = agendamento.endereco ?? agendamento.cliente?.endereco;
                                  final numeroExibicao = agendamento.numeroEndereco ?? agendamento.cliente?.numero;
                                  final bairroExibicao = agendamento.bairroEntrega ?? agendamento.cliente?.bairro;
                                  final complementoExibicao = agendamento.complemento ?? agendamento.cliente?.complemento;
                                  final pontoRefExibicao = agendamento.pontoReferencia ?? agendamento.cliente?.pontoReferencia;

                                  return Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      if (enderecoExibicao != null && enderecoExibicao.isNotEmpty) ...[
                                        Text(
                                          '$enderecoExibicao${numeroExibicao != null && numeroExibicao.isNotEmpty ? ', $numeroExibicao' : ''}',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 16,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                      ],
                                      if (bairroExibicao != null && bairroExibicao.isNotEmpty)
                                        Text(
                                          'Bairro: $bairroExibicao',
                                          style: TextStyle(
                                            color: Colors.white.withOpacity(0.9),
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      if (complementoExibicao != null && complementoExibicao.isNotEmpty)
                                        Text(
                                          'Complemento: $complementoExibicao',
                                          style: const TextStyle(color: Colors.white70, fontSize: 13),
                                        ),
                                      if (pontoRefExibicao != null && pontoRefExibicao.isNotEmpty) ...[
                                        const SizedBox(height: 8),
                                        Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: Colors.amber.withOpacity(0.1),
                                            borderRadius: BorderRadius.circular(8),
                                            border: Border.all(color: Colors.amber.withOpacity(0.3)),
                                          ),
                                          child: Row(
                                            children: [
                                              const Icon(Icons.info_outline_rounded, color: Colors.amber, size: 14),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  'REF: $pontoRefExibicao',
                                                  style: const TextStyle(
                                                    color: Colors.amber,
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.bold,
                                                    fontStyle: FontStyle.italic,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ],
                                  );
                                },
                              ),
                            ),
                            if ((agendamento.endereco != null && agendamento.endereco!.isNotEmpty) || (agendamento.cliente?.endereco != null && agendamento.cliente!.endereco!.isNotEmpty)) ...[
                               const SizedBox(width: 12),
                               InkWell(
                                 onTap: () async {
                                   final end = agendamento.endereco ?? agendamento.cliente?.endereco ?? '';
                                   final num = agendamento.numeroEndereco ?? agendamento.cliente?.numero ?? '';
                                   final bai = agendamento.bairroEntrega ?? agendamento.cliente?.bairro ?? '';
                                   final query = Uri.encodeComponent('$end, $num, $bai');
                                   final url = 'https://www.google.com/maps/search/?api=1&query=$query';
                                   if (await canLaunchUrl(Uri.parse(url))) {
                                     await launchUrl(Uri.parse(url));
                                   }
                                 },
                                 child: Container(
                                   padding: const EdgeInsets.all(12),
                                   decoration: BoxDecoration(
                                     color: Colors.white.withOpacity(0.1),
                                     shape: BoxShape.circle,
                                     border: Border.all(color: Colors.white24),
                                   ),
                                   child: const Icon(Icons.map_rounded, color: Colors.white, size: 24),
                                 ),
                               ),
                            ],
                          ],
                        ),
                        if (agendamento.valorTaxiDog != null && agendamento.valorTaxiDog! > 0) ...[
                          const SizedBox(height: 12),
                          const Divider(color: Colors.white12),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Taxa de Entrega:', style: TextStyle(color: Colors.white70, fontSize: 13)),
                              Text(
                                'R\$ ${agendamento.valorTaxiDog!.toStringAsFixed(2)}',
                                style: const TextStyle(color: Colors.greenAccent, fontSize: 14, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
              ],
              if (agendamento.cliente != null && agendamento.cliente!.observacoes != null && agendamento.cliente!.observacoes!.isNotEmpty) ...[
                const SizedBox(height: 12),
                _buildInfoLinha('Observações do Cliente', agendamento.cliente!.observacoes!),
              ],
              if (agendamento.cliente != null && agendamento.cliente!.dadosExtras != null && agendamento.cliente!.dadosExtras!.isNotEmpty) ...[
                const SizedBox(height: 12),
                _buildInfoLinha('Dados Extras do Cliente', agendamento.cliente!.dadosExtras!.entries.map((e) => '${e.key}: ${e.value}').join('\n')),
              ],
              if (agendamento.observacoes != null && agendamento.observacoes!.isNotEmpty) ...[
                const SizedBox(height: 12),
                _buildInfoLinha('Observações do Agendamento', agendamento.observacoes!),
              ],
              // Informação de recebimento
              if (agendamento.recebido == true) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.green.withOpacity(0.5),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle, color: Colors.green, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Recebido',
                              style: TextStyle(
                                color: Colors.green,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            if (agendamento.dataRecebimento != null)
                              Text(
                                'Em ${DateFormat('dd/MM/yyyy HH:mm').format(agendamento.dataRecebimento!)}',
                                style: TextStyle(
                                  color: Colors.white70,
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
            ],
          ),
        ),
        actions: [
          // Botão para marcar como recebido (se ainda não foi recebido)
          if ((agendamento.recebido != true) && agendamento.status != 'Cancelado')
            IconButton(
              icon: const Icon(Icons.payment, color: Colors.green),
              tooltip: 'Marcar como Recebido',
              onPressed: () {
                Navigator.pop(context);
                _marcarComoRecebido(context, agendamento, dataService);
              },
            ),
          // Botão para copiar todos os dados do agendamento
          IconButton(
            icon: const Icon(Icons.copy_all, color: Colors.green),
            tooltip: 'Copiar Dados do Agendamento',
            onPressed: () {
              final texto = _montarTextoAgendamento(agendamento);
              Clipboard.setData(ClipboardData(text: texto));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Dados do agendamento copiados!'),
                  backgroundColor: Colors.green,
                ),
              );
            },
          ),
          // Botão para gerar PDF
          IconButton(
            icon: const Icon(Icons.picture_as_pdf, color: Colors.red),
            tooltip: 'Gerar PDF',
            onPressed: () async {
              try {
                // Buscar cliente atualizado do DataService para garantir que tem todas as informações
                Cliente? clienteAtualizado;
                if (agendamento.clienteId != null) {
                  try {
                    clienteAtualizado = dataService.clientes.firstWhere(
                      (c) => c.id == agendamento.clienteId,
                    );
                  } catch (e) {
                    // Se não encontrar, usar o cliente do agendamento ou null
                    clienteAtualizado = agendamento.cliente;
                  }
                } else {
                  clienteAtualizado = agendamento.cliente;
                }
                
                // Criar agendamento com cliente atualizado
                final agendamentoComClienteAtualizado = agendamento.copyWith(
                  cliente: clienteAtualizado,
                );
                
                // Buscar pedido relacionado ao agendamento
                Pedido? pedidoRelacionado;
                try {
                  debugPrint('>>> [Agenda] Buscando pedido relacionado ao agendamento...');
                  debugPrint('>>> [Agenda] Cliente ID: ${agendamento.clienteId}');
                  debugPrint('>>> [Agenda] Data Agendamento: ${agendamento.dataAgendamento}');
                  
                  // Estratégia 1: Buscar por cliente e data (mais precisa)
                  final pedidosPorClienteEData = dataService.pedidos.where((p) {
                    if (agendamento.clienteId != null && p.clienteId != agendamento.clienteId) {
                      return false;
                    }
                    // Verificar se a data do pedido está próxima da data do agendamento
                    final diferencaDias = (p.dataPedido.difference(agendamento.dataAgendamento).inDays).abs();
                    return diferencaDias <= 1; // Pedido no mesmo dia ou dia seguinte
                  }).toList();
                  
                  debugPrint('>>> [Agenda] Pedidos encontrados por cliente e data: ${pedidosPorClienteEData.length}');
                  
                  // Estratégia 2: Se não encontrou, buscar por cliente apenas (mais ampla)
                  if (pedidosPorClienteEData.isEmpty && agendamento.clienteId != null) {
                    final pedidosPorCliente = dataService.pedidos.where((p) {
                      return p.clienteId == agendamento.clienteId;
                    }).toList();
                    
                    debugPrint('>>> [Agenda] Pedidos encontrados por cliente apenas: ${pedidosPorCliente.length}');
                    
                    // Se houver múltiplos, pegar o mais recente
                    if (pedidosPorCliente.isNotEmpty) {
                      pedidosPorCliente.sort((a, b) => b.dataPedido.compareTo(a.dataPedido));
                      pedidoRelacionado = pedidosPorCliente.first;
                      debugPrint('>>> [Agenda] Pedido selecionado (mais recente): ${pedidoRelacionado.numero}');
                    }
                  } else if (pedidosPorClienteEData.isNotEmpty) {
                    // Se houver múltiplos, pegar o mais recente
                    pedidosPorClienteEData.sort((a, b) => b.dataPedido.compareTo(a.dataPedido));
                    pedidoRelacionado = pedidosPorClienteEData.first;
                    debugPrint('>>> [Agenda] Pedido selecionado (mais recente): ${pedidoRelacionado.numero}');
                  }
                  
                  // Log do pedido encontrado
                  if (pedidoRelacionado != null) {
                    debugPrint('>>> [Agenda] ✅ Pedido encontrado:');
                    debugPrint('>>> [Agenda]   Número: ${pedidoRelacionado.numero}');
                    debugPrint('>>> [Agenda]   Data: ${pedidoRelacionado.dataPedido}');
                    debugPrint('>>> [Agenda]   Observações: "${pedidoRelacionado.observacoes ?? "NULL"}"');
                    debugPrint('>>> [Agenda]   Observações (isEmpty): ${pedidoRelacionado.observacoes?.isEmpty ?? true}');
                  } else {
                    debugPrint('>>> [Agenda] ⚠️ Nenhum pedido relacionado encontrado');
                  }
                } catch (e) {
                  debugPrint('>>> [Agenda] Erro ao buscar pedido: $e');
                }
                
                await AgendamentoPdfService.visualizarPDF(
                  agendamento: agendamentoComClienteAtualizado,
                  pedido: pedidoRelacionado,
                  dataService: dataService, // Passar DataService para buscar cliente atualizado
                );
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Erro ao gerar PDF: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
          ),
          // Botão para editar cliente
          // Agora sempre mostramos se houver informações mínimas (nome ou telefone)
          if (agendamento.cliente != null || agendamento.clienteId != null || agendamento.clienteTelefone != null || agendamento.clienteNome != null)
            IconButton(
              icon: Icon(
                (agendamento.clienteId == 'publico' || agendamento.clienteId == null) 
                    ? Icons.person_add_alt_1 
                    : Icons.edit, 
                color: Colors.blue
              ),
              tooltip: (agendamento.clienteId == 'publico' || agendamento.clienteId == null)
                  ? 'Vincular/Cadastrar Cliente'
                  : 'Editar Cliente',
              onPressed: () => _editarOuVincularCliente(context, agendamento, dataService),
            ),
          // Botão para alterar status
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white70),
            color: const Color(0xFF1E1E2E),
            onSelected: (novoStatus) async {
              try {
                final agendamentoAtualizado = agendamento.copyWith(
                  status: novoStatus,
                  updatedAt: DateTime.now(),
                );
                
                await dataService.updateAgendamentoServico(agendamentoAtualizado);
                
                // Se o status foi alterado para "Concluído", criar pedido no histórico
                if (novoStatus == 'Concluído' && agendamento.status != 'Concluído') {
                  await _criarPedidoDoAgendamento(agendamentoAtualizado, dataService);
                }
                
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Status alterado para: $novoStatus'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Erro ao alterar status: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'Agendado',
                child: Text('Agendado', style: TextStyle(color: Colors.white)),
              ),
              const PopupMenuItem(
                value: 'Em Andamento',
                child: Text('Em Andamento', style: TextStyle(color: Colors.white)),
              ),
              const PopupMenuItem(
                value: 'Concluído',
                child: Text('Concluído', style: TextStyle(color: Colors.white)),
              ),
              const PopupMenuItem(
                value: 'Cancelado',
                child: Text('Cancelado', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
          if (agendamento.status == 'Aguardando Confirmação') ...[
            StatefulBuilder(
              builder: (context, setBtnState) {
                // localProcessando is captured from outside if we define it in the method scope,
                // but for StatefulBuilder it's better to use a local variable that survives rebuilds.
                // Since this is a callback, we can use a closure-captured variable.
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ElevatedButton(
                      onPressed: localProcessando ? null : () async {
                        setBtnState(() => localProcessando = true);
                        try {
                          await dataService.rejeitarAgendamento(agendamento.id);
                          if (context.mounted) Navigator.pop(context);
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Erro ao rejeitar: $e'), backgroundColor: Colors.red),
                            );
                          }
                        } finally {
                          if (context.mounted) setBtnState(() => localProcessando = false);
                        }
                      },
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade900),
                      child: const Text('Rejeitar'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: localProcessando ? null : () async {
                        setBtnState(() => localProcessando = true);
                        try {
                          await dataService.aprovarAgendamento(agendamento.id);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Agendamento aprovado com sucesso!'), backgroundColor: Colors.green),
                            );
                            Navigator.pop(context);
                          }
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Erro ao aprovar: $e'), backgroundColor: Colors.red),
                            );
                          }
                        } finally {
                          if (context.mounted) setBtnState(() => localProcessando = false);
                        }
                      },
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.purple),
                      child: localProcessando 
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Aprovar'),
                    ),
                  ],
                );
              }
            ),
          ],
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fechar', style: TextStyle(color: Colors.white54)),
          ),
          if (agendamento.status == 'Agendado') ...[
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _editarAgendamento(context, agendamento, dataService);
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
              child: const Text('Editar'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _cancelarAgendamento(context, agendamento, dataService);
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Cancelar'),
            ),
          ],
        ],
      ),
    );
  }

  /// Método inteligente para editar ou vincular um cliente a um agendamento
  Future<void> _editarOuVincularCliente(BuildContext context, AgendamentoServico agendamento, DataService dataService) async {
    Navigator.pop(context); // Fechar dialog de detalhes

    Cliente? clienteAlvo;
    bool isPublico = agendamento.clienteId == 'publico' || agendamento.clienteId == null;

    if (!isPublico) {
      // Caso A: Cliente já registrado - Tentar buscar o registro oficial
      try {
        clienteAlvo = dataService.clientes.firstWhere((c) => c.id == agendamento.clienteId);
      } catch (e) {
        clienteAlvo = agendamento.cliente; // Fallback para o objeto no agendamento
      }
    }

    // Se for público ou não encontramos o cliente registrado, vamos buscar pelo telefone
    if (clienteAlvo == null || isPublico) {
      final telefoneBusca = (agendamento.clienteTelefone ?? agendamento.cliente?.telefone ?? '').replaceAll(RegExp(r'\D'), '');
      
      if (telefoneBusca.isNotEmpty) {
        try {
          // Busca exata pelo telefone (removendo caracteres não numéricos)
          final matches = dataService.clientes.where((c) {
            final t = c.telefone.replaceAll(RegExp(r'\D'), '');
            return t.contains(telefoneBusca) || telefoneBusca.contains(t);
          }).toList();

          if (matches.isNotEmpty) {
            final match = matches.first;
            
            // Perguntar se deseja vincular
            final bool? vincular = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                backgroundColor: const Color(0xFF1E1E2E),
                title: const Text('Cliente Encontrado', style: TextStyle(color: Colors.white)),
                content: Text(
                  'Identificamos que o telefone ${agendamento.clienteTelefone} pertence ao cliente cadastrado: ${match.nome}.\n\nDeseja vincular este agendamento ao cadastro dele?',
                  style: const TextStyle(color: Colors.white70),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Não, criar novo', style: TextStyle(color: Colors.white54)),
                  ),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                    child: const Text('Sim, vincular'),
                  ),
                ],
              ),
            );

            if (vincular == true) {
              // Atualizar agendamento no banco
              final agendamentoVinculado = agendamento.copyWith(
                clienteId: match.id,
                cliente: match,
                updatedAt: DateTime.now(),
              );
              await dataService.updateAgendamentoServico(agendamentoVinculado);
              clienteAlvo = match;
            }
          }
        } catch (e) {
          debugPrint('Erro ao buscar cliente por telefone: $e');
        }
      }
    }

    // Se ainda não temos um cliente alvo (e não vinculamos a um existente), criar um pré-preenchido
    if (clienteAlvo == null) {
      clienteAlvo = Cliente(
        id: '', // ID vazio para indicar NOVO cliente no ClienteDetalhesPage
        nome: agendamento.clienteNome ?? agendamento.cliente?.nome ?? '',
        telefone: agendamento.clienteTelefone ?? agendamento.cliente?.telefone ?? '',
        whatsapp: agendamento.clienteTelefone ?? agendamento.cliente?.whatsapp ?? '',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
    }

    // Abrir página de detalhes para editar/cadastrar
    if (context.mounted) {
      final Cliente? resultado = await Navigator.push<Cliente>(
        context,
        MaterialPageRoute(
          builder: (context) => ClienteDetalhesPage(cliente: clienteAlvo),
        ),
      );

      // Se um cliente foi salvo/retornado, e o agendamento era público, vincular agora
      if (resultado != null && isPublico) {
        final agendamentoFinal = agendamento.copyWith(
          clienteId: resultado.id,
          cliente: resultado,
          updatedAt: DateTime.now(),
        );
        await dataService.updateAgendamentoServico(agendamentoFinal);
        
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Agendamento vinculado ao novo cliente!'), backgroundColor: Colors.green),
          );
        }
      }
      
      if (context.mounted) setState(() {});
    }
  }

  Widget _buildInfoLinha(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontSize: 14,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoLinhaComBotoes(String label, String value, {VoidCallback? onWhatsApp, VoidCallback? onCopy}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontSize: 14,
              ),
            ),
          ),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    value,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                if (onWhatsApp != null)
                  IconButton(
                    icon: const Icon(Icons.chat, color: Colors.green, size: 20),
                    onPressed: onWhatsApp,
                    tooltip: 'Conversar no WhatsApp',
                    constraints: const BoxConstraints(),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                if (onCopy != null)
                  IconButton(
                    icon: const Icon(Icons.copy, color: Colors.blue, size: 20),
                    onPressed: onCopy,
                    tooltip: 'Copiar Telefone',
                    constraints: const BoxConstraints(),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Monta o texto formatado com todos os dados do agendamento para envio por WhatsApp
  String _montarTextoAgendamento(AgendamentoServico agendamento) {
    final buffer = StringBuffer();
    
    // Saudação e título
    final nomeCliente = agendamento.cliente?.nome ?? agendamento.clienteNome ?? '';
    buffer.writeln('Olá${nomeCliente.isNotEmpty ? ', *$nomeCliente*' : ''}! 👋');
    buffer.writeln('');
    buffer.writeln('Segue os dados do seu agendamento:');
    buffer.writeln('');
    
    // ── Dados do Agendamento ──
    buffer.writeln('📋 *AGENDAMENTO ${agendamento.numero}*');
    buffer.writeln('');
    
    // Serviço e Valor
    buffer.writeln('✂️ *Serviço:* ${agendamento.servico?.nome ?? 'N/A'}');
    if (agendamento.servico != null && agendamento.servico!.preco > 0) {
      buffer.writeln('💰 *Valor:* R\$ ${agendamento.servico!.precoTotal.toStringAsFixed(2)}');
    }
    if (agendamento.valorTaxiDog != null && agendamento.valorTaxiDog! > 0) {
      buffer.writeln('🚗 *Taxa de Entrega:* R\$ ${agendamento.valorTaxiDog!.toStringAsFixed(2)}');
      if (agendamento.servico != null && agendamento.servico!.preco > 0) {
        final total = agendamento.servico!.precoTotal + agendamento.valorTaxiDog!;
        buffer.writeln('💵 *Total:* R\$ ${total.toStringAsFixed(2)}');
      }
    }
    buffer.writeln('');
    
    // Data e Horário
    final dataFormatada = DateFormat('dd/MM/yyyy', 'pt_BR').format(agendamento.dataAgendamento);
    final horaFormatada = DateFormat('HH:mm').format(agendamento.dataAgendamento);
    final horaTermino = DateFormat('HH:mm').format(agendamento.dataAgendamento.add(Duration(minutes: agendamento.duracaoMinutos)));
    buffer.writeln('📅 *Data:* $dataFormatada');
    buffer.writeln('🕐 *Horário:* $horaFormatada às $horaTermino (${agendamento.duracaoMinutos} min)');
    buffer.writeln('');
    
    // Pet
    if (agendamento.pet != null) {
      final pet = agendamento.pet!;
      buffer.writeln('🐾 *Pet:* ${pet.nome}');
      final detalhes = <String>[];
      if (pet.especie != null) detalhes.add(pet.especie!);
      if (pet.raca != null) detalhes.add(pet.raca!);
      if (pet.tamanho != null) detalhes.add(pet.tamanho!);
      if (pet.peso != null) detalhes.add('${pet.peso!.toStringAsFixed(2)}kg');
      if (detalhes.isNotEmpty) {
        buffer.writeln('   ${detalhes.join(' • ')}');
      }
      if (pet.observacoes != null && pet.observacoes!.isNotEmpty) {
        buffer.writeln('   ⚠️ ${pet.observacoes}');
      }
      buffer.writeln('');
    } else if (agendamento.petNome != null) {
      buffer.writeln('🐾 *Pet:* ${agendamento.petNome}');
      buffer.writeln('');
    }
    
    // Entrega
    if (agendamento.tipoEntrega != null) {
      if (agendamento.tipoEntrega == 'Taxi Dog' || agendamento.tipoEntrega == 'Apenas Busca' || agendamento.tipoEntrega == 'Apenas Entrega') {
        buffer.writeln('🚗 *Entrega:* ${agendamento.tipoEntrega}');
        final enderecoPartes = <String>[];
        if (agendamento.endereco != null && agendamento.endereco!.isNotEmpty) {
          String rua = agendamento.endereco!;
          if (agendamento.numeroEndereco != null && agendamento.numeroEndereco!.isNotEmpty) {
            rua += ', ${agendamento.numeroEndereco}';
          }
          enderecoPartes.add(rua);
        }
        if (agendamento.complemento != null && agendamento.complemento!.isNotEmpty) {
          enderecoPartes.add(agendamento.complemento!);
        }
        if (agendamento.bairroEntrega != null && agendamento.bairroEntrega!.isNotEmpty) {
          enderecoPartes.add(agendamento.bairroEntrega!);
        }
        if (enderecoPartes.isNotEmpty) {
          buffer.writeln('📍 *Endereço:* ${enderecoPartes.join(' - ')}');
        }
        if (agendamento.pontoReferencia != null && agendamento.pontoReferencia!.isNotEmpty) {
          buffer.writeln('🔎 *Referência:* ${agendamento.pontoReferencia}');
        }
      } else {
        buffer.writeln('🏪 *Entrega:* ${agendamento.tipoEntrega}');
      }
      buffer.writeln('');
    }
    
    // Materiais
    if (agendamento.materiais.isNotEmpty) {
      buffer.writeln('💊 *Materiais:*');
      for (final material in agendamento.materiais) {
        final qtd = material.quantidade % 1 == 0
            ? material.quantidade.toInt().toString()
            : material.quantidade.toStringAsFixed(2);
        buffer.writeln('   • ${material.produtoNome} - $qtd${material.unidade != null ? ' ${material.unidade}' : ''}');
      }
      buffer.writeln('');
    }
    
    // Observações
    if (agendamento.observacoes != null && agendamento.observacoes!.isNotEmpty) {
      buffer.writeln('📝 *Obs:* ${agendamento.observacoes}');
      buffer.writeln('');
    }
    
    // Status
    final statusEmoji = {
      'Agendado': '✅',
      'Em Andamento': '🔄',
      'Concluído': '✔️',
      'Cancelado': '❌',
      'Aguardando Confirmação': '⏳',
    };
    buffer.writeln('${statusEmoji[agendamento.status] ?? '📊'} *Status:* ${agendamento.status}');
    
    return buffer.toString().trimRight();
  }

  void _abrirWhatsAppComDados(String telefone, AgendamentoServico agendamento) async {
    // Copiar dados do agendamento para a área de transferência
    final textoAgendamento = _montarTextoAgendamento(agendamento);
    await Clipboard.setData(ClipboardData(text: textoAgendamento));
    
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Dados do agendamento copiados! Cole no WhatsApp.'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 3),
        ),
      );
    }

    final numeroLimpo = telefone.replaceAll(RegExp(r'\D'), '');
    if (numeroLimpo.isEmpty) return;

    // Adicionar código do país se não tiver (padrão Brasil 55)
    String link = "";
    if (numeroLimpo.length <= 11) {
      link = "https://wa.me/55$numeroLimpo";
    } else {
      link = "https://wa.me/$numeroLimpo";
    }

    final uri = Uri.parse(link);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        // Fallback para window.open no web se canLaunchUrl falhar
        if (kIsWeb) {
          html_helper.openWindow(link, 'whatsapp');
        }
      }
    } catch (e) {
      debugPrint('Erro ao abrir WhatsApp: $e');
    }
  }

  void _copiarTelefoneClipboard(String telefone) {
    Clipboard.setData(ClipboardData(text: telefone));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Telefone copiado!'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  void _mostrarDialogNovoAgendamento(BuildContext context, DataService dataService, {DateTime? dataHoraPreSelecionada}) async {
    // Serviço é opcional - permitir agendamento sem serviço
    Servico? servicoSelecionado = null;
    Cliente? clienteSelecionado;
    DateTime dataAgendamento = dataHoraPreSelecionada ?? _dataSelecionada;
    TimeOfDay horaAgendamento = dataHoraPreSelecionada != null 
        ? TimeOfDay.fromDateTime(dataHoraPreSelecionada)
        : TimeOfDay.now();
    int duracaoMinutos = 60;
    final observacoesController = TextEditingController();
    List<String> petsSelecionadosIds = []; // Lista de IDs dos pets selecionados
    String? tipoEntrega; // 'Taxi Dog' ou 'Cliente busca'
    final valorTaxiDogController = TextEditingController();
    final bairroEntregaController = TextEditingController();
    final phoneController = TextEditingController(); // Novo controlador para busca por telefone
    final enderecoController = TextEditingController(); // Novo controlador para endereço
    final numeroEnderecoController = TextEditingController();
    final complementoEnderecoController = TextEditingController();
    final pontoReferenciaController = TextEditingController();
    final List<ItemMaterial> materiaisAgendamento = []; // Materiais/vacinas do agendamento

    await showDialog(
      context: context,
      builder: (dialogContext) {
        bool salvando = false;
        return StatefulBuilder(
          builder: (context, setState) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E2E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.add_circle_outline, color: Colors.blueAccent, size: 24),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text('Novo Agendamento', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Seleção de Serviço
                Row(
                  children: [
                    const Expanded(
                      child: Text('Serviço:', style: TextStyle(color: Colors.white70, fontSize: 14)),
                    ),
                    TextButton.icon(
                      onPressed: () => _mostrarDialogCadastroRapidoServico(context, dataService, (novoServico) {
                        setState(() {
                          servicoSelecionado = novoServico;
                        });
                      }),
                      icon: const Icon(Icons.add_circle, size: 18, color: Colors.blueAccent),
                      label: const Text('Novo Serviço', style: TextStyle(color: Colors.blueAccent, fontSize: 12)),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<Servico?>(
                  value: servicoSelecionado,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.05),
                    hintText: 'Nenhum serviço (opcional)',
                    hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                  ),
                  dropdownColor: const Color(0xFF2C2C3E),
                  style: const TextStyle(color: Colors.white),
                  items: [
                    // Opção "Nenhum serviço"
                    const DropdownMenuItem<Servico?>(
                      value: null,
                      child: Text('Nenhum serviço (opcional)', style: TextStyle(color: Colors.white70, fontStyle: FontStyle.italic)),
                    ),
                    // Lista de serviços
                    ...dataService.servicos.map((s) {
                      return DropdownMenuItem<Servico?>(
                        value: s,
                        child: Text(s.nome),
                      );
                    }),
                  ],
                  onChanged: (value) {
                    setState(() => servicoSelecionado = value);
                  },
                ),
                const SizedBox(height: 16),
                // Seleção por Telefone (Busca Rápida)
                const Text('Buscar Cliente por Telefone:', style: TextStyle(color: Colors.white70, fontSize: 14)),
                const SizedBox(height: 8),
                TextField(
                  controller: phoneController,
                  keyboardType: TextInputType.phone,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: '(00) 00000-0000',
                    hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                    prefixIcon: const Icon(Icons.phone, color: Colors.blueAccent, size: 20),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.05),
                    suffixIcon: IconButton(
                          icon: const Icon(Icons.search, color: Colors.blueAccent),
                          onPressed: () {
                            final termo = phoneController.text.replaceAll(RegExp(r'[^0-9]'), '');
                            if (termo.length >= 8) {
                              Cliente? encontrado;
                              for (final c in dataService.clientes) {
                                final tel = c.telefone.replaceAll(RegExp(r'[^0-9]'), '');
                                final zap = (c.whatsapp ?? '').replaceAll(RegExp(r'[^0-9]'), '');
                                if (tel.contains(termo) || zap.contains(termo)) {
                                  encontrado = c;
                                  break;
                                }
                              }
                              
                                      if (encontrado != null) {
                                        final c = encontrado!;
                                        setState(() {
                                          clienteSelecionado = c;
                                          
                                          // Preencher endereço
                                          enderecoController.text = c.endereco ?? '';
                                          numeroEnderecoController.text = c.numero ?? '';
                                          complementoEnderecoController.text = c.complemento ?? '';
                                          pontoReferenciaController.text = c.pontoReferencia ?? '';
                                          bairroEntregaController.text = c.bairro ?? '';

                                      // Se tiver apenas um pet, seleciona automaticamente
                                  if (c.pets.length == 1) {
                                    petsSelecionadosIds = [c.pets.first.id];
                                  } else {
                                    petsSelecionadosIds = [];
                                  }
                                  
                                  // Preencher observações (reutilizando a lógica do Dropdown)
                                  final value = c;
                                  final observacoesCliente = <String>[];
                                  
                                  // Adicionar endereço do cliente
                                  final enderecoCompleto = <String>[];
                                  if (value!.endereco != null && value.endereco!.isNotEmpty) {
                                    enderecoCompleto.add(value.endereco!);
                                    if (value.numero != null && value.numero!.isNotEmpty) {
                                      enderecoCompleto.add('nº ${value.numero}');
                                    }
                                    if (value.complemento != null && value.complemento!.isNotEmpty) {
                                      enderecoCompleto.add('- ${value.complemento}');
                                    }
                                    if (value.bairro != null && value.bairro!.isNotEmpty) {
                                      enderecoCompleto.add('- ${value.bairro}');
                                    }
                                    if (value.cidade != null && value.cidade!.isNotEmpty) {
                                      enderecoCompleto.add('- ${value.cidade}');
                                    }
                                    if (value.estado != null && value.estado!.isNotEmpty) {
                                      enderecoCompleto.add('/${value.estado}');
                                    }
                                    if (value.cep != null && value.cep!.isNotEmpty) {
                                      enderecoCompleto.add('CEP: ${value.cep}');
                                    }
                                    
                                    if (enderecoCompleto.isNotEmpty) {
                                      observacoesCliente.add('=== ENDEREÇO DO CLIENTE ===');
                                      observacoesCliente.add(enderecoCompleto.join(' '));
                                    }
                                  }
                                  
                                  if (value.observacoes != null && value.observacoes!.isNotEmpty) {
                                    if (observacoesCliente.isNotEmpty) observacoesCliente.add('');
                                    observacoesCliente.add('=== OBSERVAÇÕES DO CLIENTE ===');
                                    observacoesCliente.add(value.observacoes!);
                                  }

                                  if (observacoesCliente.isNotEmpty) {
                                    final textoAtual = observacoesController.text.trim();
                                    if (textoAtual.isNotEmpty) {
                                      observacoesController.text = '$textoAtual\n\n${observacoesCliente.join('\n')}';
                                    } else {
                                      observacoesController.text = observacoesCliente.join('\n');
                                    }
                                  }
                                });
                                
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Cliente ${encontrado.nome} encontrado!'),
                                    backgroundColor: Colors.green,
                                    duration: const Duration(seconds: 2),
                                  ),
                                );
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Nenhum cliente encontrado com este telefone.'),
                                    backgroundColor: Colors.redAccent,
                                  ),
                                );
                              }
                            }
                          },
                        ),
                      ),
                      onChanged: (value) {
                        final termo = value.replaceAll(RegExp(r'[^0-9]'), '');
                        if (termo.length >= 8) {
                          for (final c in dataService.clientes) {
                            final tel = c.telefone.replaceAll(RegExp(r'[^0-9]'), '');
                            final zap = (c.whatsapp ?? '').replaceAll(RegExp(r'[^0-9]'), '');
                            
                            bool match = tel == termo || zap == termo;
                            if (!match && termo.length >= 8) {
                              if (tel.length >= 8 && tel.endsWith(termo.substring(termo.length - 8))) match = true;
                              if (!match && zap.length >= 8 && zap.endsWith(termo.substring(termo.length - 8))) match = true;
                            }

                            if (match) {
                              setState(() {
                                clienteSelecionado = c;
                                
                                // Preencher endereço
                                enderecoController.text = c.endereco ?? '';
                                numeroEnderecoController.text = c.numero ?? '';
                                complementoEnderecoController.text = c.complemento ?? '';
                                pontoReferenciaController.text = c.pontoReferencia ?? '';
                                bairroEntregaController.text = c.bairro ?? '';

                                // Se tiver apenas um pet, seleciona automaticamente
                                if (c.pets.length == 1) {
                                  petsSelecionadosIds = [c.pets.first.id];
                                } else {
                                  petsSelecionadosIds = [];
                                }
                                
                                // Preencher observações do cliente
                                final observacoesCliente = <String>[];
                                final enderecoCompleto = <String>[];
                                if (c.endereco != null && c.endereco!.isNotEmpty) {
                                  enderecoCompleto.add(c.endereco!);
                                  if (c.numero != null && c.numero!.isNotEmpty) enderecoCompleto.add('nº ${c.numero}');
                                  if (c.complemento != null && c.complemento!.isNotEmpty) enderecoCompleto.add('- ${c.complemento}');
                                  if (c.bairro != null && c.bairro!.isNotEmpty) enderecoCompleto.add('- ${c.bairro}');
                                  if (c.cidade != null && c.cidade!.isNotEmpty) enderecoCompleto.add('- ${c.cidade}');
                                  if (c.estado != null && c.estado!.isNotEmpty) enderecoCompleto.add('/${c.estado}');
                                  
                                  if (enderecoCompleto.isNotEmpty) {
                                    observacoesCliente.add('=== ENDEREÇO DO CLIENTE ===');
                                    observacoesCliente.add(enderecoCompleto.join(' '));
                                  }
                                }
                                
                                if (c.observacoes != null && c.observacoes!.isNotEmpty) {
                                  if (observacoesCliente.isNotEmpty) observacoesCliente.add('');
                                  observacoesCliente.add('=== OBSERVAÇÕES DO CLIENTE ===');
                                  observacoesCliente.add(c.observacoes!);
                                }

                                if (observacoesCliente.isNotEmpty) {
                                  final textoAtual = observacoesController.text.trim();
                                  if (!textoAtual.contains('=== ENDEREÇO DO CLIENTE ===')) {
                                    if (textoAtual.isNotEmpty) {
                                      observacoesController.text = '$textoAtual\n\n${observacoesCliente.join('\n')}';
                                    } else {
                                      observacoesController.text = observacoesCliente.join('\n');
                                    }
                                  }
                                }
                              });
                              break;
                            }
                          }
                        }
                      },
                    ),
                const SizedBox(height: 16),
                // Seleção de Cliente
                Row(
                  children: [
                    const Expanded(
                      child: Text('Cliente:', style: TextStyle(color: Colors.white70, fontSize: 14)),
                    ),
                    TextButton.icon(
                      onPressed: () => _mostrarDialogCadastroRapidoCliente(context, dataService, (novoCliente) {
                      setState(() {
                        // Buscar o cliente atualizado do DataService
                        final clienteAtualizado = dataService.clientes.firstWhere(
                          (c) => c.id == novoCliente.id,
                          orElse: () => novoCliente,
                        );
                        clienteSelecionado = clienteAtualizado;
                        // Preencher observações com dados do cliente
                        final observacoesCliente = <String>[];
                            
                            // Adicionar endereço do cliente
                            final enderecoCompleto = <String>[];
                            if (novoCliente.endereco != null && novoCliente.endereco!.isNotEmpty) {
                              enderecoCompleto.add(novoCliente.endereco!);
                              if (novoCliente.numero != null && novoCliente.numero!.isNotEmpty) {
                                enderecoCompleto.add('nº ${novoCliente.numero}');
                              }
                              if (novoCliente.complemento != null && novoCliente.complemento!.isNotEmpty) {
                                enderecoCompleto.add('- ${novoCliente.complemento}');
                              }
                              if (novoCliente.bairro != null && novoCliente.bairro!.isNotEmpty) {
                                enderecoCompleto.add('- ${novoCliente.bairro}');
                              }
                              if (novoCliente.cidade != null && novoCliente.cidade!.isNotEmpty) {
                                enderecoCompleto.add('- ${novoCliente.cidade}');
                              }
                              if (novoCliente.estado != null && novoCliente.estado!.isNotEmpty) {
                                enderecoCompleto.add('/${novoCliente.estado}');
                              }
                              if (novoCliente.cep != null && novoCliente.cep!.isNotEmpty) {
                                enderecoCompleto.add('CEP: ${novoCliente.cep}');
                              }
                              if (novoCliente.pontoReferencia != null && novoCliente.pontoReferencia!.isNotEmpty) {
                                enderecoCompleto.add('Ponto de Referência: ${novoCliente.pontoReferencia}');
                              }
                              
                              if (enderecoCompleto.isNotEmpty) {
                                observacoesCliente.add('=== ENDEREÇO DO CLIENTE ===');
                                observacoesCliente.add(enderecoCompleto.join(' '));
                              }
                            }
                            
                        if (observacoesCliente.isNotEmpty) {
                          final textoAtual = observacoesController.text.trim();
                          if (textoAtual.isNotEmpty) {
                            observacoesController.text = '$textoAtual\n\n${observacoesCliente.join('\n')}';
                          } else {
                            observacoesController.text = observacoesCliente.join('\n');
                          }
                        }
                      });
                    },
                  ),
                      icon: const Icon(Icons.person_add, size: 18, color: Colors.blueAccent),
                      label: const Text('Novo Cliente', style: TextStyle(color: Colors.blueAccent, fontSize: 12)),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<Cliente?>(
                  value: clienteSelecionado,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.05),
                  ),
                  dropdownColor: const Color(0xFF2C2C3E),
                  style: const TextStyle(color: Colors.white),
                  items: [
                    const DropdownMenuItem<Cliente?>(
                      value: null,
                      child: Text('Sem cliente'),
                    ),
                    ...dataService.clientes.map((c) {
                      return DropdownMenuItem(
                        value: c,
                        child: Text(c.nome),
                      );
                    }),
                  ],
                  onChanged: (value) {
                    final v = value;
                    setState(() {
                      clienteSelecionado = v;
                      // Preencher endereço
                      if (v != null) {
                        enderecoController.text = v.endereco ?? '';
                        numeroEnderecoController.text = v.numero ?? '';
                        complementoEnderecoController.text = v.complemento ?? '';
                        pontoReferenciaController.text = v.pontoReferencia ?? '';
                        bairroEntregaController.text = v.bairro ?? '';
                      }

                      // Preencher observações com dados do cliente
                      if (v != null) {
                        final observacoesCliente = <String>[];
                        
                        // Adicionar endereço do cliente
                        final enderecoCompleto = <String>[];
                        if (v.endereco != null && v.endereco!.isNotEmpty) {
                          enderecoCompleto.add(v.endereco!);
                          if (v.numero != null && v.numero!.isNotEmpty) {
                            enderecoCompleto.add('nº ${v.numero}');
                          }
                          if (v.complemento != null && v.complemento!.isNotEmpty) {
                            enderecoCompleto.add('- ${v.complemento}');
                          }
                          if (v.bairro != null && v.bairro!.isNotEmpty) {
                            enderecoCompleto.add('- ${v.bairro}');
                          }
                          if (v.cidade != null && v.cidade!.isNotEmpty) {
                            enderecoCompleto.add('- ${v.cidade}');
                          }
                          if (v.estado != null && v.estado!.isNotEmpty) {
                            enderecoCompleto.add('/${v.estado}');
                          }
                          if (v.cep != null && v.cep!.isNotEmpty) {
                            enderecoCompleto.add('CEP: ${v.cep}');
                          }
                          if (v.pontoReferencia != null && v.pontoReferencia!.isNotEmpty) {
                            enderecoCompleto.add('Ponto de Referência: ${v.pontoReferencia}');
                          }
                          
                          if (enderecoCompleto.isNotEmpty) {
                            observacoesCliente.add('=== ENDEREÇO DO CLIENTE ===');
                            observacoesCliente.add(enderecoCompleto.join(' '));
                          }
                        }
                        
                        // Adicionar observações do cliente
                        if (v.observacoes != null && v.observacoes!.isNotEmpty) {
                          if (observacoesCliente.isNotEmpty) {
                            observacoesCliente.add('');
                          }
                          observacoesCliente.add('=== OBSERVAÇÕES DO CLIENTE ===');
                          observacoesCliente.add(v.observacoes!);
                        }
                        
                        // Adicionar dados extras do cliente
                        if (v.dadosExtras != null && v.dadosExtras!.isNotEmpty) {
                          if (observacoesCliente.isNotEmpty) {
                            observacoesCliente.add('');
                          }
                          observacoesCliente.add('=== DADOS EXTRAS DO CLIENTE ===');
                          v.dadosExtras!.forEach((key, valor) {
                            observacoesCliente.add('$key: $valor');
                          });
                        }
                        
                        // Se já tinha observações, manter e adicionar as do cliente
                        if (observacoesCliente.isNotEmpty) {
                          final textoAtual = observacoesController.text.trim();
                          if (textoAtual.isNotEmpty) {
                            observacoesController.text = '$textoAtual\n\n${observacoesCliente.join('\n')}';
                          } else {
                            observacoesController.text = observacoesCliente.join('\n');
                          }
                        }
                      } else {
                        // Se remover cliente, limpar observações relacionadas
                        final textoAtual = observacoesController.text;
                        // Remover seções de observações do cliente
                        final linhas = textoAtual.split('\n');
                        final linhasFiltradas = <String>[];
                        bool pularSecao = false;
                        
                        for (final linha in linhas) {
                          if (linha.contains('=== ENDEREÇO DO CLIENTE ===') ||
                              linha.contains('=== OBSERVAÇÕES DO CLIENTE ===') || 
                              linha.contains('=== DADOS EXTRAS DO CLIENTE ===')) {
                            pularSecao = true;
                            continue;
                          }
                          if (linha.trim().isEmpty && pularSecao) {
                            pularSecao = false;
                            continue;
                          }
                          if (!pularSecao) {
                            linhasFiltradas.add(linha);
                          }
                        }
                        
                        observacoesController.text = linhasFiltradas.join('\n').trim();
                      }
                    });
                  },
                ),
                const SizedBox(height: 16),
                // Data
                const Text('Data:', style: TextStyle(color: Colors.white70, fontSize: 14)),
                const SizedBox(height: 8),
                InkWell(
                  onTap: () async {
                    final data = await showDatePicker(
                      context: context,
                      initialDate: dataAgendamento,
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (data != null) {
                      setState(() => dataAgendamento = data);
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white.withOpacity(0.3)),
                      borderRadius: BorderRadius.circular(12),
                      color: Colors.white.withOpacity(0.05),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_today, color: Colors.white70, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          _formatoData!.format(dataAgendamento),
                          style: const TextStyle(color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // Hora
                const Text('Hora:', style: TextStyle(color: Colors.white70, fontSize: 14)),
                const SizedBox(height: 8),
                InkWell(
                  onTap: () async {
                    final hora = await _mostrarSeletorHoraComBloqueio(
                      context: context,
                      horaInicial: horaAgendamento,
                      dataAgendamento: dataAgendamento,
                      duracaoMinutos: duracaoMinutos,
                      dataService: dataService,
                    );
                    if (hora != null) {
                      setState(() => horaAgendamento = hora);
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white.withOpacity(0.3)),
                      borderRadius: BorderRadius.circular(12),
                      color: Colors.white.withOpacity(0.05),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.access_time, color: Colors.white70, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          _formatoHora!.format(DateTime(2000, 1, 1, horaAgendamento.hour, horaAgendamento.minute)),
                          style: const TextStyle(color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // Duração
                const Text('Duração (minutos):', style: TextStyle(color: Colors.white70, fontSize: 14)),
                const SizedBox(height: 8),
                Builder(
                  builder: (context) {
                    final duracaoController = TextEditingController(text: duracaoMinutos.toString());
                    return TextField(
                      controller: duracaoController,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.05),
                      ),
                      onChanged: (value) {
                        duracaoMinutos = int.tryParse(value) ?? 60;
                      },
                    );
                  },
                ),
                const SizedBox(height: 16),
                // Endereço (Novo campo solicitado)
                const Text('Endereço (Opcional):', style: TextStyle(color: Colors.white70, fontSize: 14)),
                const SizedBox(height: 8),
                TextField(
                  controller: enderecoController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Rua, Logradouro...',
                    hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                    prefixIcon: const Icon(Icons.location_on, color: Colors.blueAccent, size: 20),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.05),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: numeroEnderecoController,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'Nº',
                          hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          filled: true,
                          fillColor: Colors.white.withOpacity(0.05),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: bairroEntregaController,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'Bairro',
                          hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          filled: true,
                          fillColor: Colors.white.withOpacity(0.05),
                        ),
                      ),
                    ),
                  ],
                ),
                // Seleção de Pets (múltipla)
                if (clienteSelecionado != null) ...[
                  Row(
                    children: [
                      const Expanded(
                        child: Text('Pets:', style: TextStyle(color: Colors.white70, fontSize: 14)),
                      ),
                      if (clienteSelecionado != null && clienteSelecionado!.pets.isNotEmpty)
                        TextButton.icon(
                          onPressed: () {
                            setState(() {
                              if (petsSelecionadosIds.length == clienteSelecionado!.pets.length) {
                                petsSelecionadosIds = [];
                              } else {
                                petsSelecionadosIds = clienteSelecionado!.pets.map((p) => p.id).toList();
                              }
                            });
                          },
                          icon: Icon(
                            petsSelecionadosIds.length == clienteSelecionado!.pets.length
                                ? Icons.deselect
                                : Icons.select_all,
                            size: 16,
                            color: Colors.blueAccent,
                          ),
                          label: Text(
                            petsSelecionadosIds.length == clienteSelecionado!.pets.length
                                ? 'Desmarcar todos'
                                : 'Selecionar todos',
                            style: const TextStyle(color: Colors.blueAccent, fontSize: 11),
                          ),
                        ),
                      TextButton.icon(
                        onPressed: () async {
                          // Buscar cliente atualizado antes de abrir o diálogo
                          final clienteAtual = dataService.clientes.firstWhere(
                            (c) => c.id == clienteSelecionado!.id,
                            orElse: () => clienteSelecionado!,
                          );
                          
                          final clienteRetornado = await _mostrarDialogCadastroRapidoPet(context, dataService, clienteAtual, (novoPet) {
                            // Callback será chamado dentro do método
                          });
                          
                          // Após retornar, atualizar o cliente selecionado e a lista
                          if (clienteRetornado != null && context.mounted) {
                            // Aguardar um pouco para garantir que o DataService foi atualizado
                            await Future.delayed(const Duration(milliseconds: 300));
                            
                            // Buscar cliente atualizado do DataService
                            final clienteAtualizado = dataService.clientes.firstWhere(
                              (c) => c.id == clienteSelecionado!.id,
                              orElse: () => clienteRetornado,
                            );
                            
                            // Usar setState do StatefulBuilder para atualizar o diálogo
                            setState(() {
                              clienteSelecionado = clienteAtualizado;
                              
                              // Se houver novos pets, adicionar o último à seleção
                              if (clienteAtualizado.pets.isNotEmpty) {
                                final ultimoPet = clienteAtualizado.pets.last;
                                if (!petsSelecionadosIds.contains(ultimoPet.id)) {
                                  petsSelecionadosIds.add(ultimoPet.id);
                                }
                              }
                            });
                          }
                        },
                        icon: const Icon(Icons.pets, size: 18, color: Colors.orange),
                        label: const Text('Novo Pet', style: TextStyle(color: Colors.orange, fontSize: 12)),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Buscar cliente atualizado do DataService para ter os pets mais recentes
                  // Usar Consumer para reagir automaticamente às mudanças do DataService
                  Consumer<DataService>(
                    builder: (context, dataServiceConsumer, child) {
                      // Buscar cliente atualizado do DataService
                      final clienteAtualizado = dataServiceConsumer.clientes.firstWhere(
                        (c) => c.id == clienteSelecionado?.id,
                        orElse: () => clienteSelecionado!,
                      );
                      
                      // Atualizar clienteSelecionado se houver mudanças
                      if (clienteSelecionado != null && clienteAtualizado.id == clienteSelecionado!.id) {
                        if (clienteAtualizado.pets.length != clienteSelecionado!.pets.length) {
                          // Atualizar a referência do cliente selecionado
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted) {
                              setState(() {
                                clienteSelecionado = clienteAtualizado;
                              });
                            }
                          });
                        }
                      }
                      
                      if (clienteAtualizado.pets.isEmpty) {
                        return const Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Text(
                            'Nenhum pet cadastrado. Clique em "Novo Pet" para cadastrar.',
                            style: TextStyle(color: Colors.white70, fontSize: 12),
                            textAlign: TextAlign.center,
                          ),
                        );
                      }
                      
                      return Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.white.withOpacity(0.3)),
                          borderRadius: BorderRadius.circular(12),
                          color: Colors.white.withOpacity(0.05),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: clienteAtualizado.pets.map((pet) {
                            final isSelecionado = petsSelecionadosIds.contains(pet.id);
                            return CheckboxListTile(
                              title: Text(
                                pet.nome,
                                style: const TextStyle(color: Colors.white),
                              ),
                              subtitle: pet.especie != null || pet.raca != null
                                  ? Text(
                                      '${pet.especie ?? ''}${pet.especie != null && pet.raca != null ? ' - ' : ''}${pet.raca ?? ''}',
                                      style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12),
                                    )
                                  : null,
                              value: isSelecionado,
                              activeColor: Colors.blueAccent,
                              checkColor: Colors.white,
                              onChanged: (value) {
                                setState(() {
                                  if (value == true) {
                                    if (!petsSelecionadosIds.contains(pet.id)) {
                                      petsSelecionadosIds.add(pet.id);
                                    }
                                  } else {
                                    petsSelecionadosIds.remove(pet.id);
                                  }
                                });
                              },
                            );
                          }).toList(),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                ],
                // Tipo de Entrega — só aparece se o cliente tiver habilitaTaxiDog ativado
                if (clienteSelecionado?.habilitaTaxiDog == true) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.amber.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.amber.withOpacity(0.2)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.local_shipping, color: Colors.amber[300], size: 18),
                            const SizedBox(width: 8),
                            Text(
                              'Entrega / Taxi Dog',
                              style: TextStyle(color: Colors.amber[300], fontSize: 14, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        const Text('Tipo de Entrega:', style: TextStyle(color: Colors.white70, fontSize: 14)),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String?>(
                          value: tipoEntrega,
                          decoration: InputDecoration(
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            filled: true,
                            fillColor: Colors.white.withOpacity(0.05),
                          ),
                          dropdownColor: const Color(0xFF2C2C3E),
                          style: const TextStyle(color: Colors.white),
                          items: const [
                            DropdownMenuItem<String?>(
                              value: null,
                              child: Text('Retirada na Loja'),
                            ),
                            DropdownMenuItem<String>(
                              value: 'Taxi Dog',
                              child: Text('🚗 Taxi Dog (Busca + Entrega)'),
                            ),
                            DropdownMenuItem<String>(
                              value: 'Apenas Busca',
                              child: Text('🔵 Apenas Busca'),
                            ),
                            DropdownMenuItem<String>(
                              value: 'Apenas Entrega',
                              child: Text('🟢 Apenas Entrega'),
                            ),
                            DropdownMenuItem<String>(
                              value: 'Cliente busca',
                              child: Text('🏠 Cliente busca / retira'),
                            ),
                          ],
                          onChanged: (value) {
                            setState(() {
                              tipoEntrega = value;
                              if (value == null) {
                                valorTaxiDogController.clear();
                                bairroEntregaController.clear();
                                enderecoController.clear();
                                numeroEnderecoController.clear();
                                complementoEnderecoController.clear();
                                pontoReferenciaController.clear();
                              }
                              // Preencher endereço do cliente automaticamente se estiver vazio
                              if (value != null && enderecoController.text.isEmpty && clienteSelecionado != null) {
                                enderecoController.text = clienteSelecionado!.endereco ?? '';
                                numeroEnderecoController.text = clienteSelecionado!.numero ?? '';
                                bairroEntregaController.text = clienteSelecionado!.bairro ?? '';
                                complementoEnderecoController.text = clienteSelecionado!.complemento ?? '';
                                pontoReferenciaController.text = clienteSelecionado!.pontoReferencia ?? '';
                              }
                            });
                          },
                        ),
                        // Campos de endereço de entrega
                        if (tipoEntrega == 'Taxi Dog' || tipoEntrega == 'Apenas Busca' || tipoEntrega == 'Apenas Entrega' || tipoEntrega == 'Cliente busca') ...[
                          const SizedBox(height: 16),
                          const Text('Rua / Logradouro:', style: TextStyle(color: Colors.white70, fontSize: 14)),
                          const SizedBox(height: 8),
                          TextField(
                            controller: enderecoController,
                            style: const TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              filled: true,
                              fillColor: Colors.white.withOpacity(0.05),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                flex: 2,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Número:', style: TextStyle(color: Colors.white70, fontSize: 14)),
                                    const SizedBox(height: 8),
                                    TextField(
                                      controller: numeroEnderecoController,
                                      style: const TextStyle(color: Colors.white),
                                      decoration: InputDecoration(
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                        filled: true,
                                        fillColor: Colors.white.withOpacity(0.05),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                flex: 3,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Bairro:', style: TextStyle(color: Colors.white70, fontSize: 14)),
                                    const SizedBox(height: 8),
                                    TextField(
                                      controller: bairroEntregaController,
                                      style: const TextStyle(color: Colors.white),
                                      decoration: InputDecoration(
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                        filled: true,
                                        fillColor: Colors.white.withOpacity(0.05),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          const Text('Complemento:', style: TextStyle(color: Colors.white70, fontSize: 14)),
                          const SizedBox(height: 8),
                          TextField(
                            controller: complementoEnderecoController,
                            style: const TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              filled: true,
                              fillColor: Colors.white.withOpacity(0.05),
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text('Ponto de Referência:', style: TextStyle(color: Colors.white70, fontSize: 14)),
                          const SizedBox(height: 8),
                          TextField(
                            controller: pontoReferenciaController,
                            style: const TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              filled: true,
                              fillColor: Colors.white.withOpacity(0.05),
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text('Valor da Taxa (R\$):', style: TextStyle(color: Colors.white70, fontSize: 14)),
                          const SizedBox(height: 8),
                          TextField(
                            controller: valorTaxiDogController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            style: const TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              filled: true,
                              fillColor: Colors.white.withOpacity(0.05),
                              hintText: '0.00',
                              hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                // Seção de Materiais/Vacinas
                Row(
                  children: [
                    const Icon(Icons.vaccines, color: Colors.green, size: 20),
                    const SizedBox(width: 8),
                    const Text(
                      'Materiais/Vacinas do Agendamento',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (materiaisAgendamento.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white.withOpacity(0.1)),
                    ),
                    child: const Text(
                      'Nenhum material adicionado. Adicione vacinas ou materiais que serão utilizados neste agendamento.',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  )
                else ...[
                  ...materiaisAgendamento.asMap().entries.map((entry) {
                    final index = entry.key;
                    final material = entry.value;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white.withOpacity(0.1)),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            material.isVacina ? Icons.vaccines : Icons.inventory,
                            color: material.isVacina ? Colors.green : Colors.blue,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  material.produtoNome,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Quantidade: ${material.quantidade.toStringAsFixed(2)} ${material.unidade ?? "UN"}',
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                  ),
                                ),
                                if (material.isVacina && material.dataProximaAplicacao != null)
                                  Text(
                                    'Próxima aplicação: ${_formatoData?.format(material.dataProximaAplicacao!) ?? ""}',
                                    style: const TextStyle(
                                      color: Colors.green,
                                      fontSize: 11,
                                    ),
                                  ),
                                if (material.isVacina && material.intervaloDias != null)
                                  Text(
                                    'Intervalo: ${material.intervaloDias} dias',
                                    style: const TextStyle(
                                      color: Colors.green,
                                      fontSize: 11,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                            onPressed: () {
                              setState(() {
                                materiaisAgendamento.removeAt(index);
                              });
                            },
                          ),
                        ],
                      ),
                    );
                  }),
                ],
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: () => _mostrarDialogoAdicionarMaterialAgenda(
                    context,
                    dataService,
                    setState,
                    materiaisAgendamento,
                  ),
                  icon: const Icon(Icons.add),
                  label: const Text('Adicionar Material/Vacina'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                ),
                const SizedBox(height: 16),
                // Observações
                const Text('Observações:', style: TextStyle(color: Colors.white70, fontSize: 14)),
                const SizedBox(height: 8),
                TextField(
                  controller: observacoesController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.05),
                  ),
                  maxLines: 3,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              onPressed: salvando ? null : () async {
                setState(() => salvando = true);
                // Serviço é opcional - não precisa validar

                final dataHoraCompleta = DateTime(
                  dataAgendamento.year,
                  dataAgendamento.month,
                  dataAgendamento.day,
                  horaAgendamento.hour,
                  horaAgendamento.minute,
                );

                // Validação de conflito REMOVIDA - permitir múltiplos agendamentos no mesmo horário
                try {
                  // Processar valor do Taxi Dog
                  double? valorTaxiDog;
                  if (tipoEntrega == 'Taxi Dog' && valorTaxiDogController.text.isNotEmpty) {
                    final valorTexto = valorTaxiDogController.text.replaceAll(',', '.').trim();
                    valorTaxiDog = double.tryParse(valorTexto);
                  }

                  // Se houver pets selecionados, criar um agendamento para cada pet
                  // Se não houver pets selecionados, criar um agendamento sem pet
                  // Buscar cliente atualizado do DataService para ter os pets mais recentes
                  final clienteAtualizado = dataService.clientes.firstWhere(
                    (c) => c.id == clienteSelecionado?.id,
                    orElse: () => clienteSelecionado!,
                  );
                  
                  final petsParaAgendar = petsSelecionadosIds.isEmpty 
                      ? [null] // Criar um agendamento sem pet
                      : clienteAtualizado.pets.where((p) => petsSelecionadosIds.contains(p.id)).toList();

                  int agendamentosCriados = 0;
                  final timestamp = DateTime.now().microsecondsSinceEpoch;
                  for (final pet in petsParaAgendar) {
                    final novoAgendamento = AgendamentoServico(
                      id: '${timestamp}_${pet?.id ?? 'sem_pet'}_$agendamentosCriados',
                      numero: '', // Será gerado automaticamente no addAgendamentoServico
                      servicoId: servicoSelecionado?.id,
                      servico: servicoSelecionado,
                      clienteId: clienteSelecionado?.id,
                      petId: pet?.id,
                      pet: pet,
                      dataAgendamento: dataHoraCompleta,
                      duracaoMinutos: duracaoMinutos,
                      intervaloMinutos: servicoSelecionado?.intervaloMinutos ?? 0,
                      observacoes: observacoesController.text.trim().isEmpty
                          ? null
                          : observacoesController.text.trim(),
                      status: 'Agendado',
                      tipoEntrega: tipoEntrega,
                      valorTaxiDog: valorTaxiDog,
                      bairroEntrega: bairroEntregaController.text.isNotEmpty
                          ? bairroEntregaController.text.trim()
                          : null,
                      endereco: enderecoController.text.isNotEmpty
                          ? enderecoController.text.trim()
                          : null,
                      numeroEndereco: numeroEnderecoController.text.isNotEmpty
                          ? numeroEnderecoController.text.trim()
                          : null,
                      complemento: complementoEnderecoController.text.isNotEmpty
                          ? complementoEnderecoController.text.trim()
                          : null,
                      pontoReferencia: pontoReferenciaController.text.isNotEmpty
                          ? pontoReferenciaController.text.trim()
                          : null,
                      materiais: List.from(materiaisAgendamento), // Copiar lista de materiais
                    );

                    await dataService.addAgendamentoServico(novoAgendamento);

                    // Atualizar endereço no cadastro do cliente se houver mudanças
                    if (clienteSelecionado != null && agendamentosCriados == 0) {
                      final novoEnd = enderecoController.text.trim();
                      final novoNum = numeroEnderecoController.text.trim();
                      final novoBairro = bairroEntregaController.text.trim();
                      
                      if (novoEnd != (clienteSelecionado!.endereco ?? '') || 
                          novoNum != (clienteSelecionado!.numero ?? '') || 
                          novoBairro != (clienteSelecionado!.bairro ?? '')) {
                        final clienteParaAtualizar = clienteSelecionado!.copyWith(
                          endereco: novoEnd.isNotEmpty ? novoEnd : null,
                          numero: novoNum.isNotEmpty ? novoNum : null,
                          bairro: novoBairro.isNotEmpty ? novoBairro : null,
                          updatedAt: DateTime.now(),
                        );
                        await dataService.updateCliente(clienteParaAtualizar);
                      }
                    }

                    agendamentosCriados++;
                    
                    // Criar agendamentos de reaplicação para vacinas
                    // Usar o contexto do dialogContext que está disponível
                    for (final material in materiaisAgendamento) {
                      if (material.isVacina) {
                        // Usar o contexto do dialog para mostrar mensagens
                        await _criarAgendamentoReaplicacaoVacinaComContexto(
                          dialogContext,
                          material,
                          clienteSelecionado,
                          pet,
                          dataService,
                        );
                      }
                    }
                  }
                  
                  if (context.mounted) {
                    Navigator.pop(dialogContext);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(agendamentosCriados > 1
                            ? '$agendamentosCriados agendamentos criados com sucesso!'
                            : 'Agendamento criado com sucesso!'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    final mensagemErro = e.toString().replaceAll('Exception: ', '');
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(mensagemErro),
                        backgroundColor: Colors.red,
                        duration: const Duration(seconds: 6),
                        action: SnackBarAction(
                          label: 'OK',
                          textColor: Colors.white,
                          onPressed: () {},
                        ),
                      ),
                    );
                  }
                } finally {
                  if (context.mounted) {
                    setState(() => salvando = false);
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueAccent,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              child: salvando 
                ? const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      ),
                      SizedBox(width: 12),
                      Text('Aguardando...', style: TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  )
                : const Text('Agendar'),
            ),
          ],
        ),
      );
    },
  );
}

  void _editarAgendamento(BuildContext context, AgendamentoServico agendamento, DataService dataService) {
    final servicos = dataService.servicos;
    final clientes = dataService.clientes;
    
    // Buscar por ID na lista do DataService para garantir mesma referência do dropdown
    Servico? servicoSelecionado;
    if (agendamento.servicoId != null) {
      try {
        servicoSelecionado = servicos.firstWhere((s) => s.id == agendamento.servicoId);
      } catch (_) {
        servicoSelecionado = null; // Não usar referência externa ao dropdown
      }
    } else if (agendamento.servico != null) {
      try {
        servicoSelecionado = servicos.firstWhere((s) => s.id == agendamento.servico!.id);
      } catch (_) {
        servicoSelecionado = null;
      }
    }

    Cliente? clienteSelecionado;
    if (agendamento.clienteId != null && agendamento.clienteId != 'publico') {
      try {
        clienteSelecionado = clientes.firstWhere((c) => c.id == agendamento.clienteId);
      } catch (_) {
        clienteSelecionado = null; // Não usar referência externa ao dropdown
      }
    } else if (agendamento.cliente != null) {
      try {
        clienteSelecionado = clientes.firstWhere((c) => c.id == agendamento.cliente!.id);
      } catch (_) {
        clienteSelecionado = null;
      }
    }
    DateTime dataSelecionada = agendamento.dataAgendamento;
    TimeOfDay horaSelecionada = TimeOfDay.fromDateTime(agendamento.dataAgendamento);
    int duracaoMinutos = agendamento.duracaoMinutos;
    final observacoesController = TextEditingController(text: agendamento.observacoes ?? '');
    List<String> petsSelecionadosIds = agendamento.petId != null ? [agendamento.petId!] : [];
    String? tipoEntrega = agendamento.tipoEntrega;
    final valorTaxiDogController = TextEditingController(
      text: agendamento.valorTaxiDog != null ? agendamento.valorTaxiDog!.toStringAsFixed(2) : '',
    );
    final bairroEntregaController = TextEditingController(text: agendamento.bairroEntrega ?? agendamento.cliente?.bairro ?? '');
    final enderecoController = TextEditingController(text: agendamento.endereco ?? agendamento.cliente?.endereco ?? '');
    final numeroEnderecoController = TextEditingController(text: agendamento.numeroEndereco ?? agendamento.cliente?.numero ?? '');
    final complementoEnderecoController = TextEditingController(text: agendamento.complemento ?? agendamento.cliente?.complemento ?? '');
    final pontoReferenciaController = TextEditingController(text: agendamento.pontoReferencia ?? agendamento.cliente?.pontoReferencia ?? '');
    
    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E2E),
          title: const Text('Editar Agendamento', style: TextStyle(color: Colors.white)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Serviço
                DropdownButtonFormField<Servico?>(
                  value: servicoSelecionado,
                  decoration: const InputDecoration(
                    labelText: 'Serviço (opcional)',
                    labelStyle: TextStyle(color: Colors.white70),
                    border: OutlineInputBorder(),
                    hintText: 'Nenhum serviço',
                  ),
                  dropdownColor: const Color(0xFF1E1E2E),
                  style: const TextStyle(color: Colors.white),
                  items: [
                    // Opção "Nenhum serviço"
                    const DropdownMenuItem<Servico?>(
                      value: null,
                      child: Text('Nenhum serviço (opcional)', style: TextStyle(color: Colors.white70, fontStyle: FontStyle.italic)),
                    ),
                    // Lista de serviços
                    ...servicos.map((s) => DropdownMenuItem<Servico?>(
                      value: s,
                      child: Text(s.nome),
                    )),
                  ],
                  onChanged: (value) {
                    setStateDialog(() {
                      servicoSelecionado = value;
                    });
                  },
                ),
                const SizedBox(height: 16),
                
                // Cliente
                DropdownButtonFormField<Cliente?>(
                  value: clienteSelecionado,
                  decoration: const InputDecoration(
                    labelText: 'Cliente (Opcional)',
                    labelStyle: TextStyle(color: Colors.white70),
                    border: OutlineInputBorder(),
                  ),
                  dropdownColor: const Color(0xFF1E1E2E),
                  style: const TextStyle(color: Colors.white),
                  items: [
                    const DropdownMenuItem<Cliente?>(
                      value: null,
                      child: Text('Sem cliente'),
                    ),
                    ...clientes.map((c) => DropdownMenuItem(
                      value: c,
                      child: Text(c.nome),
                    )),
                  ],
                  onChanged: (value) {
                    setStateDialog(() {
                      clienteSelecionado = value;
                      
                      // Preencher campos de endereço se estiverem vazios
                      if (value != null) {
                        if (enderecoController.text.isEmpty) enderecoController.text = value.endereco ?? '';
                        if (numeroEnderecoController.text.isEmpty) numeroEnderecoController.text = value.numero ?? '';
                        if (bairroEntregaController.text.isEmpty) bairroEntregaController.text = value.bairro ?? '';
                        if (complementoEnderecoController.text.isEmpty) complementoEnderecoController.text = value.complemento ?? '';
                        if (pontoReferenciaController.text.isEmpty) pontoReferenciaController.text = value.pontoReferencia ?? '';
                      }

                      // Atualizar observações com dados do cliente
                      if (clienteSelecionado != null) {
                        String obsCliente = observacoesController.text;
                        if (!obsCliente.contains('=== ENDEREÇO DO CLIENTE ===') && 
                            !obsCliente.contains('=== OBSERVAÇÕES DO CLIENTE ===')) {
                          String novaObs = '';
                          
                          // Adicionar endereço do cliente
                          final enderecoCompleto = <String>[];
                          if (clienteSelecionado!.endereco != null && clienteSelecionado!.endereco!.isNotEmpty) {
                            enderecoCompleto.add(clienteSelecionado!.endereco!);
                            if (clienteSelecionado!.numero != null && clienteSelecionado!.numero!.isNotEmpty) {
                              enderecoCompleto.add('nº ${clienteSelecionado!.numero}');
                            }
                            if (clienteSelecionado!.complemento != null && clienteSelecionado!.complemento!.isNotEmpty) {
                              enderecoCompleto.add('- ${clienteSelecionado!.complemento}');
                            }
                            if (clienteSelecionado!.bairro != null && clienteSelecionado!.bairro!.isNotEmpty) {
                              enderecoCompleto.add('- ${clienteSelecionado!.bairro}');
                            }
                            if (clienteSelecionado!.cidade != null && clienteSelecionado!.cidade!.isNotEmpty) {
                              enderecoCompleto.add('- ${clienteSelecionado!.cidade}');
                            }
                            if (clienteSelecionado!.estado != null && clienteSelecionado!.estado!.isNotEmpty) {
                              enderecoCompleto.add('/${clienteSelecionado!.estado}');
                            }
                            if (clienteSelecionado!.cep != null && clienteSelecionado!.cep!.isNotEmpty) {
                              enderecoCompleto.add('CEP: ${clienteSelecionado!.cep}');
                            }
                            if (clienteSelecionado!.pontoReferencia != null && clienteSelecionado!.pontoReferencia!.isNotEmpty) {
                              enderecoCompleto.add('Ponto de Referência: ${clienteSelecionado!.pontoReferencia}');
                            }
                            
                            if (enderecoCompleto.isNotEmpty) {
                              novaObs += '=== ENDEREÇO DO CLIENTE ===\n${enderecoCompleto.join(' ')}\n';
                            }
                          }
                          
                          if (clienteSelecionado!.observacoes != null && clienteSelecionado!.observacoes!.isNotEmpty) {
                            if (novaObs.isNotEmpty) novaObs += '\n';
                            novaObs += '=== OBSERVAÇÕES DO CLIENTE ===\n${clienteSelecionado!.observacoes}\n';
                          }
                          if (clienteSelecionado!.dadosExtras != null && clienteSelecionado!.dadosExtras!.isNotEmpty) {
                            if (novaObs.isNotEmpty) novaObs += '\n';
                            novaObs += '=== DADOS EXTRAS DO CLIENTE ===\n';
                            clienteSelecionado!.dadosExtras!.forEach((key, val) {
                              novaObs += '$key: $val\n';
                            });
                          }
                          if (novaObs.isNotEmpty) {
                            observacoesController.text = novaObs + (obsCliente.isNotEmpty ? '\n$obsCliente' : '');
                          }
                        }
                      }
                    });
                  },
                ),
                const SizedBox(height: 16),
                
                // Seleção de Pets (múltipla)
                if (clienteSelecionado != null && clienteSelecionado!.pets.isNotEmpty) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Pets:', style: TextStyle(color: Colors.white70, fontSize: 14)),
                      TextButton.icon(
                        onPressed: () {
                          setStateDialog(() {
                            if (petsSelecionadosIds.length == clienteSelecionado!.pets.length) {
                              // Se todos estão selecionados, desmarcar todos
                              petsSelecionadosIds = [];
                            } else {
                              // Selecionar todos
                              petsSelecionadosIds = clienteSelecionado!.pets.map((p) => p.id).toList();
                            }
                          });
                        },
                        icon: Icon(
                          petsSelecionadosIds.length == clienteSelecionado!.pets.length
                              ? Icons.deselect
                              : Icons.select_all,
                          size: 16,
                          color: Colors.blueAccent,
                        ),
                        label: Text(
                          petsSelecionadosIds.length == clienteSelecionado!.pets.length
                              ? 'Desmarcar todos'
                              : 'Selecionar todos',
                          style: const TextStyle(color: Colors.blueAccent, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white.withOpacity(0.3)),
                      borderRadius: BorderRadius.circular(12),
                      color: Colors.white.withOpacity(0.05),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: clienteSelecionado!.pets.map((pet) {
                        final isSelecionado = petsSelecionadosIds.contains(pet.id);
                        return CheckboxListTile(
                          title: Text(
                            pet.nome,
                            style: const TextStyle(color: Colors.white),
                          ),
                          subtitle: pet.especie != null || pet.raca != null
                              ? Text(
                                  '${pet.especie ?? ''}${pet.especie != null && pet.raca != null ? ' - ' : ''}${pet.raca ?? ''}',
                                  style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12),
                                )
                              : null,
                          value: isSelecionado,
                          activeColor: Colors.blueAccent,
                          checkColor: Colors.white,
                          onChanged: (value) {
                            setStateDialog(() {
                              if (value == true) {
                                if (!petsSelecionadosIds.contains(pet.id)) {
                                  petsSelecionadosIds.add(pet.id);
                                }
                              } else {
                                petsSelecionadosIds.remove(pet.id);
                              }
                            });
                          },
                        );
                      }).toList(),
                    ),
                  ),
                  if (petsSelecionadosIds.length > 1)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.orange.withOpacity(0.3)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.info_outline, color: Colors.orange, size: 16),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${petsSelecionadosIds.length} pets selecionados. Será criado um agendamento para cada pet adicional.',
                                style: const TextStyle(color: Colors.orange, fontSize: 11),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
                ],
                // Tipo de Entrega
                const Text('Tipo de Entrega:', style: TextStyle(color: Colors.white70, fontSize: 14)),
                const SizedBox(height: 8),
                DropdownButtonFormField<String?>(
                  value: tipoEntrega,
                  decoration: const InputDecoration(
                    labelText: 'Tipo de Entrega',
                    labelStyle: TextStyle(color: Colors.white70),
                    border: OutlineInputBorder(),
                  ),
                  dropdownColor: const Color(0xFF1E1E2E),
                  style: const TextStyle(color: Colors.white),
                  items: const [
                    DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Não especificado'),
                    ),
                    DropdownMenuItem<String>(
                      value: 'Retirada na Loja',
                      child: Text('Retirada na Loja'),
                    ),
                    DropdownMenuItem<String>(
                      value: 'Taxi Dog',
                      child: Text('Taxi Dog (Leva e Traz)'),
                    ),
                    DropdownMenuItem<String>(
                      value: 'Apenas Busca',
                      child: Text('Apenas Busca'),
                    ),
                    DropdownMenuItem<String>(
                      value: 'Apenas Entrega',
                      child: Text('Apenas Entrega'),
                    ),
                    DropdownMenuItem<String>(
                      value: 'Apenas Busca',
                      child: Text('Apenas Busca'),
                    ),
                    DropdownMenuItem<String>(
                      value: 'Cliente busca',
                      child: Text('Cliente traz e busca'),
                    ),
                  ],
                  onChanged: (value) {
                    setStateDialog(() {
                      tipoEntrega = value;
                      // Se o cliente já informou endereço no cadastro ou no agendamento, manter os dados
                      // mas limpar se for especificamente "Retirada na Loja" e não quisermos ver nada
                      if (value == 'Retirada na Loja') {
                        // Opcional: manter endereço para histórico mas ocultar campos
                      }
                    });
                  },
                ),
                // Campos de endereço para Taxi Dog, Apenas Busca e Apenas Entrega
                if (tipoEntrega == 'Taxi Dog' || tipoEntrega == 'Apenas Busca' || tipoEntrega == 'Apenas Entrega' || tipoEntrega == 'Cliente busca') ...[
                  const SizedBox(height: 16),
                  TextField(
                    controller: enderecoController,
                    decoration: const InputDecoration(
                      labelText: 'Rua / Logradouro',
                      labelStyle: TextStyle(color: Colors.white70),
                      border: OutlineInputBorder(),
                    ),
                    style: const TextStyle(color: Colors.white),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: numeroEnderecoController,
                          decoration: const InputDecoration(
                            labelText: 'Número',
                            labelStyle: TextStyle(color: Colors.white70),
                            border: OutlineInputBorder(),
                          ),
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 3,
                        child: TextField(
                          controller: bairroEntregaController,
                          decoration: const InputDecoration(
                            labelText: 'Bairro',
                            labelStyle: TextStyle(color: Colors.white70),
                            border: OutlineInputBorder(),
                          ),
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: complementoEnderecoController,
                    decoration: const InputDecoration(
                      labelText: 'Complemento',
                      labelStyle: TextStyle(color: Colors.white70),
                      border: OutlineInputBorder(),
                    ),
                    style: const TextStyle(color: Colors.white),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: pontoReferenciaController,
                    decoration: const InputDecoration(
                      labelText: 'Ponto de Referência',
                      labelStyle: TextStyle(color: Colors.white70),
                      border: OutlineInputBorder(),
                    ),
                    style: const TextStyle(color: Colors.white),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: valorTaxiDogController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Valor da Taxa (R\$)',
                      labelStyle: TextStyle(color: Colors.white70),
                      border: OutlineInputBorder(),
                    ),
                    style: const TextStyle(color: Colors.white),
                  ),
                ],
                const SizedBox(height: 16),
                
                // Data
                ListTile(
                  title: const Text('Data', style: TextStyle(color: Colors.white70)),
                  subtitle: Text(
                    _formatoData!.format(dataSelecionada),
                    style: const TextStyle(color: Colors.white),
                  ),
                  trailing: const Icon(Icons.calendar_today, color: Colors.blueAccent),
                  onTap: () async {
                    final data = await showDatePicker(
                      context: dialogContext,
                      initialDate: dataSelecionada,
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (data != null) {
                      setStateDialog(() {
                        dataSelecionada = DateTime(
                          data.year,
                          data.month,
                          data.day,
                          horaSelecionada.hour,
                          horaSelecionada.minute,
                        );
                      });
                    }
                  },
                ),
                
                // Hora
                ListTile(
                  title: const Text('Hora', style: TextStyle(color: Colors.white70)),
                  subtitle: Text(
                    _formatoHora!.format(DateTime(2000, 1, 1, horaSelecionada.hour, horaSelecionada.minute)),
                    style: const TextStyle(color: Colors.white),
                  ),
                  trailing: const Icon(Icons.access_time, color: Colors.blueAccent),
                  onTap: () async {
                    final hora = await _mostrarSeletorHoraComBloqueio(
                      context: dialogContext,
                      horaInicial: horaSelecionada,
                      dataAgendamento: dataSelecionada,
                      duracaoMinutos: duracaoMinutos,
                      dataService: dataService,
                      excluirAgendamentoId: agendamento.id,
                    );
                    if (hora != null) {
                      setStateDialog(() {
                        horaSelecionada = hora;
                        dataSelecionada = DateTime(
                          dataSelecionada.year,
                          dataSelecionada.month,
                          dataSelecionada.day,
                          hora.hour,
                          hora.minute,
                        );
                      });
                    }
                  },
                ),
                
                // Duração
                TextField(
                  controller: TextEditingController(text: duracaoMinutos.toString()),
                  decoration: const InputDecoration(
                    labelText: 'Duração (minutos)',
                    labelStyle: TextStyle(color: Colors.white70),
                    border: OutlineInputBorder(),
                  ),
                  style: const TextStyle(color: Colors.white),
                  keyboardType: TextInputType.number,
                  onChanged: (value) {
                    setStateDialog(() {
                      duracaoMinutos = int.tryParse(value) ?? 60;
                    });
                  },
                ),
                const SizedBox(height: 16),
                
                // Observações
                TextField(
                  controller: observacoesController,
                  decoration: const InputDecoration(
                    labelText: 'Observações',
                    labelStyle: TextStyle(color: Colors.white70),
                    border: OutlineInputBorder(),
                  ),
                  style: const TextStyle(color: Colors.white),
                  maxLines: 4,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              onPressed: () async {
                
                final dataHoraCompleta = DateTime(
                  dataSelecionada.year,
                  dataSelecionada.month,
                  dataSelecionada.day,
                  horaSelecionada.hour,
                  horaSelecionada.minute,
                );
                
                // Validação de conflito REMOVIDA - permitir múltiplos agendamentos no mesmo horário
                try {
                  // Processar valor da taxa de entrega
                  double? valorTaxiDog;
                  if ((tipoEntrega == 'Taxi Dog' || tipoEntrega == 'Apenas Busca' || tipoEntrega == 'Apenas Entrega') && valorTaxiDogController.text.isNotEmpty) {
                    final valorTexto = valorTaxiDogController.text.replaceAll(',', '.').trim();
                    valorTaxiDog = double.tryParse(valorTexto);
                  }

                  // Obter pets selecionados
                  List<Pet> petsParaAgendar = [];
                  if (petsSelecionadosIds.isNotEmpty && clienteSelecionado != null) {
                    petsParaAgendar = clienteSelecionado!.pets
                        .where((p) => petsSelecionadosIds.contains(p.id))
                        .toList();
                  }

                  // Primeiro pet (ou null) atualiza o agendamento existente
                  final primeiroPet = petsParaAgendar.isNotEmpty ? petsParaAgendar.first : null;

                  await dataService.updateAgendamentoServico(
                    agendamento.copyWith(
                      servicoId: servicoSelecionado?.id,
                      servico: servicoSelecionado,
                      clienteId: clienteSelecionado?.id,
                      petId: primeiroPet?.id,
                      pet: primeiroPet,
                      dataAgendamento: dataHoraCompleta,
                      duracaoMinutos: duracaoMinutos,
                      intervaloMinutos: servicoSelecionado?.intervaloMinutos ?? 0,
                      observacoes: observacoesController.text.trim().isEmpty
                          ? null
                          : observacoesController.text.trim(),
                      tipoEntrega: tipoEntrega,
                      valorTaxiDog: valorTaxiDog,
                      bairroEntrega: bairroEntregaController.text.isNotEmpty ? bairroEntregaController.text.trim() : null,
                      endereco: enderecoController.text.isNotEmpty ? enderecoController.text.trim() : null,
                      numeroEndereco: numeroEnderecoController.text.isNotEmpty ? numeroEnderecoController.text.trim() : null,
                      complemento: complementoEnderecoController.text.isNotEmpty ? complementoEnderecoController.text.trim() : null,
                      pontoReferencia: pontoReferenciaController.text.isNotEmpty ? pontoReferenciaController.text.trim() : null,
                      updatedAt: DateTime.now(),
                    ),
                  );

                  // Para cada pet adicional, criar novo agendamento
                  int agendamentosCriados = 0;
                  if (petsParaAgendar.length > 1) {
                    final timestamp = DateTime.now().microsecondsSinceEpoch;
                    for (int i = 1; i < petsParaAgendar.length; i++) {
                      final petExtra = petsParaAgendar[i];
                      final novoAgendamento = AgendamentoServico(
                        id: '${timestamp}_${petExtra.id}_$i',
                        numero: '', // Será gerado automaticamente
                        servicoId: servicoSelecionado?.id,
                        servico: servicoSelecionado,
                        clienteId: clienteSelecionado?.id,
                        petId: petExtra.id,
                        pet: petExtra,
                        dataAgendamento: dataHoraCompleta,
                        duracaoMinutos: duracaoMinutos,
                        intervaloMinutos: servicoSelecionado?.intervaloMinutos ?? 0,
                        observacoes: observacoesController.text.trim().isEmpty
                            ? null
                            : observacoesController.text.trim(),
                        status: agendamento.status,
                        tipoEntrega: tipoEntrega,
                        valorTaxiDog: valorTaxiDog,
                        bairroEntrega: bairroEntregaController.text.isNotEmpty ? bairroEntregaController.text.trim() : null,
                        endereco: enderecoController.text.isNotEmpty ? enderecoController.text.trim() : null,
                        numeroEndereco: numeroEnderecoController.text.isNotEmpty ? numeroEnderecoController.text.trim() : null,
                        complemento: complementoEnderecoController.text.isNotEmpty ? complementoEnderecoController.text.trim() : null,
                        pontoReferencia: pontoReferenciaController.text.isNotEmpty ? pontoReferenciaController.text.trim() : null,
                      );
                      await dataService.addAgendamentoServico(novoAgendamento);
                      agendamentosCriados++;
                    }
                  }
                  
                  if (dialogContext.mounted) {
                    Navigator.pop(dialogContext);
                    final mensagem = agendamentosCriados > 0
                        ? 'Agendamento atualizado + $agendamentosCriados novo(s) criado(s)!'
                        : 'Agendamento atualizado com sucesso!';
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(mensagem),
                        backgroundColor: Colors.green,
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  }
                } catch (e) {
                  if (dialogContext.mounted) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      SnackBar(
                        content: Text('Erro: ${e.toString()}'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
  }

  void _cancelarAgendamento(BuildContext context, AgendamentoServico agendamento, DataService dataService) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: const Text('Cancelar Agendamento', style: TextStyle(color: Colors.white)),
        content: const Text('Tem certeza que deseja cancelar este agendamento?', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Não', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () {
              dataService.updateAgendamentoServico(
                agendamento.copyWith(status: 'Cancelado'),
              );
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Agendamento cancelado'),
                  backgroundColor: Colors.green,
                ),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Sim, Cancelar'),
          ),
        ],
      ),
    );
  }

  /// Mostra seletor de hora com bloqueio de horários ocupados
  Future<TimeOfDay?> _mostrarSeletorHoraComBloqueio({
    required BuildContext context,
    required TimeOfDay horaInicial,
    required DateTime dataAgendamento,
    required int duracaoMinutos,
    required DataService dataService,
    String? excluirAgendamentoId, // Para edição, excluir o próprio agendamento
  }) async {
    // Bloqueio de horários REMOVIDO - permitir múltiplos agendamentos no mesmo horário
    // A duração do serviço é mantida apenas para informação, sem bloquear outros agendamentos
    
    // Mostrar seletor de hora em formato 24 horas (horário de Brasília)
    // FORÇAR formato 24 horas - sem AM/PM (13:00 = 1 hora da tarde)
    final horaSelecionada = await showTimePicker(
      context: context,
      initialTime: horaInicial,
      builder: (BuildContext context, Widget? child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            alwaysUse24HourFormat: true, // FORÇAR formato 24 horas
          ),
          child: Theme(
            data: Theme.of(context).copyWith(
              colorScheme: const ColorScheme.dark(
                primary: Colors.blueAccent,
                onPrimary: Colors.white,
                surface: Color(0xFF1E1E2E),
                onSurface: Colors.white,
              ),
            ),
            child: child!,
          ),
        );
      },
    );
    
    if (horaSelecionada == null) return null;
    
    // Validação de conflito REMOVIDA - permitir qualquer horário
    // A duração do serviço é mantida apenas para informação, sem bloquear outros agendamentos
    
    return horaSelecionada;
  }

  /// Marca agendamento como recebido
  void _marcarComoRecebido(
    BuildContext context,
    AgendamentoServico agendamento,
    DataService dataService,
  ) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.payment, color: Colors.green),
            SizedBox(width: 12),
            Text('Marcar como Recebido', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: const Text(
          'Deseja marcar este agendamento como recebido?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () {
              try {
                final agendamentoAtualizado = agendamento.copyWith(
                  recebido: true,
                  dataRecebimento: DateTime.now(),
                );
                
                dataService.updateAgendamentoServico(agendamentoAtualizado);
                
                Navigator.pop(dialogContext);
                
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Agendamento marcado como recebido!'),
                    backgroundColor: Colors.green,
                  ),
                );
              } catch (e) {
                Navigator.pop(dialogContext);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Erro ao marcar como recebido: $e'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
  }

  /// Mostra diálogo para cadastro rápido de serviço
  Future<void> _mostrarDialogCadastroRapidoServico(
    BuildContext context,
    DataService dataService,
    Function(Servico) onServicoCriado,
  ) async {
    final nomeController = TextEditingController();
    final descricaoController = TextEditingController();
    final precoController = TextEditingController();
    final List<ItemMaterial> materiaisSelecionados = [];

    await showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E2E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.build, color: Colors.blueAccent),
              SizedBox(width: 12),
              Text('Cadastro Rápido - Serviço', style: TextStyle(color: Colors.white)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Nome do Serviço *:', style: TextStyle(color: Colors.white70, fontSize: 14)),
                const SizedBox(height: 8),
                TextField(
                  controller: nomeController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.05),
                    hintText: 'Nome do serviço',
                    hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                  ),
                  autofocus: true,
                ),
                const SizedBox(height: 16),
                const Text('Descrição:', style: TextStyle(color: Colors.white70, fontSize: 14)),
                const SizedBox(height: 8),
                TextField(
                  controller: descricaoController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.05),
                    hintText: 'Descrição do serviço',
                    hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 16),
                const Text('Preço (R\$):', style: TextStyle(color: Colors.white70, fontSize: 14)),
                const SizedBox(height: 8),
                TextField(
                  controller: precoController,
                  style: const TextStyle(color: Colors.white),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.05),
                    hintText: '0.00',
                    hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                  ),
                ),
                const SizedBox(height: 24),
                // Seção de Materiais
                Row(
                  children: [
                    const Icon(Icons.inventory, color: Colors.blueAccent, size: 20),
                    const SizedBox(width: 8),
                    const Text(
                      'Materiais do Serviço',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (materiaisSelecionados.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white.withOpacity(0.1)),
                    ),
                    child: const Text(
                      'Nenhum material cadastrado. Adicione materiais que serão consumidos ao executar este serviço.',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  )
                else ...[
                  ...materiaisSelecionados.asMap().entries.map((entry) {
                    final index = entry.key;
                    final material = entry.value;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white.withOpacity(0.1)),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            material.isVacina ? Icons.vaccines : Icons.inventory,
                            color: material.isVacina ? Colors.green : Colors.blue,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  material.produtoNome,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Quantidade: ${material.quantidade.toStringAsFixed(2)} ${material.unidade ?? "UN"}',
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                  ),
                                ),
                                if (material.isVacina && material.dataProximaAplicacao != null)
                                  Text(
                                    'Próxima aplicação: ${_formatoData?.format(material.dataProximaAplicacao!) ?? ""}',
                                    style: const TextStyle(
                                      color: Colors.green,
                                      fontSize: 11,
                                    ),
                                  ),
                                if (material.isVacina && material.intervaloDias != null)
                                  Text(
                                    'Intervalo: ${material.intervaloDias} dias',
                                    style: const TextStyle(
                                      color: Colors.green,
                                      fontSize: 11,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                            onPressed: () {
                              setState(() {
                                materiaisSelecionados.removeAt(index);
                              });
                            },
                          ),
                        ],
                      ),
                    );
                  }),
                ],
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: () => _mostrarDialogoAdicionarMaterialAgenda(
                    context,
                    dataService,
                    setState,
                    materiaisSelecionados,
                  ),
                  icon: const Icon(Icons.add),
                  label: const Text('Adicionar Material'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              onPressed: () async {
                if (nomeController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Nome do serviço é obrigatório'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }

                try {
                  final precoTexto = precoController.text.replaceAll(',', '.').trim();
                  final preco = double.tryParse(precoTexto) ?? 0.0;

                  final novoServico = Servico(
                    id: DateTime.now().millisecondsSinceEpoch.toString(),
                    nome: nomeController.text.trim(),
                    descricao: descricaoController.text.trim().isNotEmpty
                        ? descricaoController.text.trim()
                        : null,
                    preco: preco,
                    materiais: List.from(materiaisSelecionados),
                    createdAt: DateTime.now(),
                    updatedAt: DateTime.now(),
                  );

                  await dataService.addServico(novoServico);
                  
                  if (context.mounted) {
                    Navigator.pop(dialogContext);
                    onServicoCriado(novoServico);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Serviço cadastrado com sucesso${materiaisSelecionados.isNotEmpty ? ' com ${materiaisSelecionados.length} material(is)' : ''}!',
                        ),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Erro ao cadastrar serviço: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
              child: const Text('Cadastrar'),
            ),
          ],
        ),
      ),
    );
  }

  /// Diálogo para adicionar material ao serviço na agenda
  void _mostrarDialogoAdicionarMaterialAgenda(
    BuildContext context,
    DataService dataService,
    StateSetter setStateDialogo,
    List<ItemMaterial> materiaisSelecionados,
  ) {
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
              backgroundColor: const Color(0xFF1E1E2E),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: const Row(
                children: [
                  Icon(Icons.inventory, color: Colors.blueAccent),
                  SizedBox(width: 12),
                  Text('Adicionar Material', style: TextStyle(color: Colors.white)),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<Produto>(
                            decoration: InputDecoration(
                              labelText: 'Produto/Material *',
                              labelStyle: const TextStyle(color: Colors.white70),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              filled: true,
                              fillColor: Colors.white.withOpacity(0.05),
                            ),
                            dropdownColor: const Color(0xFF1E1E2E),
                            style: const TextStyle(color: Colors.white),
                            items: produtos.map((produto) {
                              return DropdownMenuItem<Produto>(
                                value: produto,
                                child: Text(
                                  '${produto.nome} (Estoque: ${produto.estoque})',
                                  style: const TextStyle(color: Colors.white),
                                ),
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
                          icon: const Icon(Icons.add_circle_outline, color: Colors.blueAccent),
                          tooltip: 'Cadastrar Novo Produto',
                          onPressed: () => _mostrarDialogoCadastroRapidoProdutoAgenda(
                            context,
                            dataService,
                            setState,
                            (novoProduto) {
                              setState(() {
                                produtoSelecionado = novoProduto;
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: quantidadeController,
                      style: const TextStyle(color: Colors.white),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: 'Quantidade *',
                        labelStyle: const TextStyle(color: Colors.white70),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.05),
                        helperText: 'Quantidade a ser consumida (permite decimais)',
                        helperStyle: const TextStyle(color: Colors.white54),
                      ),
                    ),
                    if (produtoSelecionado != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Estoque atual: ${produtoSelecionado!.estoque} ${produtoSelecionado!.unidade}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.blue,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    TextField(
                      controller: observacaoController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'Observação (opcional)',
                        labelStyle: const TextStyle(color: Colors.white70),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.05),
                      ),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 16),
                    // Opções para vacinas
                    CheckboxListTile(
                      title: const Text(
                        'É uma vacina (requer agendamento)',
                        style: TextStyle(color: Colors.white),
                      ),
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
                      activeColor: Colors.green,
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
                          decoration: InputDecoration(
                            labelText: 'Data da Próxima Aplicação (opcional se informar intervalo)',
                            labelStyle: const TextStyle(color: Colors.white70),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            filled: true,
                            fillColor: Colors.white.withOpacity(0.05),
                            suffixIcon: const Icon(Icons.calendar_today, color: Colors.white70),
                            helperText: 'Deixe em branco se usar apenas o intervalo de dias',
                            helperStyle: const TextStyle(color: Colors.white54),
                          ),
                          child: Text(
                            dataProximaAplicacao != null
                                ? _formatoData?.format(dataProximaAplicacao!) ?? 'Selecionar data'
                                : 'Selecionar data (opcional)',
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: intervaloDiasController,
                        style: const TextStyle(color: Colors.white),
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'Intervalo entre doses (dias) *',
                          labelStyle: const TextStyle(color: Colors.white70),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          filled: true,
                          fillColor: Colors.white.withOpacity(0.05),
                          helperText: 'Ex: 1 para amanhã, 21 para 3 semanas. Obrigatório se não informar data',
                          helperStyle: const TextStyle(color: Colors.white54),
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
                    intervaloDiasController.dispose();
                    Navigator.pop(context);
                  },
                  child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
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

                    setStateDialogo(() {
                      materiaisSelecionados.add(ItemMaterial(
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
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
                  child: const Text('Adicionar'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// Diálogo para cadastro rápido de produto na agenda
  Future<void> _mostrarDialogoCadastroRapidoProdutoAgenda(
    BuildContext context,
    DataService dataService,
    StateSetter setStateDialogo,
    Function(Produto) onProdutoCriado,
  ) async {
    final nomeController = TextEditingController();
    final precoCustoController = TextEditingController();
    final estoqueController = TextEditingController(text: '0');
    final unidadeController = TextEditingController(text: 'UN');
    final grupoController = TextEditingController();

    final novoProduto = await showDialog<Produto>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E1E2E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.add_circle, color: Colors.blueAccent),
              SizedBox(width: 12),
              Text('Cadastrar Novo Produto', style: TextStyle(color: Colors.white)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: nomeController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Nome do Produto *',
                    labelStyle: const TextStyle(color: Colors.white70),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.05),
                  ),
                  autofocus: true,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: precoCustoController,
                  style: const TextStyle(color: Colors.white),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Preço de Custo (R\$) *',
                    labelStyle: const TextStyle(color: Colors.white70),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.05),
                    prefixText: 'R\$ ',
                    prefixStyle: const TextStyle(color: Colors.white),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: estoqueController,
                        style: const TextStyle(color: Colors.white),
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'Estoque Inicial',
                          labelStyle: const TextStyle(color: Colors.white70),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          filled: true,
                          fillColor: Colors.white.withOpacity(0.05),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: unidadeController,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: 'Unidade',
                          labelStyle: const TextStyle(color: Colors.white70),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          filled: true,
                          fillColor: Colors.white.withOpacity(0.05),
                          hintText: 'UN',
                          hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: grupoController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Grupo/Categoria (opcional)',
                    labelStyle: const TextStyle(color: Colors.white70),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.05),
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
              child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
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
                    .map((p) => p.codigo ?? '')
                    .where((c) => c.isNotEmpty)
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
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
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

  /// Cria agendamento de reaplicação para vacina (versão com contexto)
  Future<void> _criarAgendamentoReaplicacaoVacinaComContexto(
    BuildContext context,
    ItemMaterial vacina,
    Cliente? cliente,
    Pet? pet,
    DataService dataService,
  ) async {
    if (!vacina.isVacina) {
      return;
    }

    // Calcular data da próxima aplicação
    DateTime? dataProximaAplicacao = vacina.dataProximaAplicacao;
    
    // Se não há data definida mas há intervalo de dias, calcular automaticamente
    if (dataProximaAplicacao == null && vacina.intervaloDias != null && vacina.intervaloDias! > 0) {
      final diasAdicionar = vacina.intervaloDias!;
      dataProximaAplicacao = DateTime.now().add(Duration(days: diasAdicionar));
    }
    
    if (dataProximaAplicacao == null) {
      return; // Sem data de próxima aplicação, não criar agendamento
    }

    try {
      // Para vacinas, não usamos serviço - apenas os dados da vacina nas observações
      final servicoVacinaId = 'vacina_${vacina.produtoId}_${DateTime.now().millisecondsSinceEpoch}';

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

      // Criar descrição da vacina para usar nas observações
      final descricaoVacina = vacina.intervaloDias != null 
          ? 'Aplicar ${vacina.produtoNome} (intervalo: ${vacina.intervaloDias} dia(s))'
          : 'Aplicar ${vacina.produtoNome}';

      final agendamento = AgendamentoServico(
        id: 'vacina_${vacina.produtoId}_${DateTime.now().microsecondsSinceEpoch}',
        numero: '', // Será gerado automaticamente
        servicoId: servicoVacinaId,
        clienteId: cliente?.id,
        cliente: cliente,
        petId: pet?.id,
        pet: pet,
        dataAgendamento: dataAgendamentoComHora,
        duracaoMinutos: 30, // 30 minutos padrão para vacinação
        observacoes: descricaoVacina,
        status: 'Agendado',
        materiais: [vacina], // Incluir a vacina nos materiais do agendamento
      );

      await dataService.addAgendamentoServico(agendamento);
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Agendamento criado para próxima dose de ${vacina.produtoNome} em ${_formatoData?.format(dataProximaAplicacao) ?? ""}'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      debugPrint('>>> Erro ao criar agendamento de reaplicação de vacina: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao criar agendamento de reaplicação: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Cria um pedido no histórico quando um agendamento é concluído
  Future<void> _criarPedidoDoAgendamento(
    AgendamentoServico agendamento,
    DataService dataService,
  ) async {
    try {
      // Coletar todos os materiais do agendamento e do serviço
      final todosMateriais = [
        ...agendamento.materiais,
        if (agendamento.servico != null) ...agendamento.servico!.materiais,
      ];

      // Criar ItemServico a partir do agendamento
      final servicoNome = agendamento.servico?.nome ?? 
          (agendamento.observacoes ?? 'Serviço do Agendamento');
      final servicoValor = agendamento.servico?.preco ?? 0.0;
      
      final itemServico = ItemServico(
        id: uuid.v4(),
        descricao: servicoNome,
        valor: servicoValor,
        valorAdicional: agendamento.valorTaxiDog ?? 0.0,
        descricaoAdicional: agendamento.tipoEntrega == 'Taxi Dog' 
            ? 'Taxi Dog${agendamento.bairroEntrega != null ? ' - ${agendamento.bairroEntrega}' : ''}'
            : null,
        dataAgendamento: agendamento.dataAgendamento,
        duracaoMinutos: agendamento.duracaoMinutos,
        materiais: todosMateriais,
        tipoEntrega: agendamento.tipoEntrega,
        valorTaxiDog: agendamento.valorTaxiDog,
        bairroEntrega: agendamento.bairroEntrega,
      );

      // Gerar número do pedido (usar SRV- para serviços)
      final numeroPedido = dataService.getProximoNumeroServico();

      // Criar pedido
      final pedido = Pedido(
        id: uuid.v4(),
        numero: numeroPedido,
        clienteId: agendamento.clienteId,
        clienteNome: agendamento.cliente?.nome,
        clienteTelefone: agendamento.cliente?.telefone,
        clienteEndereco: agendamento.cliente?.endereco,
        clienteCpfCnpj: agendamento.cliente?.cpfCnpj,
        dataPedido: agendamento.dataAgendamento,
        status: 'Concluído',
        produtos: [],
        servicos: [itemServico],
        materiaisConsumidos: todosMateriais,
        observacoes: 'Agendamento ${agendamento.numero}${agendamento.observacoes != null ? ' - ${agendamento.observacoes}' : ''}',
      );

      await dataService.addPedido(pedido);
      
      // Atualizar agendamento com o número do pedido
      await dataService.updateAgendamentoServico(
        agendamento.copyWith(
          pedidoId: pedido.id,
          numeroPedido: pedido.numero,
        ),
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Agendamento concluído e salvo no histórico (${pedido.numero})'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      debugPrint('>>> Erro ao criar pedido do agendamento: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao salvar no histórico: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Marca agendamento como Em Andamento
  Future<void> _marcarEmAndamento(AgendamentoServico agendamento, DataService dataService) async {
    try {
      await dataService.updateAgendamentoServico(
        agendamento.copyWith(
          status: 'Em Andamento',
          updatedAt: DateTime.now(),
        ),
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Serviço iniciado'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 2),
          ),
        );
        setState(() {}); // Atualizar UI
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao iniciar serviço: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Marca agendamento como Concluído e cria pedido no histórico
  Future<void> _marcarConcluido(AgendamentoServico agendamento, DataService dataService) async {
    try {
      final agendamentoAtualizado = agendamento.copyWith(
        status: 'Concluído',
        updatedAt: DateTime.now(),
      );
      
      await dataService.updateAgendamentoServico(agendamentoAtualizado);
      
      // Criar pedido no histórico
      await _criarPedidoDoAgendamento(agendamentoAtualizado, dataService);
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Serviço concluído e salvo no histórico'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
        setState(() {}); // Atualizar UI
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao concluir serviço: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Navega para tela de cadastro de cliente
  Future<void> _mostrarDialogCadastroRapidoCliente(
    BuildContext context,
    DataService dataService,
    Function(Cliente) onClienteCriado,
  ) async {
    // Navegar para a tela completa de cadastro de cliente
    final novoCliente = await Navigator.push<Cliente>(
      context,
      MaterialPageRoute(
        builder: (context) => const ClienteDetalhesPage(cliente: null),
      ),
    );

    // Se um cliente foi criado, atualizar a seleção
    if (novoCliente != null && context.mounted) {
      onClienteCriado(novoCliente);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cliente cadastrado com sucesso!'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  /// Navega para tela de cadastro de pet (dentro da tela de detalhes do cliente)
  Future<Cliente?> _mostrarDialogCadastroRapidoPet(
    BuildContext context,
    DataService dataService,
    Cliente cliente,
    Function(Pet) onPetCriado,
  ) async {
    // Navegar para a tela de detalhes do cliente na aba Pet (índice 3)
    final clienteAtualizado = await Navigator.push<Cliente>(
      context,
      MaterialPageRoute(
        builder: (context) => ClienteDetalhesPage(
          cliente: cliente,
          abaInicial: 3, // Ir direto para a aba Pet
        ),
      ),
    );

    // Se o cliente foi atualizado (com novo pet), atualizar a seleção
    if (clienteAtualizado != null && context.mounted) {
      // Aguardar um pouco para garantir que o DataService foi atualizado
      await Future.delayed(const Duration(milliseconds: 300));
      
      // Buscar o cliente atualizado do DataService para garantir que tem os pets mais recentes
      Cliente? clienteAtualizadoDoService;
      try {
        clienteAtualizadoDoService = dataService.clientes.firstWhere(
          (c) => c.id == cliente.id,
        );
      } catch (e) {
        // Se não encontrar, usar o cliente retornado
        clienteAtualizadoDoService = clienteAtualizado;
      }
      
      // Verificar se há novos pets comparando com os pets originais
      final petsAntigos = cliente.pets.map((p) => p.id).toSet();
      final novosPets = clienteAtualizadoDoService.pets.where((p) => !petsAntigos.contains(p.id)).toList();
      
      if (novosPets.isNotEmpty) {
        // Adicionar o primeiro novo pet à seleção
        onPetCriado(novosPets.first);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Pet "${novosPets.first.nome}" cadastrado com sucesso!'),
            backgroundColor: Colors.green,
          ),
        );
        return clienteAtualizadoDoService;
      } else {
        // Se não encontrou novos pets, verificar se o cliente retornado tem mais pets
        if (clienteAtualizado.pets.length > cliente.pets.length) {
          final petNovo = clienteAtualizado.pets.last;
          onPetCriado(petNovo);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Pet "${petNovo.nome}" cadastrado com sucesso!'),
              backgroundColor: Colors.green,
            ),
          );
          return clienteAtualizadoDoService;
        }
      }
      
      return clienteAtualizadoDoService;
    }
    
    return null;
  }

  /// Mapa Visual de Disponibilidade do Dia
  void _mostrarMapaDisponibilidade(BuildContext context, DataService dataService) {
    final config = dataService.empresaAtual?.configuracoes?['agendamento'] as Map<String, dynamic>?;
    final hAberturaStr = config?['horarioAbertura']?.toString() ?? '08:00';
    final hFechamentoStr = config?['horarioFechamento']?.toString() ?? '18:00';
    final intervaloSlots = config?['intervaloSlots'] != null 
        ? int.tryParse(config!['intervaloSlots'].toString()) ?? 30 
        : 30;
    
    final partsA = hAberturaStr.split(':');
    final partsF = hFechamentoStr.split(':');
    final horaAbertura = int.tryParse(partsA[0]) ?? 8;
    final minAbertura = int.tryParse(partsA.length > 1 ? partsA[1] : '0') ?? 0;
    final horaFechamento = int.tryParse(partsF[0]) ?? 18;
    final minFechamento = int.tryParse(partsF.length > 1 ? partsF[1] : '0') ?? 0;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            DateTime dataMapa = _dataSelecionada;

            // Agendamentos do dia (excluindo cancelados)
            final inicioDia = DateTime(dataMapa.year, dataMapa.month, dataMapa.day);
            final fimDia = inicioDia.add(const Duration(days: 1));
            final agendamentosDoDia = dataService.getAgendamentosPorPeriodo(inicioDia, fimDia)
                .where((a) => a.status != 'Cancelado')
                .toList()
              ..sort((a, b) => a.dataAgendamento.compareTo(b.dataAgendamento));

            // Calcular minutos totais do dia de trabalho
            final minutoInicio = horaAbertura * 60 + minAbertura;
            final minutoFim = horaFechamento * 60 + minFechamento;
            final totalMinutosDia = minutoFim - minutoInicio;
            if (totalMinutosDia <= 0) return const SizedBox();

            // Construir os blocos ocupados (ranges de minutos)
            List<Map<String, dynamic>> blocosOcupados = [];
            
            for (final ag in agendamentosDoDia) {
              final agMin = ag.dataAgendamento.hour * 60 + ag.dataAgendamento.minute;
              final duracao = ag.duracaoMinutos;
              final intervalo = ag.intervaloMinutos;
              final fimReal = agMin + duracao;
              final fimComIntervalo = fimReal + intervalo;
              
              final nomeCliente = ag.cliente?.nome ?? ag.clienteNome ?? 'Sem cliente';
              final nomePet = ag.pet?.nome ?? ag.petNome;
              final servico = ag.servico?.nome ?? 'Serviço';
              
              Color corBloco;
              switch (ag.status) {
                case 'Em Andamento':
                  corBloco = Colors.amber;
                  break;
                case 'Concluído':
                  corBloco = Colors.green[700]!;
                  break;
                case 'Aguardando Confirmação':
                  corBloco = Colors.orange;
                  break;
                default:
                  corBloco = Colors.blueAccent;
              }

              blocosOcupados.add({
                'inicio': agMin,
                'fim': fimReal,
                'fimComIntervalo': fimComIntervalo,
                'cor': corBloco,
                'titulo': nomeCliente,
                'subtitulo': nomePet != null ? '$servico • $nomePet' : servico,
                'status': ag.status,
                'duracao': duracao,
                'intervalo': intervalo,
              });
            }

            blocosOcupados.sort((a, b) => (a['inicio'] as int).compareTo(b['inicio'] as int));

            // Construir timeline mista: blocos ocupados + grades de slots livres
            List<Map<String, dynamic>> timeline = [];
            int cursor = minutoInicio;

            for (final bloco in blocosOcupados) {
              final blocoInicio = bloco['inicio'] as int;
              final blocoFimComIntervalo = bloco['fimComIntervalo'] as int;

              if (blocoInicio > cursor) {
                // Lacuna livre — gerar slots individuais
                timeline.add({
                  'tipo': 'slots_livres',
                  'inicio': cursor,
                  'fim': blocoInicio,
                });
              }
              // Bloco de agendamento
              timeline.add({
                'tipo': 'agendamento',
                ...bloco,
              });
              // Bloco de pausa (se houver intervalo)
              if ((bloco['intervalo'] as int) > 0) {
                timeline.add({
                  'tipo': 'pausa',
                  'inicio': bloco['fim'] as int,
                  'fim': blocoFimComIntervalo,
                  'duracao': bloco['intervalo'] as int,
                });
              }
              if (blocoFimComIntervalo > cursor) cursor = blocoFimComIntervalo;
            }

            // Lacuna final
            if (cursor < minutoFim) {
              timeline.add({
                'tipo': 'slots_livres',
                'inicio': cursor,
                'fim': minutoFim,
              });
            }

            String minToTime(int min) {
              final h = (min ~/ 60).toString().padLeft(2, '0');
              final m = (min % 60).toString().padLeft(2, '0');
              return '$h:$m';
            }

            final diaFormatado = '${dataMapa.day.toString().padLeft(2, '0')}/${dataMapa.month.toString().padLeft(2, '0')}/${dataMapa.year}';
            final diasSemana = ['', 'Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb', 'Dom'];
            final diaSemanaStr = diasSemana[dataMapa.weekday];
            
            // Contagens
            int slotsLivres = 0;
            for (final item in timeline) {
              if (item['tipo'] == 'slots_livres') {
                final ini = item['inicio'] as int;
                final fi = item['fim'] as int;
                for (int m = ini; m < fi; m += intervaloSlots) {
                  slotsLivres++;
                }
              }
            }

            return Container(
              height: MediaQuery.of(context).size.height * 0.85,
              decoration: const BoxDecoration(
                color: Color(0xFF0F172A),
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Column(
                children: [
                  // Handle
                  Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(top: 12, bottom: 8),
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  // Título + Navegação
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Colors.green.withOpacity(0.3), Colors.teal.withOpacity(0.1)],
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.map_rounded, color: Colors.greenAccent, size: 24),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Mapa de Disponibilidade',
                                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                              ),
                              Text(
                                '$diaSemanaStr, $diaFormatado',
                                style: const TextStyle(color: Colors.white60, fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.chevron_left, color: Colors.white70),
                          onPressed: () {
                            setModalState(() {
                              dataMapa = dataMapa.subtract(const Duration(days: 1));
                              setState(() => _dataSelecionada = dataMapa);
                            });
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.chevron_right, color: Colors.white70),
                          onPressed: () {
                            setModalState(() {
                              dataMapa = dataMapa.add(const Duration(days: 1));
                              setState(() => _dataSelecionada = dataMapa);
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                  // Resumo compacto
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                    child: Row(
                      children: [
                        _buildMapaResumoChip(Icons.check_circle_outline, '$slotsLivres livres', Colors.greenAccent),
                        const SizedBox(width: 8),
                        _buildMapaResumoChip(Icons.event_busy, '${agendamentosDoDia.length} agendados', Colors.blueAccent),
                        const SizedBox(width: 8),
                        _buildMapaResumoChip(Icons.access_time, '${minToTime(minutoInicio)} - ${minToTime(minutoFim)}', Colors.white54),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Divider(color: Colors.white12, height: 1),
                  // Timeline com slots
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      itemCount: timeline.length,
                      itemBuilder: (context, index) {
                        final item = timeline[index];
                        final tipo = item['tipo'] as String;

                        if (tipo == 'agendamento') {
                          // Card do agendamento
                          final inicio = item['inicio'] as int;
                          final fim = item['fim'] as int;
                          final cor = item['cor'] as Color;
                          final titulo = item['titulo'] as String;
                          final subtitulo = item['subtitulo'] as String;
                          final status = item['status'] as String;
                          final dur = item['duracao'] as int;

                          return Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: cor.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: cor.withOpacity(0.4)),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 4,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: cor,
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Icon(Icons.person, color: cor, size: 18),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        titulo,
                                        style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      Text(
                                        subtitulo,
                                        style: const TextStyle(color: Colors.white54, fontSize: 11),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      '${minToTime(inicio)} - ${minToTime(fim)}',
                                      style: TextStyle(color: cor, fontSize: 12, fontWeight: FontWeight.bold),
                                    ),
                                    Text(
                                      '${dur}min • $status',
                                      style: const TextStyle(color: Colors.white38, fontSize: 10),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        } else if (tipo == 'pausa') {
                          // Linha de pausa compacta
                          final inicio = item['inicio'] as int;
                          final dur = item['duracao'] as int;
                          return Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.03),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.white.withOpacity(0.06)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.coffee, color: Colors.white30, size: 14),
                                const SizedBox(width: 8),
                                Text(
                                  'Pausa (${dur}min) • a partir de ${minToTime(inicio)}',
                                  style: const TextStyle(color: Colors.white30, fontSize: 11),
                                ),
                              ],
                            ),
                          );
                        } else {
                          // === SLOTS LIVRES: Grade igual a do cliente ===
                          final ini = item['inicio'] as int;
                          final fi = item['fim'] as int;
                          final slotsNesta = <int>[];
                          for (int m = ini; m < fi; m += intervaloSlots) {
                            slotsNesta.add(m);
                          }

                          if (slotsNesta.isEmpty) return const SizedBox();

                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.green.withOpacity(0.06),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: Colors.green.withOpacity(0.15)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.event_available, color: Colors.greenAccent, size: 16),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Horários Disponíveis (${minToTime(ini)} - ${minToTime(fi)})',
                                      style: const TextStyle(color: Colors.greenAccent, fontSize: 12, fontWeight: FontWeight.w600),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: slotsNesta.map((slotMin) {
                                    return InkWell(
                                      onTap: () {
                                        Navigator.pop(ctx);
                                        final h = slotMin ~/ 60;
                                        final m = slotMin % 60;
                                        _mostrarDialogNovoAgendamento(
                                          context,
                                          dataService,
                                          dataHoraPreSelecionada: DateTime(dataMapa.year, dataMapa.month, dataMapa.day, h, m),
                                        );
                                      },
                                      borderRadius: BorderRadius.circular(10),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                        decoration: BoxDecoration(
                                          color: Colors.green.withOpacity(0.12),
                                          borderRadius: BorderRadius.circular(10),
                                          border: Border.all(color: Colors.greenAccent.withOpacity(0.35)),
                                        ),
                                        child: Text(
                                          minToTime(slotMin),
                                          style: const TextStyle(
                                            color: Colors.greenAccent,
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ],
                            ),
                          );
                        }
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildMapaResumoChip(IconData icon, String text, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 14),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                text,
                style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Gera e exibe o link de agendamento online para a empresa atual
  void _gerarLinkAgendamento(DataService dataService) {
    // Obter o identificador da empresa (prefere slug ao ID)
    // Tentar obter a empresa do DataService primeiro, e do AuthService como fallback
    Empresa? empresa = dataService.empresaAtual;
    
    if (empresa == null) {
      try {
        final authService = Provider.of<AuthService>(context, listen: false);
        empresa = authService.empresaAtual;
      } catch (e) {
        debugPrint('Erro ao obter AuthService no link de agendamento: $e');
      }
    }

    String? identificador;
    
    if (empresa != null) {
      if (empresa.slug.isNotEmpty) {
        identificador = empresa.slug;
      } else {
        // Fallback: Gerar slug a partir do nome se o campo slug estiver vazio
        identificador = Empresa.gerarSlug(empresa.nomeExibicao);
      }
    }
    
    // Se ainda for nulo (não deveria), usa o ID
    identificador ??= dataService.empresaIdAtual;


    if (identificador == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Selecione uma empresa primeiro'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    // Gerar o link de agendamento online baseado na URL atual do navegador
    String baseUrl = '';
    if (kIsWeb) {
      // Usar o origin atual (host + protocolo) 
      baseUrl = html_helper.getWindowOrigin();
      // Remover barra final se houver para evitar barra dupla
      if (baseUrl.endsWith('/')) {
        baseUrl = baseUrl.substring(0, baseUrl.length - 1);
      }
    } else {
      baseUrl = 'https://sistema-exodo.web.app'; // Fallback para mobile/desktop
    }
    
    // Garantir que identificador não tenha espaços ou caracteres especiais
    final identificadorLimpo = identificador!.trim();
    // Link no formato /agendamento/slug para ser igual ao ecommerce
    final link = '$baseUrl/agendamento/$identificadorLimpo';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text('Link de Agendamento Online', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Compartilhe este link com seus clientes para que eles possam agendar serviços online:',
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white24),
              ),
              child: SelectableText(
                link,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        actions: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Fechar', style: TextStyle(color: Colors.white54)),
              ),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: () {
                      if (kIsWeb) {
                        html_helper.openWindow(link, '_blank');
                      } else {
                        // Para mobile/desktop usaria url_launcher se disponível
                        // Por enquanto apenas copia
                        Clipboard.setData(ClipboardData(text: link));
                      }
                    },
                    icon: const Icon(Icons.open_in_new, size: 18),
                    label: const Text('Abrir'),
                    style: TextButton.styleFrom(foregroundColor: Colors.blueAccent),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: link));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Link copiado para a área de transferência!'),
                          backgroundColor: Colors.green,
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                    icon: const Icon(Icons.copy, size: 18),
                    label: const Text('Copiar'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF9800),
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
  /// Mostra as solicitações de agendamento online (Aguardando Confirmação)
  void _mostrarSolicitacoesAgendamento(BuildContext context, DataService dataService) {
    // Conjunto local de IDs processados (aprovados/rejeitados) para remoção imediata da lista
    final Set<String> idsProcessados = {};
    // Conjunto local de IDs em processamento (mostrando loading)
    final Set<String> idsProcessando = {};
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (modalContext) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: StatefulBuilder(
          builder: (sbContext, setModalState) {
          return Consumer<DataService>(
          builder: (consumerContext, currentDataService, _) {
            final solicitacoes = currentDataService.agendamentosServico
                .where((a) => a.status == 'Aguardando Confirmação' && !idsProcessados.contains(a.id))
                .toList();

            final totalTodos = currentDataService.agendamentosServico.length;
            final outrosStatus = currentDataService.agendamentosServico
                .where((a) => a.status != 'Aguardando Confirmação')
                .map((a) => '${a.status}:${a.id.length > 4 ? a.id.substring(a.id.length - 4) : a.id}')
                .join(', ');

            // Ordenar por data (mais recente primeiro)
            solicitacoes.sort((a, b) => b.dataAgendamento.compareTo(a.dataAgendamento));

            // Se não tiver mais solicitações e temos IDs processados, fechar o modal
            if (solicitacoes.isEmpty && idsProcessados.isNotEmpty) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (modalContext.mounted) {
                  Navigator.pop(modalContext);
                }
              });
            }

            return Container(
              height: MediaQuery.of(modalContext).size.height * 0.8,
              decoration: const BoxDecoration(
                color: Color(0xFF1E1E2E), // Cor escura do sistema
                borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                currentDataService.empresaAtual?.nomeExibicao ?? 'Solicitações Online',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                'ID: ${currentDataService.empresaIdAtual}',
                                style: const TextStyle(
                                  color: Colors.white38,
                                  fontSize: 10,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        // Botão de Refresh Manual no Modal
                        IconButton(
                          icon: const Icon(Icons.refresh, color: Colors.blueAccent, size: 20),
                          onPressed: () async {
                             ScaffoldMessenger.of(modalContext).showSnackBar(
                              const SnackBar(content: Text('Buscando atualizações no Firebase...')),
                            );
                            await currentDataService.forceSync();
                          },
                          tooltip: 'Recarregar Agora',
                        ),
                        // Botão de Diagnóstico (Long Press na Info)
                        GestureDetector(
                          onLongPress: () async {
                            ScaffoldMessenger.of(modalContext).showSnackBar(
                              const SnackBar(content: Text('Verificando Firestore...')),
                            );
                            final count = await FirebaseService.instance.contarAgendamentosPendentes(currentDataService.empresaIdAtual!);
                            if (modalContext.mounted) {
                            ScaffoldMessenger.of(modalContext).showSnackBar(
                              SnackBar(
                                content: Text('Encontrados $count docs em: .../${currentDataService.empresaIdAtual}/agendamentos_servico'),
                                backgroundColor: Colors.blueAccent,
                                action: SnackBarAction(
                                  label: 'CRIAR TESTE',
                                  textColor: Colors.white,
                                  onPressed: () async {
                                    final teste = AgendamentoServico(
                                      id: 'TESTE-${DateTime.now().millisecondsSinceEpoch}',
                                      numero: 'TS-999',
                                      dataAgendamento: DateTime.now(),
                                      status: 'Aguardando Confirmação',
                                      observacoes: 'AGENDAMENTO DE TESTE PARA VERIFICAR CONEXÃO',
                                    );
                                    await FirebaseService.instance.salvarAgendamentoServico(currentDataService.empresaIdAtual!, teste);
                                  },
                                ),
                              ),
                            );
                            }
                          },
                          child: const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8.0),
                            child: Icon(Icons.info_outline, color: Colors.white10, size: 20),
                          ),
                        ),
                        if (solicitacoes.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.amber.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.amber.withOpacity(0.3)),
                            ),
                            child: Text(
                              '${solicitacoes.length} PENDENTE(S)',
                              style: const TextStyle(
                                color: Colors.amber,
                                fontWeight: FontWeight.bold,
                                fontSize: 10,
                              ),
                            ),
                          ),
                        const SizedBox(width: 8),
                        Text(
                          'Total: $totalTodos',
                          style: const TextStyle(color: Colors.white24, fontSize: 10),
                        ),
                        if (totalTodos > 0)
                          IconButton(
                            icon: const Icon(Icons.bug_report, size: 14, color: Colors.white10),
                            onPressed: () {
                              debugPrint('>>> [DEBUG-MODAL] 📋 Todos os agendamentos em memória:');
                              for (var a in currentDataService.agendamentosServico) {
                                debugPrint('    - ID: ${a.id} | Status: ${a.status} | Data: ${a.dataAgendamento}');
                              }
                            },
                          ),
                      ],
                    ),
                  ),
                  if (outrosStatus.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0, left: 24, right: 24),
                      child: Text(
                        'Outros: $outrosStatus',
                        style: const TextStyle(color: Colors.white10, fontSize: 8),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  const SizedBox(height: 24),
                  Expanded(
                    child: solicitacoes.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.event_available_rounded, size: 80, color: Colors.white.withOpacity(0.05)),
                                const SizedBox(height: 16),
                                const Text(
                                  'Nenhuma nova solicitação no momento.',
                                  style: TextStyle(color: Colors.white38),
                                ),
                              ],
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                            itemCount: solicitacoes.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 16),
                            itemBuilder: (listContext, index) {
                              final sol = solicitacoes[index];
                              final isProcessando = idsProcessando.contains(sol.id);
                              return AnimatedOpacity(
                                opacity: isProcessando ? 0.4 : 1.0,
                                duration: const Duration(milliseconds: 300),
                                child: AnimatedScale(
                                  scale: isProcessando ? 0.95 : 1.0,
                                  duration: const Duration(milliseconds: 300),
                                  child: Container(
                                padding: const EdgeInsets.all(20),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.05),
                                  borderRadius: BorderRadius.circular(24),
                                  border: Border.all(color: Colors.white.withOpacity(0.05)),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            color: Colors.blueAccent.withOpacity(0.1),
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(Icons.person_outline_rounded, color: Colors.blueAccent, size: 24),
                                        ),
                                        const SizedBox(width: 16),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                sol.clienteNome ?? sol.cliente?.nome ?? 'Cliente Publico',
                                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                                              ),
                                              Row(
                                                children: [
                                                  Text(
                                                    sol.clienteTelefone ?? sol.cliente?.telefone ?? 'Sem telefone',
                                                    style: const TextStyle(color: Colors.white54, fontSize: 13),
                                                  ),
                                                  if ((sol.clienteTelefone ?? sol.cliente?.telefone) != null) ...[
                                                    const SizedBox(width: 8),
                                                    InkWell(
                                                      onTap: () => _abrirWhatsAppComDados(sol.clienteTelefone ?? sol.cliente!.telefone, sol),
                                                      child: const Icon(Icons.chat, color: Colors.green, size: 16),
                                                    ),
                                                    const SizedBox(width: 8),
                                                    InkWell(
                                                      onTap: () => _copiarTelefoneClipboard(sol.clienteTelefone ?? sol.cliente!.telefone),
                                                      child: const Icon(Icons.copy, color: Colors.blueAccent, size: 16),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        IconButton(
                                          icon: Icon(
                                            (sol.clienteId == 'publico' || sol.clienteId == null) 
                                              ? Icons.person_add_alt_1 
                                              : Icons.edit, 
                                            color: Colors.blueAccent.withOpacity(0.8),
                                            size: 20,
                                          ),
                                          tooltip: (sol.clienteId == 'publico' || sol.clienteId == null)
                                            ? 'Vincular/Cadastrar Cliente'
                                            : 'Editar Cliente',
                                          onPressed: isProcessando ? null : () => _editarOuVincularCliente(modalContext, sol, currentDataService),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.event_note_rounded, color: Colors.orange, size: 20),
                                          tooltip: 'Editar Agendamento Completo',
                                          onPressed: isProcessando ? null : () => _editarAgendamento(modalContext, sol, currentDataService),
                                        ),
                                      ],
                                    ),
                                    const Padding(
                                      padding: EdgeInsets.symmetric(vertical: 16),
                                      child: Divider(color: Colors.white10),
                                    ),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: _buildInfoItem(
                                            Icons.calendar_today_rounded,
                                            'Data',
                                            _formatoData?.format(sol.dataAgendamento) ?? '',
                                          ),
                                        ),
                                        Expanded(
                                          child: _buildInfoItem(
                                            Icons.access_time_rounded,
                                            'Horário',
                                            _formatoHora?.format(sol.dataAgendamento) ?? '',
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 16),
                                    _buildInfoItem(
                                      (currentDataService.empresaAtual?.moduloPet == true || sol.petNome != null || sol.pet != null) ? Icons.pets_rounded : Icons.work_rounded,
                                      (currentDataService.empresaAtual?.moduloPet == true || sol.petNome != null || sol.pet != null) ? 'Pet / Serviço' : 'Serviço',
                                      (currentDataService.empresaAtual?.moduloPet == true || sol.petNome != null || sol.pet != null)
                                        ? '${sol.petNome ?? sol.pet?.nome ?? "Não informado"}${sol.pet?.raca != null ? " (${sol.pet!.raca})" : ""} - ${sol.servico?.nome ?? sol.servicoId ?? "Serviço"}'
                                        : (sol.servico?.nome ?? sol.servicoId ?? "Serviço"),
                                    ),
                                    if (sol.pet != null) 
                                      Padding(
                                        padding: const EdgeInsets.only(top: 8),
                                        child: Text(
                                          'Pet Detalhes: ${sol.pet!.especie ?? ""} ${sol.pet!.sexo == "M" ? "♂" : sol.pet!.sexo == "F" ? "♀" : ""} ${sol.pet!.cor ?? ""} - Porte: ${sol.pet!.tamanho ?? "N/I"} - Peso: ${sol.pet!.peso != null ? "${sol.pet!.peso}kg" : "N/I"}',
                                          style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 11),
                                        ),
                                      ),
                                    if (sol.tipoEntrega != null && sol.tipoEntrega != 'Retirada na Loja')
                                      Container(
                                        margin: const EdgeInsets.only(top: 12),
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: Colors.blueAccent.withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(color: Colors.blueAccent.withOpacity(0.2)),
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(
                                              sol.tipoEntrega == 'Taxi Dog' ? Icons.local_shipping_rounded : Icons.home_rounded, 
                                              color: Colors.blueAccent, 
                                              size: 20
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    'Solicitado: ${sol.tipoEntrega}',
                                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                                  ),
                                                  Text(
                                                    'Bairro: ${sol.bairroEntrega ?? "Não informado"} ${sol.valorTaxiDog != null ? "(Taxa: R\$ ${sol.valorTaxiDog!.toStringAsFixed(2)})" : ""}',
                                                    style: const TextStyle(color: Colors.white60, fontSize: 11),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    if (sol.observacoes != null && sol.observacoes!.isNotEmpty) ...[
                                      const SizedBox(height: 16),
                                      Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withOpacity(0.03),
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Text(
                                          sol.observacoes!,
                                          style: const TextStyle(color: Colors.white38, fontSize: 12),
                                        ),
                                      ),
                                    ],
                                    const SizedBox(height: 24),
                                    if (isProcessando)
                                      const Center(
                                        child: Padding(
                                          padding: EdgeInsets.symmetric(vertical: 8),
                                          child: Row(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              SizedBox(
                                                width: 20, height: 20,
                                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.amber),
                                              ),
                                              SizedBox(width: 12),
                                              Text('Processando...', style: TextStyle(color: Colors.amber, fontSize: 13)),
                                            ],
                                          ),
                                        ),
                                      )
                                    else
                                    Row(
                                      children: [
                                        Expanded(
                                          child: ElevatedButton(
                                            onPressed: () async {
                                                try {
                                                  // Marcar como processando imediatamente
                                                  setModalState(() {
                                                    idsProcessando.add(sol.id);
                                                  });
                                                  
                                                  await currentDataService.rejeitarAgendamento(sol.id);
                                                  
                                                  // Marcar como processado para remoção imediata da lista
                                                  setModalState(() {
                                                    idsProcessando.remove(sol.id);
                                                    idsProcessados.add(sol.id);
                                                  });
                                                  
                                                  if (modalContext.mounted) {
                                                    ScaffoldMessenger.of(modalContext).hideCurrentSnackBar();
                                                    ScaffoldMessenger.of(modalContext).showSnackBar(
                                                      const SnackBar(
                                                        content: Text('Solicitação cancelada/rejeitada'),
                                                        behavior: SnackBarBehavior.floating,
                                                      ),
                                                    );
                                                  }
                                                  
                                                  // Limpar filtros da página principal
                                                  setState(() {
                                                     _termoBusca = '';
                                                     _buscaController.clear();
                                                     _filtroStatus = null;
                                                  });
                                                  
                                                  currentDataService.forceUpdate();
                                                } catch (e) {
                                                  // Desfazer processando em caso de erro
                                                  setModalState(() {
                                                    idsProcessando.remove(sol.id);
                                                  });
                                                  if (modalContext.mounted) {
                                                    ScaffoldMessenger.of(modalContext).showSnackBar(
                                                      SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red),
                                                    );
                                                  }
                                              }
                                            },
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: Colors.redAccent.withOpacity(0.1),
                                              foregroundColor: Colors.redAccent,
                                              elevation: 0,
                                              padding: const EdgeInsets.symmetric(vertical: 16),
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                              side: BorderSide(color: Colors.redAccent.withOpacity(0.3)),
                                            ),
                                            child: const Text('Rejeitar', style: TextStyle(fontWeight: FontWeight.bold)),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: ElevatedButton(
                                            onPressed: () async {
                                                try {
                                                  // Marcar como processando imediatamente
                                                  setModalState(() {
                                                    idsProcessando.add(sol.id);
                                                  });
                                                  
                                                  // Capturar o ScaffoldMessenger ANTES de qualquer pop ou mudança de contexto
                                                  final messenger = ScaffoldMessenger.of(modalContext);
                                                  
                                                  await currentDataService.aprovarAgendamento(sol.id);
                                                  
                                                  // Marcar como processado para remoção imediata da lista
                                                  setModalState(() {
                                                    idsProcessando.remove(sol.id);
                                                    idsProcessados.add(sol.id);
                                                  });
                                                  
                                                  if (modalContext.mounted) {
                                                    messenger.hideCurrentSnackBar();
                                                    messenger.showSnackBar(
                                                      const SnackBar(
                                                        content: Text('Solicitação aprovada com sucesso!'), 
                                                        backgroundColor: Colors.green,
                                                        behavior: SnackBarBehavior.floating,
                                                      ),
                                                    );
                                                  }
                                                  
                                                  // Limpar filtros locais para que o agendamento apareça na agenda
                                                  setState(() {
                                                     _termoBusca = '';
                                                     _buscaController.clear();
                                                     _filtroStatus = null; // Mostrar todos
                                                     _filtroTipo = 'Todos';
                                                  });

                                                  // Forçar atualização local da agenda
                                                  currentDataService.forceUpdate();
                                                } catch (e) {
                                                  // Desfazer processando em caso de erro
                                                  setModalState(() {
                                                    idsProcessando.remove(sol.id);
                                                  });
                                                  if (modalContext.mounted) {
                                                    ScaffoldMessenger.of(modalContext).showSnackBar(
                                                      SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red),
                                                    );
                                                  }
                                                }
                                            },
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: const Color(0xFFFF9800),
                                              foregroundColor: Colors.white,
                                              elevation: 4,
                                              padding: const EdgeInsets.symmetric(vertical: 16),
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                            ),
                                            child: const Text('Confirmar Agendamento', style: TextStyle(fontWeight: FontWeight.bold)),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
          },
        ),
      );
    },
  );
}

  Widget _buildInfoItem(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFFFF9800).withOpacity(0.5), size: 16),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: Colors.white38, fontSize: 10)),
            Text(value, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
          ],
        ),
      ],
    );
  }
}
