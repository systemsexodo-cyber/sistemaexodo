import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/data_service.dart';
import '../models/servico.dart';
import '../models/cliente.dart';
import '../theme.dart';
import 'lancar_servico_page.dart';

class ServicosPage extends StatelessWidget {
  const ServicosPage({super.key});

  @override
  Widget build(BuildContext context) {
    final dataService = Provider.of<DataService>(context);
    final servicos = dataService.servicos;

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    
    return AppTheme.appBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Serviços'),
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: Colors.white,
          actions: [
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const LancarServicoPage(),
                  ),
                ).then((pedido) {
                  if (pedido != null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Serviço lançado com sucesso!'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                });
              },
            ),
          ],
        ),
        body: ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: servicos.length,
          separatorBuilder: (_, __) => const SizedBox(height: 16),
          itemBuilder: (context, index) {
            final servico = servicos[index];
            return Card(
              elevation: theme.cardTheme.elevation ?? 2,
              shape: theme.cardTheme.shape,
              color: theme.cardTheme.color,
              child: ListTile(
                title: Text(
                  servico.nome,
                  style: TextStyle(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                subtitle: Text(
                  servico.descricao ?? '',
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                trailing: IconButton(
                  icon: Icon(
                    Icons.edit,
                    color: colorScheme.primary,
                  ),
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (context) =>
                          _EditarServicoDialog(servico: servico),
                    );
                  },
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

// Modal de adicionar serviço
class _AdicionarServicoDialog extends StatefulWidget {
  @override
  State<_AdicionarServicoDialog> createState() =>
      _AdicionarServicoDialogState();
}

class _AdicionarServicoDialogState extends State<_AdicionarServicoDialog> {
  Servico? _servicoSelecionado;
  final _descricaoController = TextEditingController();
  final _valorController = TextEditingController();

  @override
  void dispose() {
    _descricaoController.dispose();
    _valorController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dataService = Provider.of<DataService>(context);
    final clientes = dataService.clientes;
    final servicosCadastrados = dataService.servicos;

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    
    return Dialog(
      backgroundColor: theme.dialogBackgroundColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Autocomplete<Cliente>(
                optionsBuilder: (TextEditingValue textEditingValue) {
                  if (textEditingValue.text.isEmpty) {
                    return clientes;
                  }
                  return clientes.where(
                    (Cliente c) => c.nome.toLowerCase().contains(
                      textEditingValue.text.toLowerCase(),
                    ),
                  );
                },
                displayStringForOption: (Cliente c) => c.nome,
                fieldViewBuilder:
                    (context, controller, focusNode, onFieldSubmitted) {
                      return TextFormField(
                        controller: controller,
                        focusNode: focusNode,
                        decoration: InputDecoration(
                          labelText: 'Cliente',
                          labelStyle: TextStyle(
                            color: colorScheme.onSurfaceVariant,
                          ),
                          filled: true,
                          fillColor: theme.inputDecorationTheme.fillColor,
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: colorScheme.outline,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: colorScheme.primary,
                            ),
                          ),
                        ),
                        style: TextStyle(
                          color: colorScheme.onSurface,
                        ),
                      );
                    },
                onSelected: (Cliente selection) {
                  setState(() {
                    // ação ao selecionar cliente (se necessário)
                  });
                },
              ),
              const SizedBox(height: 12),
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
                displayStringForOption: (Servico s) => s.nome,
                fieldViewBuilder:
                    (context, controller, focusNode, onFieldSubmitted) {
                      return TextFormField(
                        controller: controller,
                        focusNode: focusNode,
                        decoration: InputDecoration(
                          labelText: 'Serviço',
                          labelStyle: TextStyle(
                            color: colorScheme.onSurfaceVariant,
                          ),
                          filled: true,
                          fillColor: theme.inputDecorationTheme.fillColor,
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: colorScheme.outline,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: colorScheme.primary,
                            ),
                          ),
                        ),
                        style: TextStyle(
                          color: colorScheme.onSurface,
                        ),
                      );
                    },
                onSelected: (Servico selection) {
                  setState(() {
                    _servicoSelecionado = selection;
                    _valorController.text = selection.preco.toStringAsFixed(2);
                  });
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _descricaoController,
                style: TextStyle(
                  color: colorScheme.onSurface,
                ),
                decoration: InputDecoration(
                  labelText: 'Descrição',
                  labelStyle: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                  ),
                  filled: true,
                  fillColor: theme.inputDecorationTheme.fillColor,
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: colorScheme.outline,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: colorScheme.primary,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _valorController,
                keyboardType: TextInputType.number,
                style: TextStyle(
                  color: colorScheme.onSurface,
                ),
                decoration: InputDecoration(
                  labelText: 'Valor do Serviço',
                  labelStyle: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                  ),
                  filled: true,
                  fillColor: theme.inputDecorationTheme.fillColor,
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: colorScheme.outline,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: colorScheme.primary,
                    ),
                  ),
                ),
                readOnly: _servicoSelecionado != null,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  textStyle: const TextStyle(fontSize: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onPressed: () async {
                  // Aqui você pode salvar o serviço usando _clienteSelecionado e _servicoSelecionado
                  Navigator.of(context).pop();
                },
                child: const Text('Cadastrar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Modal de edição de serviço
class _EditarServicoDialog extends StatefulWidget {
  final Servico servico;
  const _EditarServicoDialog({required this.servico});

  @override
  State<_EditarServicoDialog> createState() => _EditarServicoDialogState();
}

class _EditarServicoDialogState extends State<_EditarServicoDialog> {
  late TextEditingController _nomeController;
  late TextEditingController _descricaoController;
  late TextEditingController _precoController;

  @override
  void initState() {
    super.initState();
    _nomeController = TextEditingController(text: widget.servico.nome);
    _descricaoController = TextEditingController(
      text: widget.servico.descricao ?? '',
    );
    _precoController = TextEditingController(
      text: widget.servico.preco.toStringAsFixed(2),
    );
  }

  @override
  void dispose() {
    _nomeController.dispose();
    _descricaoController.dispose();
    _precoController.dispose();
    super.dispose();
  }

  void _salvarAlteracoes() {
    final dataService = Provider.of<DataService>(context, listen: false);
    final preco = double.tryParse(_precoController.text.replaceAll(',', '.')) ?? 0.0;
    
    if (_nomeController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('O nome do serviço é obrigatório'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (preco <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('O preço deve ser maior que zero'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final servicoAtualizado = Servico(
      id: widget.servico.id,
      nome: _nomeController.text,
      descricao: _descricaoController.text.isEmpty ? null : _descricaoController.text,
      preco: preco,
      createdAt: widget.servico.createdAt,
      updatedAt: DateTime.now(),
    );

    dataService.updateTipoServico(servicoAtualizado);
    Navigator.of(context).pop();
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Serviço atualizado com sucesso!'),
        backgroundColor: Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    
    return Dialog(
      backgroundColor: theme.dialogBackgroundColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Editar Serviço',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _nomeController,
                style: TextStyle(color: colorScheme.onSurface),
                decoration: InputDecoration(
                  labelText: 'Nome do Serviço *',
                  labelStyle: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                  ),
                  filled: true,
                  fillColor: theme.inputDecorationTheme.fillColor,
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: colorScheme.outline,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: colorScheme.primary,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _descricaoController,
                style: TextStyle(color: colorScheme.onSurface),
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: 'Descrição',
                  labelStyle: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                  ),
                  filled: true,
                  fillColor: theme.inputDecorationTheme.fillColor,
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: colorScheme.outline,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: colorScheme.primary,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _precoController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: TextStyle(color: colorScheme.onSurface),
                decoration: InputDecoration(
                  labelText: 'Preço (R\$) *',
                  prefixText: 'R\$ ',
                  labelStyle: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                  ),
                  filled: true,
                  fillColor: theme.inputDecorationTheme.fillColor,
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: colorScheme.outline,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: colorScheme.primary,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancelar'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        foregroundColor: Theme.of(context).colorScheme.onPrimary,
                        textStyle: const TextStyle(fontSize: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: _salvarAlteracoes,
                      child: const Text('Salvar'),
                    ),
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
