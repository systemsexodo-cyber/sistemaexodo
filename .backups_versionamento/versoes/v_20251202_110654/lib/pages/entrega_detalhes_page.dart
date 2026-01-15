import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/entrega.dart';
import '../services/data_service.dart';
import '../theme.dart';

class EntregaDetalhesPage extends StatefulWidget {
  final Entrega? entrega;

  const EntregaDetalhesPage({super.key, this.entrega});

  @override
  State<EntregaDetalhesPage> createState() => _EntregaDetalhesPageState();
}

class _EntregaDetalhesPageState extends State<EntregaDetalhesPage> {
  late TextEditingController _clienteController;
  late TextEditingController _telefoneController;
  late TextEditingController _enderecoController;
  late TextEditingController _complementoController;
  late TextEditingController _bairroController;
  late TextEditingController _cidadeController;
  late TextEditingController _cepController;
  late TextEditingController _referenciaController;
  late TextEditingController _observacoesController;
  late TextEditingController _volumesController;

  String? _tipoEntrega;
  String? _periodoEntrega;
  DateTime? _dataPrevisao;
  String? _motoristaId;

  final List<String> _tiposEntrega = ['Normal', 'Expressa', 'Agendada'];
  final List<String> _periodos = ['Manhã', 'Tarde', 'Noite', 'Qualquer'];

  @override
  void initState() {
    super.initState();
    final e = widget.entrega;
    _clienteController = TextEditingController(text: e?.clienteNome ?? '');
    _telefoneController = TextEditingController(text: e?.clienteTelefone ?? '');
    _enderecoController = TextEditingController(text: e?.enderecoEntrega ?? '');
    _complementoController = TextEditingController(text: e?.complemento ?? '');
    _bairroController = TextEditingController(text: e?.bairro ?? '');
    _cidadeController = TextEditingController(text: e?.cidade ?? '');
    _cepController = TextEditingController(text: e?.cep ?? '');
    _referenciaController = TextEditingController(
      text: e?.pontoReferencia ?? '',
    );
    _observacoesController = TextEditingController(text: e?.observacoes ?? '');
    _volumesController = TextEditingController(
      text: e?.quantidadeVolumes.toString() ?? '1',
    );
    _tipoEntrega = e?.tipoEntrega ?? 'Normal';
    _periodoEntrega = e?.periodoEntrega ?? 'Qualquer';
    _dataPrevisao =
        e?.dataPrevisao ?? DateTime.now().add(const Duration(days: 1));
    _motoristaId = e?.motoristaId;
  }

  @override
  void dispose() {
    _clienteController.dispose();
    _telefoneController.dispose();
    _enderecoController.dispose();
    _complementoController.dispose();
    _bairroController.dispose();
    _cidadeController.dispose();
    _cepController.dispose();
    _referenciaController.dispose();
    _observacoesController.dispose();
    _volumesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dataService = Provider.of<DataService>(context);
    final isEditing = widget.entrega != null;

    return AppTheme.appBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(isEditing ? 'Detalhes da Entrega' : 'Nova Entrega'),
          centerTitle: true,
          backgroundColor: Colors.transparent,
          elevation: 0,
          actions: [
            if (isEditing)
              IconButton(
                icon: const Icon(Icons.delete, color: Colors.redAccent),
                onPressed: () => _confirmarExclusao(context, dataService),
              ),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Se editando, mostrar status e histórico
              if (isEditing) ...[
                _buildStatusSection(dataService),
                const SizedBox(height: 24),
              ],

              // Dados do destinatário
              _buildSection('Destinatário', Icons.person, Colors.blue, [
                _buildTextField(
                  controller: _clienteController,
                  label: 'Nome do Cliente',
                  icon: Icons.person_outline,
                  required: true,
                ),
                const SizedBox(height: 12),
                _buildTextField(
                  controller: _telefoneController,
                  label: 'Telefone',
                  icon: Icons.phone,
                  keyboardType: TextInputType.phone,
                ),
              ]),

              const SizedBox(height: 20),

              // Endereço
              _buildSection(
                'Endereço de Entrega',
                Icons.location_on,
                Colors.green,
                [
                  _buildTextField(
                    controller: _enderecoController,
                    label: 'Endereço',
                    icon: Icons.home,
                    required: true,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: _buildTextField(
                          controller: _complementoController,
                          label: 'Complemento',
                          icon: Icons.apartment,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildTextField(
                          controller: _cepController,
                          label: 'CEP',
                          icon: Icons.pin_drop,
                          keyboardType: TextInputType.number,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _buildTextField(
                          controller: _bairroController,
                          label: 'Bairro',
                          icon: Icons.location_city,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildTextField(
                          controller: _cidadeController,
                          label: 'Cidade',
                          icon: Icons.location_city,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildTextField(
                    controller: _referenciaController,
                    label: 'Ponto de Referência',
                    icon: Icons.flag,
                    maxLines: 2,
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // Configurações da entrega
              _buildSection('Configurações', Icons.settings, Colors.orange, [
                // Tipo de entrega
                Row(
                  children: [
                    Expanded(
                      child: _buildDropdown(
                        label: 'Tipo de Entrega',
                        value: _tipoEntrega,
                        items: _tiposEntrega,
                        onChanged: (v) => setState(() => _tipoEntrega = v),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildDropdown(
                        label: 'Período',
                        value: _periodoEntrega,
                        items: _periodos,
                        onChanged: (v) => setState(() => _periodoEntrega = v),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _buildDatePicker(
                        label: 'Data Prevista',
                        value: _dataPrevisao,
                        onChanged: (d) => setState(() => _dataPrevisao = d),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildTextField(
                        controller: _volumesController,
                        label: 'Volumes',
                        icon: Icons.inventory,
                        keyboardType: TextInputType.number,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildMotoristaSelector(dataService),
              ]),

              const SizedBox(height: 20),

              // Observações
              _buildSection('Observações', Icons.notes, Colors.purple, [
                _buildTextField(
                  controller: _observacoesController,
                  label: 'Observações da entrega',
                  icon: Icons.note_add,
                  maxLines: 3,
                ),
              ]),

              // Histórico de eventos (se editando)
              if (isEditing && widget.entrega!.historico.isNotEmpty) ...[
                const SizedBox(height: 20),
                _buildHistoricoSection(),
              ],

              const SizedBox(height: 100),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _salvar(dataService),
          backgroundColor: Colors.green,
          icon: const Icon(Icons.save),
          label: Text(isEditing ? 'Salvar Alterações' : 'Criar Entrega'),
        ),
      ),
    );
  }

  Widget _buildSection(
    String titulo,
    IconData icone,
    Color cor,
    List<Widget> children,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cor.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icone, color: cor, size: 20),
              const SizedBox(width: 8),
              Text(
                titulo,
                style: TextStyle(
                  color: cor,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }

  Widget _buildStatusSection(DataService dataService) {
    final entrega = widget.entrega!;
    final corStatus = _getCorStatus(entrega.status);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [corStatus.withOpacity(0.3), corStatus.withOpacity(0.1)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: corStatus.withOpacity(0.5)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: corStatus.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  _getIconeStatus(entrega.status),
                  color: corStatus,
                  size: 32,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entrega.pedidoNumero ?? 'Entrega Avulsa',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: corStatus,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        entrega.status.nome,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (entrega.estaAtrasada)
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Column(
                    children: [
                      Icon(Icons.warning, color: Colors.white, size: 20),
                      Text(
                        'ATRASADA',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          // Botões de ação rápida
          _buildAcoesRapidas(entrega, dataService),
        ],
      ),
    );
  }

  Widget _buildAcoesRapidas(Entrega entrega, DataService dataService) {
    final proximosStatus = StatusEntrega.values
        .where((s) => entrega.podeAlterarPara(s))
        .toList();

    if (proximosStatus.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.black26,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              entrega.status == StatusEntrega.entregue
                  ? Icons.check_circle
                  : Icons.block,
              color: Colors.white54,
            ),
            const SizedBox(width: 8),
            Text(
              entrega.status == StatusEntrega.entregue
                  ? 'Entrega concluída com sucesso!'
                  : 'Status final - não pode ser alterado',
              style: const TextStyle(color: Colors.white54),
            ),
          ],
        ),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: proximosStatus.map((status) {
        final cor = _getCorStatus(status);
        return ElevatedButton.icon(
          onPressed: () => _alterarStatus(entrega, status, dataService),
          icon: Icon(_getIconeStatus(status), size: 18),
          label: Text(status.nome),
          style: ElevatedButton.styleFrom(
            backgroundColor: cor,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }).toList(),
    );
  }

  void _alterarStatus(
    Entrega entrega,
    StatusEntrega novoStatus,
    DataService dataService,
  ) {
    // Se for marcar como entregue, pedir confirmação de recebimento
    if (novoStatus == StatusEntrega.entregue) {
      _confirmarEntrega(entrega, dataService);
      return;
    }

    // Alteração direta
    final evento = EventoEntrega(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      dataHora: DateTime.now(),
      status: novoStatus,
      descricao: 'Status alterado para ${novoStatus.nome}',
    );

    final entregaAtualizada = entrega.adicionarEvento(evento);
    dataService.updateEntrega(entregaAtualizada);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Status alterado para ${novoStatus.nome}'),
        backgroundColor: _getCorStatus(novoStatus),
      ),
    );

    setState(() {});
  }

  void _confirmarEntrega(Entrega entrega, DataService dataService) {
    final nomeController = TextEditingController();
    final documentoController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.done_all, color: Colors.green),
            SizedBox(width: 10),
            Text('Confirmar Entrega', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nomeController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Nome de quem recebeu',
                labelStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
                prefixIcon: const Icon(Icons.person, color: Colors.white54),
                filled: true,
                fillColor: Colors.black26,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: documentoController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Documento (opcional)',
                labelStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
                prefixIcon: const Icon(Icons.badge, color: Colors.white54),
                filled: true,
                fillColor: Colors.black26,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Cancelar',
              style: TextStyle(color: Colors.white54),
            ),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context);

              final evento = EventoEntrega(
                id: DateTime.now().millisecondsSinceEpoch.toString(),
                dataHora: DateTime.now(),
                status: StatusEntrega.entregue,
                descricao:
                    'Entregue para: ${nomeController.text.isNotEmpty ? nomeController.text : "Não informado"}',
              );

              final entregaAtualizada = entrega
                  .adicionarEvento(evento)
                  .copyWith(
                    dataEntrega: DateTime.now(),
                    nomeRecebedor: nomeController.text.isNotEmpty
                        ? nomeController.text
                        : null,
                    documentoRecebedor: documentoController.text.isNotEmpty
                        ? documentoController.text
                        : null,
                  );

              dataService.updateEntrega(entregaAtualizada);

              ScaffoldMessenger.of(this.context).showSnackBar(
                const SnackBar(
                  content: Row(
                    children: [
                      Icon(Icons.check_circle, color: Colors.white),
                      SizedBox(width: 10),
                      Text('Entrega confirmada com sucesso!'),
                    ],
                  ),
                  backgroundColor: Colors.green,
                ),
              );

              setState(() {});
            },
            icon: const Icon(Icons.check),
            label: const Text('Confirmar Entrega'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
          ),
        ],
      ),
    );
  }

  void _registrarFalha(Entrega entrega, DataService dataService) {
    final motivoController = TextEditingController();
    final motivos = [
      'Endereço não encontrado',
      'Cliente ausente',
      'Recusou recebimento',
      'Endereço incorreto',
      'Estabelecimento fechado',
      'Outro',
    ];

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          String? motivoSelecionado;

          return AlertDialog(
            backgroundColor: const Color(0xFF1E1E2E),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: const Row(
              children: [
                Icon(Icons.warning, color: Colors.orange),
                SizedBox(width: 10),
                Text('Registrar Falha', style: TextStyle(color: Colors.white)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Selecione o motivo:',
                  style: TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: motivos.map((m) {
                    final selecionado = motivoSelecionado == m;
                    return ChoiceChip(
                      label: Text(m),
                      selected: selecionado,
                      onSelected: (s) {
                        setDialogState(() {
                          motivoSelecionado = s ? m : null;
                          if (m != 'Outro') {
                            motivoController.text = m;
                          } else {
                            motivoController.clear();
                          }
                        });
                      },
                      selectedColor: Colors.orange,
                      backgroundColor: Colors.white12,
                      labelStyle: TextStyle(
                        color: selecionado ? Colors.white : Colors.white70,
                      ),
                    );
                  }).toList(),
                ),
                if (motivoSelecionado == 'Outro') ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: motivoController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Descreva o motivo...',
                      hintStyle: TextStyle(
                        color: Colors.white.withOpacity(0.5),
                      ),
                      filled: true,
                      fillColor: Colors.black26,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    maxLines: 2,
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  'Cancelar',
                  style: TextStyle(color: Colors.white54),
                ),
              ),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context);

                  final evento = EventoEntrega(
                    id: DateTime.now().millisecondsSinceEpoch.toString(),
                    dataHora: DateTime.now(),
                    status: StatusEntrega.aguardando,
                    descricao: 'Tentativa falhou: ${motivoController.text}',
                  );

                  final entregaAtualizada = entrega
                      .adicionarEvento(evento)
                      .copyWith(motivoFalha: motivoController.text);

                  dataService.updateEntrega(entregaAtualizada);

                  ScaffoldMessenger.of(this.context).showSnackBar(
                    const SnackBar(
                      content: Text('Falha registrada'),
                      backgroundColor: Colors.orange,
                    ),
                  );

                  setState(() {});
                },
                icon: const Icon(Icons.save),
                label: const Text('Registrar'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHistoricoSection() {
    final historico = widget.entrega!.historico.reversed.toList();

    return _buildSection('Histórico', Icons.history, Colors.teal, [
      ...historico.asMap().entries.map((entry) {
        final index = entry.key;
        final evento = entry.value;
        final isLast = index == historico.length - 1;

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: _getCorStatus(evento.status),
                    shape: BoxShape.circle,
                  ),
                ),
                if (!isLast)
                  Container(width: 2, height: 50, color: Colors.white24),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          evento.status.nome,
                          style: TextStyle(
                            color: _getCorStatus(evento.status),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          _formatarDataHora(evento.dataHora),
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.5),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                    if (evento.descricao != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        evento.descricao!,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.7),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        );
      }),
    ]);
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    IconData? icon,
    bool required = false,
    int maxLines = 1,
    TextInputType? keyboardType,
  }) {
    return TextField(
      controller: controller,
      style: const TextStyle(color: Colors.white),
      maxLines: maxLines,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: required ? '$label *' : label,
        labelStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
        prefixIcon: icon != null ? Icon(icon, color: Colors.white54) : null,
        filled: true,
        fillColor: Colors.black26,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.greenAccent),
        ),
      ),
    );
  }

  Widget _buildDropdown({
    required String label,
    required String? value,
    required List<String> items,
    required Function(String?) onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(12),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          dropdownColor: const Color(0xFF2C3E50),
          hint: Text(
            label,
            style: TextStyle(color: Colors.white.withOpacity(0.5)),
          ),
          style: const TextStyle(color: Colors.white),
          items: items
              .map((item) => DropdownMenuItem(value: item, child: Text(item)))
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildDatePicker({
    required String label,
    required DateTime? value,
    required Function(DateTime?) onChanged,
  }) {
    return InkWell(
      onTap: () async {
        final data = await showDatePicker(
          context: context,
          initialDate: value ?? DateTime.now(),
          firstDate: DateTime.now(),
          lastDate: DateTime.now().add(const Duration(days: 365)),
          builder: (context, child) {
            return Theme(
              data: Theme.of(context).copyWith(
                colorScheme: const ColorScheme.dark(
                  primary: Colors.greenAccent,
                  surface: Color(0xFF1E1E2E),
                ),
              ),
              child: child!,
            );
          },
        );
        if (data != null) onChanged(data);
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.black26,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(Icons.calendar_today, color: Colors.white54, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                value != null
                    ? '${value.day}/${value.month}/${value.year}'
                    : label,
                style: TextStyle(
                  color: value != null ? Colors.white : Colors.white54,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMotoristaSelector(DataService dataService) {
    final motoristas = dataService.motoristas;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(12),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _motoristaId,
          isExpanded: true,
          dropdownColor: const Color(0xFF2C3E50),
          hint: Text(
            'Selecionar Motorista',
            style: TextStyle(color: Colors.white.withOpacity(0.5)),
          ),
          style: const TextStyle(color: Colors.white),
          items: [
            const DropdownMenuItem(value: null, child: Text('Não atribuído')),
            ...motoristas.map(
              (m) => DropdownMenuItem(
                value: m.id,
                child: Row(
                  children: [
                    const Icon(Icons.person, color: Colors.blue, size: 18),
                    const SizedBox(width: 8),
                    Text(m.nome),
                    if (m.veiculoPlaca != null) ...[
                      const SizedBox(width: 8),
                      Text(
                        '(${m.veiculoPlaca})',
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
          onChanged: (v) => setState(() => _motoristaId = v),
        ),
      ),
    );
  }

  void _salvar(DataService dataService) {
    if (_clienteController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Informe o nome do cliente'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_enderecoController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Informe o endereço de entrega'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final motorista = _motoristaId != null
        ? dataService.motoristas.firstWhere(
            (m) => m.id == _motoristaId,
            orElse: () => Motorista(
              id: '',
              nome: '',
              telefone: '',
              dataCadastro: DateTime.now(),
            ),
          )
        : null;

    final entrega = Entrega(
      id:
          widget.entrega?.id ??
          DateTime.now().millisecondsSinceEpoch.toString(),
      pedidoId: widget.entrega?.pedidoId ?? '',
      pedidoNumero: widget.entrega?.pedidoNumero,
      clienteNome: _clienteController.text,
      clienteTelefone: _telefoneController.text.isNotEmpty
          ? _telefoneController.text
          : null,
      enderecoEntrega: _enderecoController.text,
      complemento: _complementoController.text.isNotEmpty
          ? _complementoController.text
          : null,
      bairro: _bairroController.text.isNotEmpty ? _bairroController.text : null,
      cidade: _cidadeController.text.isNotEmpty ? _cidadeController.text : null,
      cep: _cepController.text.isNotEmpty ? _cepController.text : null,
      pontoReferencia: _referenciaController.text.isNotEmpty
          ? _referenciaController.text
          : null,
      status: widget.entrega?.status ?? StatusEntrega.aguardando,
      dataCriacao: widget.entrega?.dataCriacao ?? DateTime.now(),
      dataPrevisao: _dataPrevisao,
      dataEntrega: widget.entrega?.dataEntrega,
      motoristaId: _motoristaId,
      motoristaNome: motorista?.nome,
      motoristaTelefone: motorista?.telefone,
      veiculoPlaca: motorista?.veiculoPlaca,
      tipoEntrega: _tipoEntrega,
      periodoEntrega: _periodoEntrega,
      observacoes: _observacoesController.text.isNotEmpty
          ? _observacoesController.text
          : null,
      historico:
          widget.entrega?.historico ??
          [
            EventoEntrega(
              id: '1',
              dataHora: DateTime.now(),
              status: StatusEntrega.aguardando,
              descricao: 'Entrega criada',
            ),
          ],
      quantidadeVolumes: int.tryParse(_volumesController.text) ?? 1,
      nomeRecebedor: widget.entrega?.nomeRecebedor,
      documentoRecebedor: widget.entrega?.documentoRecebedor,
      motivoFalha: widget.entrega?.motivoFalha,
    );

    if (widget.entrega != null) {
      dataService.updateEntrega(entrega);
    } else {
      dataService.addEntrega(entrega);
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 10),
            Text(
              widget.entrega != null
                  ? 'Entrega atualizada!'
                  : 'Entrega criada!',
            ),
          ],
        ),
        backgroundColor: Colors.green,
      ),
    );

    Navigator.pop(context);
  }

  void _confirmarExclusao(BuildContext context, DataService dataService) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Excluir Entrega?',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Esta ação não pode ser desfeita.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              dataService.deleteEntrega(widget.entrega!.id);
              Navigator.pop(context);
              Navigator.pop(context);
              ScaffoldMessenger.of(this.context).showSnackBar(
                const SnackBar(
                  content: Text('Entrega excluída'),
                  backgroundColor: Colors.red,
                ),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
  }

  String _formatarDataHora(DateTime data) {
    return '${data.day.toString().padLeft(2, '0')}/${data.month.toString().padLeft(2, '0')} ${data.hour.toString().padLeft(2, '0')}:${data.minute.toString().padLeft(2, '0')}';
  }

  Color _getCorStatus(StatusEntrega status) {
    switch (status) {
      case StatusEntrega.aguardando:
        return Colors.orange;
      case StatusEntrega.entregue:
        return Colors.green;
    }
  }

  IconData _getIconeStatus(StatusEntrega status) {
    switch (status) {
      case StatusEntrega.aguardando:
        return Icons.hourglass_empty;
      case StatusEntrega.entregue:
        return Icons.done_all;
    }
  }
}
