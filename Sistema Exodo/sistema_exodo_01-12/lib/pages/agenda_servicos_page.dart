import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../services/data_service.dart';
import '../models/agendamento_servico.dart';
import '../models/servico.dart';
import '../models/cliente.dart';
import '../theme.dart';

class AgendaServicosPage extends StatefulWidget {
  const AgendaServicosPage({super.key});

  @override
  State<AgendaServicosPage> createState() => _AgendaServicosPageState();
}

class _AgendaServicosPageState extends State<AgendaServicosPage> {
  DateTime _dataSelecionada = DateTime.now();
  String _visualizacao = 'Dia'; // 'Dia', 'Semana', 'Mês'
  final DateFormat _formatoData = DateFormat('dd/MM/yyyy');
  final DateFormat _formatoHora = DateFormat('HH:mm');
  final DateFormat _formatoDataHora = DateFormat('dd/MM/yyyy HH:mm');

  @override
  Widget build(BuildContext context) {
    final dataService = Provider.of<DataService>(context);
    
    return AppTheme.appBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Agenda de Serviços'),
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: Colors.white,
          actions: [
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
            _buildControlesNavegacao(),
            // Visualização
            Expanded(
              child: _buildVisualizacao(dataService),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlesNavegacao() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.3),
        border: Border(
          bottom: BorderSide(color: Colors.white.withOpacity(0.1)),
        ),
      ),
      child: Column(
        children: [
          // Seletor de visualização
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildBotaoVisualizacao('Dia', Icons.view_day),
              const SizedBox(width: 8),
              _buildBotaoVisualizacao('Semana', Icons.view_week),
              const SizedBox(width: 8),
              _buildBotaoVisualizacao('Mês', Icons.calendar_month),
            ],
          ),
          const SizedBox(height: 16),
          // Navegação de data
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left, color: Colors.white),
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
              ),
              GestureDetector(
                onTap: () => _selecionarData(context),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.withOpacity(0.5)),
                  ),
                  child: Text(
                    _getTextoData(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right, color: Colors.white),
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelecionado 
              ? Colors.blue.withOpacity(0.3)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelecionado 
                ? Colors.blue
                : Colors.white.withOpacity(0.2),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: isSelecionado ? Colors.blueAccent : Colors.white70, size: 18),
            const SizedBox(width: 4),
            Text(
              tipo,
              style: TextStyle(
                color: isSelecionado ? Colors.white : Colors.white70,
                fontWeight: isSelecionado ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getTextoData() {
    if (_visualizacao == 'Dia') {
      return _formatoData.format(_dataSelecionada);
    } else if (_visualizacao == 'Semana') {
      final inicioSemana = _dataSelecionada.subtract(Duration(days: _dataSelecionada.weekday - 1));
      final fimSemana = inicioSemana.add(const Duration(days: 6));
      return '${_formatoData.format(inicioSemana)} - ${_formatoData.format(fimSemana)}';
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

  List<AgendamentoServico> _getAgendamentosPeriodo(DataService dataService) {
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
    
    return dataService.getAgendamentosPorPeriodo(inicio, fim);
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
                          Container(
                            height: 1,
                            color: Colors.white.withOpacity(0.1),
                          ),
                        ]
                      : agendamentosHora.map((agendamento) {
                          return _buildCardAgendamento(agendamento, dataService);
                        }).toList(),
                ),
              ),
            ],
          ),
        );
      },
    );
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
                        final corStatus = _getCorStatus(agendamento.status);
                        final corFundo = _getCorFundoStatus(agendamento.status);
                        
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
                            '${_formatoHora.format(agendamento.dataAgendamento)}',
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

  Widget _buildCardAgendamento(AgendamentoServico agendamento, DataService dataService) {
    final corStatus = _getCorStatus(agendamento.status);
    final corFundo = _getCorFundoStatus(agendamento.status);
    
    return GestureDetector(
      onTap: () => _mostrarDetalhesAgendamento(context, agendamento, dataService),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              corFundo,
              Color.lerp(corFundo, corStatus, 0.3)!,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: corStatus.withOpacity(0.8),
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: corStatus.withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    agendamento.servico?.nome ?? 'Serviço',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      shadows: [
                        Shadow(
                          color: Colors.black54,
                          blurRadius: 2,
                        ),
                      ],
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    _formatoHora.format(agendamento.dataAgendamento),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            if (agendamento.cliente != null) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.person, size: 14, color: Colors.white70),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      agendamento.cliente!.nome,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: corStatus.withOpacity(0.3),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: corStatus.withOpacity(0.6),
                  width: 1,
                ),
              ),
              child: Text(
                agendamento.status.toUpperCase(),
                style: TextStyle(
                  color: corStatus,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCardAgendamentoCompacto(AgendamentoServico agendamento, DataService dataService) {
    final corStatus = _getCorStatus(agendamento.status);
    final corFundo = _getCorFundoStatus(agendamento.status);
    
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
              _formatoHora.format(agendamento.dataAgendamento),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              agendamento.servico?.nome ?? 'Serviço',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 9,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
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
          ],
        ),
      ),
    );
  }

  void _mostrarDetalhesAgendamento(
    BuildContext context,
    AgendamentoServico agendamento,
    DataService dataService,
  ) {
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
                color: _getCorStatus(agendamento.status).withOpacity(0.3),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.event,
                color: _getCorStatus(agendamento.status),
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
              _buildInfoLinha('Serviço', agendamento.servico?.nome ?? 'N/A'),
              _buildInfoLinha('Cliente', agendamento.cliente?.nome ?? 'N/A'),
              _buildInfoLinha('Data/Hora', _formatoDataHora.format(agendamento.dataAgendamento)),
              _buildInfoLinha('Duração', '${agendamento.duracaoMinutos} minutos'),
              _buildInfoLinha('Status', agendamento.status),
              if (agendamento.observacoes != null && agendamento.observacoes!.isNotEmpty)
                _buildInfoLinha('Observações', agendamento.observacoes!),
            ],
          ),
        ),
        actions: [
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

  void _mostrarDialogNovoAgendamento(BuildContext context, DataService dataService) async {
    final servicos = dataService.servicos;
    final clientes = dataService.clientes;
    
    if (servicos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cadastre pelo menos um serviço antes de agendar'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    Servico? servicoSelecionado = servicos.first;
    Cliente? clienteSelecionado;
    DateTime dataAgendamento = _dataSelecionada;
    TimeOfDay horaAgendamento = TimeOfDay.now();
    int duracaoMinutos = 60;
    final observacoesController = TextEditingController();

    await showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
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
                const Text('Serviço:', style: TextStyle(color: Colors.white70, fontSize: 14)),
                const SizedBox(height: 8),
                DropdownButtonFormField<Servico>(
                  value: servicoSelecionado,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.05),
                  ),
                  dropdownColor: const Color(0xFF2C2C3E),
                  style: const TextStyle(color: Colors.white),
                  items: servicos.map((s) {
                    return DropdownMenuItem(
                      value: s,
                      child: Text(s.nome),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => servicoSelecionado = value);
                    }
                  },
                ),
                const SizedBox(height: 16),
                // Seleção de Cliente
                const Text('Cliente:', style: TextStyle(color: Colors.white70, fontSize: 14)),
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
                    ...clientes.map((c) {
                      return DropdownMenuItem(
                        value: c,
                        child: Text(c.nome),
                      );
                    }),
                  ],
                  onChanged: (value) {
                    setState(() => clienteSelecionado = value);
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
                          _formatoData.format(dataAgendamento),
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
                    final hora = await showTimePicker(
                      context: context,
                      initialTime: horaAgendamento,
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
                          horaAgendamento.format(context),
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
              onPressed: () async {
                if (servicoSelecionado == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Selecione um serviço'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }

                final dataHoraCompleta = DateTime(
                  dataAgendamento.year,
                  dataAgendamento.month,
                  dataAgendamento.day,
                  horaAgendamento.hour,
                  horaAgendamento.minute,
                );

                // Verificar conflitos
                if (dataService.verificarConflitoHorario(dataHoraCompleta, duracaoMinutos)) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Já existe um agendamento neste horário!'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }

                try {
                  final novoAgendamento = AgendamentoServico(
                    id: DateTime.now().millisecondsSinceEpoch.toString(),
                    servicoId: servicoSelecionado!.id,
                    clienteId: clienteSelecionado?.id,
                    dataAgendamento: dataHoraCompleta,
                    duracaoMinutos: duracaoMinutos,
                    observacoes: observacoesController.text.trim().isEmpty
                        ? null
                        : observacoesController.text.trim(),
                    status: 'Agendado',
                  );

                  await dataService.addAgendamentoServico(novoAgendamento);
                  
                  if (context.mounted) {
                    Navigator.pop(dialogContext);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Agendamento criado com sucesso!'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Erro: ${e.toString()}'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
              child: const Text('Agendar'),
            ),
          ],
        ),
      ),
    );
  }

  void _editarAgendamento(BuildContext context, AgendamentoServico agendamento, DataService dataService) {
    // Implementar edição
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
}

