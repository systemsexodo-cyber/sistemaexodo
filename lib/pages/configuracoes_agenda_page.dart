import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/data_service.dart';
import '../services/auth_service.dart';
import '../models/empresa.dart';
import '../theme.dart';
import '../widgets/sync_status_widget.dart';

class ConfiguracoesAgendaPage extends StatefulWidget {
  const ConfiguracoesAgendaPage({super.key});

  @override
  State<ConfiguracoesAgendaPage> createState() => _ConfiguracoesAgendaPageState();
}

class _ConfiguracoesAgendaPageState extends State<ConfiguracoesAgendaPage> {
  final _whatsappContatoController = TextEditingController();
  final _novoBairroController = TextEditingController();
  final _taxaController = TextEditingController();
  final _taxaBuscaController = TextEditingController();
  final _taxaSolevaController = TextEditingController();
  bool _esconderValores = false;
  bool _modoSolicitacao = false;
  bool _permitirEscolhaProfissional = false;
  bool _enviarValorWhatsApp = true;
  List<Map<String, dynamic>> _bairrosConfig = [];
  List<Map<String, dynamic>> _horariosIndisponiveis = [];
  bool _isLoading = false;

  TimeOfDay _horarioAbertura = const TimeOfDay(hour: 8, minute: 0);
  TimeOfDay _horarioFechamento = const TimeOfDay(hour: 18, minute: 0);
  int _intervaloSlots = 30;

  @override
  void initState() {
    super.initState();
    _carregarConfiguracoes();
  }

  @override
  void dispose() {
    _whatsappContatoController.dispose();
    _novoBairroController.dispose();
    _taxaController.dispose();
    _taxaBuscaController.dispose();
    _taxaSolevaController.dispose();
    super.dispose();
  }

  void _carregarConfiguracoes() {
    final authService = Provider.of<AuthService>(context, listen: false);
    final dataService = Provider.of<DataService>(context, listen: false);
    
    // Priorizar empresa do AuthService (sessão) ou DataService (dados)
    final empresa = authService.empresaAtual ?? dataService.empresaAtual;
    
    if (empresa != null && empresa.configuracoes != null) {
      final config = empresa.configuracoes!;
      final agendamentoConfig = config['agendamento'] as Map<String, dynamic>? ?? {};
      
      _whatsappContatoController.text = agendamentoConfig['whatsappContato']?.toString() ?? '';
      _esconderValores = agendamentoConfig['esconderValores'] as bool? ?? false;
      _modoSolicitacao = agendamentoConfig['modoSolicitacao'] as bool? ?? false;
      _permitirEscolhaProfissional = agendamentoConfig['permitirEscolhaProfissional'] as bool? ?? false;
      _enviarValorWhatsApp = agendamentoConfig['enviarValorWhatsApp'] as bool? ?? true;
      
      final bairrosData = (config['bairrosTaxiDogV2'] ?? agendamentoConfig['bairrosTaxiDogV2']) as List<dynamic>?;
      
      if (bairrosData != null) {
        _bairrosConfig = bairrosData.map((e) => Map<String, dynamic>.from(e)).toList();
      } else {
        final bairrosAntigos = (config['bairrosTaxiDog'] ?? agendamentoConfig['bairrosTaxiDog']) as List<dynamic>?;
        if (bairrosAntigos != null) {
          _bairrosConfig = bairrosAntigos.map((e) => {
            'bairro': e.toString(), 
            'taxa': 0.0,
            'taxaBusca': 0.0,
            'taxaSoleva': 0.0,
          }).toList();
        }
      }

      final horariosData = agendamentoConfig['horariosIndisponiveis'] as List<dynamic>?;
      if (horariosData != null) {
        _horariosIndisponiveis = horariosData.map((e) => Map<String, dynamic>.from(e)).toList();
      }

      // Horário de Atendimento
      final hAbertura = agendamentoConfig['horarioAbertura']?.toString() ?? '08:00';
      final hFechamento = agendamentoConfig['horarioFechamento']?.toString() ?? '18:00';
      _intervaloSlots = agendamentoConfig['intervaloSlots'] != null 
          ? int.tryParse(agendamentoConfig['intervaloSlots'].toString()) ?? 30 
          : 30;

      try {
        final partsA = hAbertura.split(':');
        _horarioAbertura = TimeOfDay(hour: int.parse(partsA[0]), minute: int.parse(partsA[1]));
        
        final partsF = hFechamento.split(':');
        _horarioFechamento = TimeOfDay(hour: int.parse(partsF[0]), minute: int.parse(partsF[1]));
      } catch (_) {}
    }
  }

  Future<void> _salvarConfiguracoes() async {
    setState(() => _isLoading = true);
    final dataService = Provider.of<DataService>(context, listen: false);
    final empresa = dataService.empresaAtual;

    if (empresa != null) {
      final novasConfigs = Map<String, dynamic>.from(empresa.configuracoes ?? {});
      final agendamentoConfig = Map<String, dynamic>.from(novasConfigs['agendamento'] ?? {});
      
      agendamentoConfig['bairrosTaxiDogV2'] = _bairrosConfig;
      agendamentoConfig['bairrosTaxiDog'] = _bairrosConfig.map((e) => e['bairro']).toList();
      agendamentoConfig['horariosIndisponiveis'] = _horariosIndisponiveis;
      agendamentoConfig['whatsappContato'] = _whatsappContatoController.text.trim();
      agendamentoConfig['esconderValores'] = _esconderValores;
       agendamentoConfig['modoSolicitacao'] = _modoSolicitacao;
      agendamentoConfig['permitirEscolhaProfissional'] = _permitirEscolhaProfissional;
      agendamentoConfig['enviarValorWhatsApp'] = _enviarValorWhatsApp;
      agendamentoConfig['horarioAbertura'] = '${_horarioAbertura.hour.toString().padLeft(2, '0')}:${_horarioAbertura.minute.toString().padLeft(2, '0')}';
      agendamentoConfig['horarioFechamento'] = '${_horarioFechamento.hour.toString().padLeft(2, '0')}:${_horarioFechamento.minute.toString().padLeft(2, '0')}';
      agendamentoConfig['intervaloSlots'] = _intervaloSlots;
      
      novasConfigs['agendamento'] = agendamentoConfig;
      novasConfigs['bairrosTaxiDogV2'] = _bairrosConfig;
      novasConfigs['bairrosTaxiDog'] = _bairrosConfig.map((e) => e['bairro']).toList();

      final novaEmpresa = empresa.copyWith(configuracoes: novasConfigs);
      
      try {
        final authService = Provider.of<AuthService>(context, listen: false);
        
        // 1. Atualizar no AuthService (IMPORTANTE: Garante localStorage + Firebase)
        await authService.atualizarEmpresa(novaEmpresa);
        
        // 2. Sincronizar com DataService para manter UI consistente
        dataService.setEmpresaAtual(novaEmpresa);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Configurações salvas com sucesso!'), backgroundColor: Colors.green),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erro ao salvar: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
    setState(() => _isLoading = false);
  }

  void _adicionarBairro() {
    final nome = _novoBairroController.text.trim();
    final taxa = double.tryParse(_taxaController.text.replaceAll(',', '.')) ?? 0.0;
    final taxaBusca = double.tryParse(_taxaBuscaController.text.replaceAll(',', '.')) ?? 0.0;
    final taxaSoleva = double.tryParse(_taxaSolevaController.text.replaceAll(',', '.')) ?? 0.0;

    if (nome.isNotEmpty) {
      setState(() {
        // Verificar se já existe (case-insensitive)
        final index = _bairrosConfig.indexWhere(
          (element) => element['bairro'].toString().toLowerCase() == nome.toLowerCase()
        );

        if (index != -1) {
          // Atualizar existente
          _bairrosConfig[index] = {
            'bairro': nome, // Mantém o nome digitado agora (pode mudar o casing)
            'taxa': taxa,
            'taxaBusca': taxaBusca,
            'taxaSoleva': taxaSoleva,
          };
        } else {
          // Adicionar novo
          _bairrosConfig.add({
            'bairro': nome, 
            'taxa': taxa,
            'taxaBusca': taxaBusca,
            'taxaSoleva': taxaSoleva,
          });
        }
        
        _novoBairroController.clear();
        _taxaController.clear();
        _taxaBuscaController.clear();
        _taxaSolevaController.clear();
      });
    }
  }

  void _removerBairro(int index) {
    setState(() {
      _bairrosConfig.removeAt(index);
    });
  }

  Future<void> _adicionarHorarioIndisponivel() async {
    // 1. Selecionar o tipo de bloqueio
    final opcao = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Tipo de Bloqueio', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Escolha como deseja bloquear:', style: TextStyle(color: Colors.white60, fontSize: 13)),
            const SizedBox(height: 16),
            _buildOpcaoBloqueio(ctx, 'todos', Icons.all_inclusive, 'Todos os dias', 'Ex: almoço, intervalo fixo'),
            _buildOpcaoBloqueio(ctx, 'dia', Icons.today, 'Dia específico', 'Bloquear uma data única'),
            _buildOpcaoBloqueio(ctx, 'periodo', Icons.date_range, 'Período (de-até)', 'Bloquear vários dias seguidos'),
            _buildOpcaoBloqueio(ctx, 'diaSemana', Icons.view_week, 'Dias da semana', 'Ex: toda segunda e terça'),
          ],
        ),
      ),
    );

    if (opcao == null) return;

    // 2. Coletar dados específicos de cada tipo
    Map<String, dynamic> dadosBloqueio = {'tipo': opcao};

    if (opcao == 'dia') {
      final DateTime? data = await _selecionarData('SELECIONE O DIA PARA BLOQUEAR');
      if (data == null) return;
      dadosBloqueio['data'] = _formatarDataStr(data);
    } else if (opcao == 'periodo') {
      final DateTime? dataInicio = await _selecionarData('DATA DE INÍCIO DO BLOQUEIO');
      if (dataInicio == null) return;
      final DateTime? dataFim = await _selecionarData('DATA DE TÉRMINO DO BLOQUEIO', firstDate: dataInicio);
      if (dataFim == null) return;
      if (dataFim.isBefore(dataInicio)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('A data final deve ser após a data inicial.'), backgroundColor: Colors.orange),
          );
        }
        return;
      }
      dadosBloqueio['dataInicio'] = _formatarDataStr(dataInicio);
      dadosBloqueio['dataFim'] = _formatarDataStr(dataFim);
    } else if (opcao == 'diaSemana') {
      final diasSelecionados = await _selecionarDiasSemana();
      if (diasSelecionados == null || diasSelecionados.isEmpty) return;
      dadosBloqueio['diasSemana'] = diasSelecionados;
    }

    // 3. Selecionar horário de início
    final TimeOfDay? inicio = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 12, minute: 0),
      helpText: 'HORÁRIO DE INÍCIO',
    );
    if (inicio == null) return;

    // 4. Selecionar horário de término
    final TimeOfDay? fim = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: inicio.hour + 1, minute: inicio.minute),
      helpText: 'HORÁRIO DE TÉRMINO',
    );
    if (fim == null) return;

    final double inicioDouble = inicio.hour + inicio.minute / 60.0;
    final double fimDouble = fim.hour + fim.minute / 60.0;
    if (fimDouble <= inicioDouble) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('O horário de término deve ser após o início.'), backgroundColor: Colors.orange),
        );
      }
      return;
    }

    dadosBloqueio['inicio'] = '${inicio.hour.toString().padLeft(2, '0')}:${inicio.minute.toString().padLeft(2, '0')}';
    dadosBloqueio['fim'] = '${fim.hour.toString().padLeft(2, '0')}:${fim.minute.toString().padLeft(2, '0')}';

    setState(() {
      _horariosIndisponiveis.add(dadosBloqueio);
      _horariosIndisponiveis.sort((a, b) {
        final tipoOrdem = {'todos': 0, 'diaSemana': 1, 'periodo': 2, 'dia': 3};
        final ta = tipoOrdem[a['tipo'] ?? 'todos'] ?? 0;
        final tb = tipoOrdem[b['tipo'] ?? 'todos'] ?? 0;
        if (ta != tb) return ta.compareTo(tb);
        return a['inicio'].toString().compareTo(b['inicio'].toString());
      });
    });
  }

  Widget _buildOpcaoBloqueio(BuildContext ctx, String valor, IconData icon, String titulo, String subtitulo) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => Navigator.pop(ctx, valor),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
          ),
          child: Row(
            children: [
              Icon(icon, color: Colors.orangeAccent, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(titulo, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                    Text(subtitulo, style: const TextStyle(color: Colors.white54, fontSize: 11)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.white30, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  Future<DateTime?> _selecionarData(String helpText, {DateTime? firstDate}) async {
    return showDatePicker(
      context: context,
      initialDate: firstDate ?? DateTime.now(),
      firstDate: firstDate ?? DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      helpText: helpText,
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Colors.orangeAccent,
              onPrimary: Colors.white,
              surface: Color(0xFF1E293B),
              onSurface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );
  }

  String _formatarDataStr(DateTime data) {
    return '${data.year}-${data.month.toString().padLeft(2, '0')}-${data.day.toString().padLeft(2, '0')}';
  }

  String _formatarDataExibicao(String dataStr) {
    return dataStr.split('-').reversed.join('/');
  }

  static const _nomesDiaSemana = {
    1: 'Segunda',
    2: 'Terça',
    3: 'Quarta',
    4: 'Quinta',
    5: 'Sexta',
    6: 'Sábado',
    7: 'Domingo',
  };

  Future<List<int>?> _selecionarDiasSemana() async {
    final selecionados = <int>{};
    return showDialog<List<int>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Dias da Semana', style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Selecione os dias para bloquear:', style: TextStyle(color: Colors.white60, fontSize: 13)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _nomesDiaSemana.entries.map((e) {
                  final isSel = selecionados.contains(e.key);
                  return FilterChip(
                    label: Text(e.value, style: TextStyle(color: isSel ? Colors.white : Colors.white70, fontSize: 13)),
                    selected: isSel,
                    selectedColor: Colors.orangeAccent,
                    backgroundColor: Colors.white.withOpacity(0.05),
                    checkmarkColor: Colors.white,
                    onSelected: (v) {
                      setDialogState(() {
                        if (v) { selecionados.add(e.key); } else { selecionados.remove(e.key); }
                      });
                    },
                  );
                }).toList(),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              onPressed: selecionados.isEmpty ? null : () => Navigator.pop(ctx, selecionados.toList()..sort()),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orangeAccent),
              child: const Text('Confirmar', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  String _descricaoBloqueio(Map<String, dynamic> item) {
    final tipo = item['tipo']?.toString() ?? 'todos';
    switch (tipo) {
      case 'dia':
        return '📅 ${_formatarDataExibicao(item['data'].toString())}';
      case 'periodo':
        return '📅 ${_formatarDataExibicao(item['dataInicio'].toString())} até ${_formatarDataExibicao(item['dataFim'].toString())}';
      case 'diaSemana':
        final dias = (item['diasSemana'] as List<dynamic>).map((d) => _nomesDiaSemana[d] ?? '?').join(', ');
        return '🔄 $dias';
      default:
        // Compatibilidade: bloqueios antigos sem 'tipo' mas com 'data'
        if (item['data'] != null) {
          return '📅 ${_formatarDataExibicao(item['data'].toString())}';
        }
        return '🔄 Todos os dias';
    }
  }

  void _removerHorario(int index) {
    setState(() {
      _horariosIndisponiveis.removeAt(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: const Text('Configurações de Agendamento'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          if (_isLoading)
            const Center(child: Padding(padding: EdgeInsets.all(16.0), child: CircularProgressIndicator(strokeWidth: 2)))
          else
            IconButton(
              icon: const Icon(Icons.save, color: Colors.greenAccent),
              onPressed: _salvarConfiguracoes,
              tooltip: 'Salvar Alterações',
            ),
          const SyncStatusWidget(),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            const SizedBox(height: 32),
            _buildConfiguracoesGerais(),
            const SizedBox(height: 32),
            _buildFormNovoBairro(),
            const SizedBox(height: 32),
            const Text(
              'Bairros e Taxas Cadastradas',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            _buildListaBairros(),
            const SizedBox(height: 48),
            _buildHorariosIndisponiveisSection(),
            const SizedBox(height: 32),
            if (_bairrosConfig.isNotEmpty || _horariosIndisponiveis.isNotEmpty)
              ElevatedButton.icon(
                onPressed: _isLoading ? null : _salvarConfiguracoes,
                icon: _isLoading 
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.check_circle_outline),
                label: Text(_isLoading ? 'Salvando...' : 'Salvar Todas as Configurações'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 8,
                  shadowColor: Colors.green.withOpacity(0.5),
                ),
              ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildHorariosIndisponiveisSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.orangeAccent.withOpacity(0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.orangeAccent.withOpacity(0.2)),
          ),
          child: Row(
            children: [
              const Icon(Icons.block_flipped, color: Colors.orangeAccent, size: 32),
              const SizedBox(width: 16),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Horários Indisponíveis',
                      style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Defina intervalos de tempo onde agendamentos não serão permitidos (ex: almoço).',
                      style: TextStyle(color: Colors.white60, fontSize: 13),
                    ),
                  ],
                ),
              ),
              ElevatedButton(
                onPressed: _adicionarHorarioIndisponivel,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orangeAccent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Bloquear Horário'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (_horariosIndisponiveis.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(40.0),
              child: Column(
                children: [
                  Icon(Icons.event_available, size: 48, color: Colors.white.withOpacity(0.1)),
                  const SizedBox(height: 16),
                  const Text('Todos os horários estão liberados.', style: TextStyle(color: Colors.white24)),
                ],
              ),
            ),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _horariosIndisponiveis.length,
            itemBuilder: (context, index) {
              final item = _horariosIndisponiveis[index];
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.03),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withOpacity(0.05)),
                ),
                child: ListTile(
                  leading: const Icon(Icons.timer_off_outlined, color: Colors.orangeAccent),
                  title: Text(
                    'Das ${item['inicio']} às ${item['fim']}',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    '${_descricaoBloqueio(item)} — Indisponível',
                    style: TextStyle(
                      color: (item['tipo'] ?? 'todos') == 'todos' && item['data'] == null 
                        ? Colors.white54 
                        : Colors.orangeAccent.withOpacity(0.8), 
                      fontSize: 12,
                    ),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                    onPressed: () => _removerHorario(index),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.blueAccent.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.blueAccent.withOpacity(0.2)),
      ),
      child: const Row(
        children: [
          Icon(Icons.local_shipping_rounded, color: Colors.blueAccent, size: 32),
          SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Taxas de Taxi Dog',
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 4),
                Text(
                  'Configure o valor cobrado para cada bairro atendido pelo Taxi Dog.',
                  style: TextStyle(color: Colors.white60, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormNovoBairro() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _novoBairroController,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: 'Nome do Bairro',
              labelStyle: const TextStyle(color: Colors.white60),
              hintText: 'Ex: Centro',
              prefixIcon: const Icon(Icons.location_on, color: Colors.white30),
              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white12)),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _taxaController,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Leva e Traz (R\$)',
                    labelStyle: const TextStyle(color: Colors.white60, fontSize: 12),
                    hintText: '0,00',
                    prefixIcon: const Icon(Icons.swap_horiz, color: Colors.white30, size: 18),
                    enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white12)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _taxaBuscaController,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Só Busca (R\$)',
                    labelStyle: const TextStyle(color: Colors.white60, fontSize: 12),
                    hintText: '0,00',
                    prefixIcon: const Icon(Icons.arrow_downward, color: Colors.white30, size: 18),
                    enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white12)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _taxaSolevaController,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Só Leva (R\$)',
                    labelStyle: const TextStyle(color: Colors.white60, fontSize: 12),
                    hintText: '0,00',
                    prefixIcon: const Icon(Icons.arrow_upward, color: Colors.white30, size: 18),
                    enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white12)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _novoBairroController,
            builder: (context, value, child) {
              final nome = value.text.trim().toLowerCase();
              final jaExiste = _bairrosConfig.any((b) => b['bairro'].toString().toLowerCase() == nome);
              
              return ElevatedButton.icon(
                onPressed: _adicionarBairro,
                icon: Icon(jaExiste ? Icons.edit : Icons.add),
                label: Text(jaExiste ? 'Atualizar Bairro Existente' : 'Adicionar Novo Bairro'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: jaExiste ? Colors.orangeAccent : Colors.blueAccent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildListaBairros() {
    if (_bairrosConfig.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40.0),
          child: Column(
            children: [
              Icon(Icons.map_outlined, size: 48, color: Colors.white.withOpacity(0.1)),
              const SizedBox(height: 16),
              const Text('Nenhum bairro cadastrado ainda.', style: TextStyle(color: Colors.white24)),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _bairrosConfig.length,
      itemBuilder: (context, index) {
        final item = _bairrosConfig[index];
        final double taxa = (item['taxa'] as num?)?.toDouble() ?? 0.0;
        final double taxaBusca = (item['taxaBusca'] as num?)?.toDouble() ?? 0.0;
        final double taxaSoleva = (item['taxaSoleva'] as num?)?.toDouble() ?? 0.0;
        
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.03),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.05)),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            leading: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), shape: BoxShape.circle),
              child: const Icon(Icons.location_city_rounded, color: Colors.white70, size: 20),
            ),
            title: Text(item['bairro'] ?? '', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Row(
                  children: [
                    _buildMiniBadge('Leva/Traz: R\$ ${taxa.toStringAsFixed(2)}', Colors.greenAccent),
                    const SizedBox(width: 8),
                    _buildMiniBadge('Busca: R\$ ${taxaBusca.toStringAsFixed(2)}', Colors.orangeAccent),
                    const SizedBox(width: 8),
                    _buildMiniBadge('Leva: R\$ ${taxaSoleva.toStringAsFixed(2)}', Colors.blueAccent),
                  ],
                ),
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit_outlined, color: Colors.blueAccent, size: 20),
                  onPressed: () {
                    setState(() {
                      _novoBairroController.text = item['bairro'] ?? '';
                      _taxaController.text = taxa.toStringAsFixed(2).replaceAll('.', ',');
                      _taxaBuscaController.text = taxaBusca.toStringAsFixed(2).replaceAll('.', ',');
                      _taxaSolevaController.text = taxaSoleva.toStringAsFixed(2).replaceAll('.', ',');
                    });
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                  onPressed: () => _removerBairro(index),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMiniBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        text,
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildConfiguracoesGerais() {
    return Column(
      children: [
        // WhatsApp de Contato
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.chat_bubble_outline, color: Colors.greenAccent, size: 24),
                  const SizedBox(width: 12),
                  const Text(
                    'WhatsApp / Contato da Loja',
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Número para onde serão enviadas as notificações.',
                style: TextStyle(color: Colors.white60, fontSize: 12),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _whatsappContatoController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Número do WhatsApp (com DDD)',
                  labelStyle: const TextStyle(color: Colors.white60),
                  hintText: 'Ex: 11999999999',
                  prefixIcon: const Icon(Icons.phone, color: Colors.white30),
                  enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white12)),
                ),
                keyboardType: TextInputType.phone,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Esconder Valores
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.money_off, color: Colors.orangeAccent, size: 24),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Esconder Valores dos Serviços',
                      style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                  Switch(
                    value: _esconderValores,
                    onChanged: (v) => setState(() => _esconderValores = v),
                    activeColor: Colors.greenAccent,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Se ativado, os clientes não verão o preço dos serviços durante o agendamento.',
                style: TextStyle(color: Colors.white60, fontSize: 12),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Enviar Valor no WhatsApp
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                   Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(color: Colors.green.withOpacity(0.2), shape: BoxShape.circle),
                    child: const Icon(Icons.chat_bubble_outline, color: Colors.greenAccent, size: 20),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Enviar Valor no WhatsApp ao Copiar',
                      style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                  Switch(
                    value: _enviarValorWhatsApp,
                    onChanged: (v) => setState(() => _enviarValorWhatsApp = v),
                    activeColor: Colors.greenAccent,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Se desativado, o valor dos serviços não será incluído no texto copiado para o WhatsApp.',
                style: TextStyle(color: Colors.white60, fontSize: 12),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Modo Solicitação
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: _modoSolicitacao ? Colors.amber.withOpacity(0.08) : Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(20),
            border: _modoSolicitacao ? Border.all(color: Colors.amber.withOpacity(0.3)) : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(_modoSolicitacao ? Icons.mail_outline_rounded : Icons.calendar_view_day_rounded, color: Colors.amber, size: 24),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Modo Solicitação (Sem Agenda Visível)',
                      style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                  Switch(
                    value: _modoSolicitacao,
                    onChanged: (v) => setState(() => _modoSolicitacao = v),
                    activeColor: Colors.amber,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _modoSolicitacao
                    ? '✅ ATIVO — O cliente escolhe data e hora livremente, sem ver a disponibilidade. Você confirma cada solicitação manualmente.'
                    : '❌ DESATIVADO — O cliente vê os horários disponíveis na agenda inteligente e agenda diretamente.',
                style: TextStyle(
                  color: _modoSolicitacao ? Colors.amber[200] : Colors.white60,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Permitir Escolha de Profissional
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.person_search, color: Colors.blueAccent, size: 24),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Permitir Escolha de Profissional no Agendamento Online',
                      style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                  Switch(
                    value: _permitirEscolhaProfissional,
                    onChanged: (v) => setState(() => _permitirEscolhaProfissional = v),
                    activeColor: Colors.blueAccent,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Se ativado, os clientes poderão selecionar o profissional de sua preferência durante o agendamento online.',
                style: TextStyle(color: Colors.white60, fontSize: 12),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Horário de Atendimento
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.access_time_filled, color: Colors.blueAccent, size: 24),
                  const SizedBox(width: 12),
                  const Text(
                    'Horário de Atendimento',
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Defina o intervalo em que a loja aceita agendamentos online.',
                style: TextStyle(color: Colors.white60, fontSize: 12),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: _buildTimePickerTile(
                      label: 'Abertura',
                      time: _horarioAbertura,
                      onTap: () async {
                        final picked = await showTimePicker(context: context, initialTime: _horarioAbertura);
                        if (picked != null) setState(() => _horarioAbertura = picked);
                      },
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildTimePickerTile(
                      label: 'Fechamento',
                      time: _horarioFechamento,
                      onTap: () async {
                        final picked = await showTimePicker(context: context, initialTime: _horarioFechamento);
                        if (picked != null) setState(() => _horarioFechamento = picked);
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Intervalo entre Slots
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                   Icon(Icons.grid_view_rounded, color: Colors.purpleAccent, size: 24),
                  const SizedBox(width: 12),
                  const Text(
                    'Intervalo de Horários na Agenda',
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Define de quanto em quanto tempo os horários aparecem para o cliente.',
                style: TextStyle(color: Colors.white60, fontSize: 12),
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.03),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withOpacity(0.08)),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    value: _intervaloSlots,
                    dropdownColor: const Color(0xFF1E293B),
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    isExpanded: true,
                    items: [10, 15, 20, 30, 45, 60]
                      .map((val) => DropdownMenuItem(
                        value: val,
                        child: Text('$val Minutos'),
                      ))
                      .toList(),
                    onChanged: (val) {
                      if (val != null) setState(() => _intervaloSlots = val);
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTimePickerTile({required String label, required TimeOfDay time, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.03),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: Colors.white60, fontSize: 11)),
            const SizedBox(height: 4),
            Text(
              '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }
}
