import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/data_service.dart';
import '../models/servico.dart';
import '../models/cliente.dart';
import '../theme.dart';
import 'lancar_servico_page.dart';
import 'agenda_servicos_page.dart';
import 'pdv_page.dart';
import 'clientes_servicos_page.dart';
import 'comissoes_page.dart';
import 'historico_vendas_page.dart';

class ServicosPage extends StatelessWidget {
  const ServicosPage({super.key});

  @override
  Widget build(BuildContext context) {
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
              icon: const Icon(Icons.people),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const ClientesServicosPage(),
                  ),
                );
              },
              tooltip: 'Clientes de Serviços',
            ),
            IconButton(
              icon: const Icon(Icons.account_balance_wallet),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const ComissoesPage(),
                  ),
                );
              },
              tooltip: 'Consulta de Comissões',
            ),
            IconButton(
              icon: const Icon(Icons.payment),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const PdvPage(
                      abaInicial: 0, // Aba de Receber
                    ),
                  ),
                );
              },
              tooltip: 'Receber Pagamentos',
            ),
            IconButton(
              icon: const Icon(Icons.calendar_month),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const AgendaServicosPage(),
                  ),
                );
              },
              tooltip: 'Agenda de Serviços',
            ),
            IconButton(
              icon: const Icon(Icons.history, color: Colors.blue),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const HistoricoVendasPage(),
                  ),
                );
              },
              tooltip: 'Histórico de Vendas',
            ),
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
        body: Consumer<DataService>(
          builder: (context, dataService, _) {
            final servicos = dataService.servicos;
            
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              cacheExtent: 1000, // Otimização para mobile: pré-carrega itens próximos
              itemCount: servicos.length,
          separatorBuilder: (_, __) => const SizedBox(height: 16),
          itemBuilder: (context, index) {
            final servico = servicos[index];
            // Garante que o valor adicional seja exibido corretamente
            final valorAdicional = servico.valorAdicional;
            final precoBase = servico.preco;
            final temAdicional = valorAdicional > 0.001;
            
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
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (servico.descricaoAdicional != null && servico.descricaoAdicional!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        servico.descricaoAdicional!,
                        style: TextStyle(
                          color: colorScheme.primary,
                          fontStyle: FontStyle.italic,
                          fontSize: 12,
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    // Preço Base - SEMPRE mostra o valor base puro (sem adicional)
                    Row(
                      children: [
                        const Text(
                          'Preço Base: ',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                        Text(
                          'R\$ ${precoBase.toStringAsFixed(2)}',
                          style: TextStyle(
                            color: colorScheme.onSurfaceVariant,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    // Valor Adicional - SEMPRE mostra quando houver valor adicional
                    if (temAdicional) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Text(
                            '+ ',
                            style: TextStyle(
                              color: Colors.green,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Text(
                            'Adicional: ',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                          Text(
                            'R\$ ${valorAdicional.toStringAsFixed(2)}',
                            style: const TextStyle(
                              color: Colors.green,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 6),
                    // Total - SEMPRE mostra (preço base + valor adicional)
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      decoration: BoxDecoration(
                        border: Border(
                          top: BorderSide(
                            color: Colors.white.withOpacity(0.1),
                            width: 1,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Text(
                            'Total: ',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            'R\$ ${(precoBase + valorAdicional).toStringAsFixed(2)}',
                            style: TextStyle(
                              color: colorScheme.primary,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(Icons.edit, color: colorScheme.primary),
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder: (context) => _EditarServicoDialog(servico: servico),
                        );
                      },
                      tooltip: 'Editar serviço',
                    ),
                    Text(
                      'R\$ ${(precoBase + valorAdicional).toStringAsFixed(2)}',
                      style: TextStyle(
                        color: colorScheme.primary,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
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
                displayStringForOption: (Servico s) {
              if (s.temAdicional) {
                return '${s.nome} + R\$ ${s.preco.toStringAsFixed(2)} + R\$ ${s.valorAdicional.toStringAsFixed(2)} = R\$ ${s.precoTotal.toStringAsFixed(2)}';
              }
              return '${s.nome} + R\$ ${s.preco.toStringAsFixed(2)}';
            },
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
                    _valorController.text = selection.precoTotal.toStringAsFixed(2);
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
  late TextEditingController _valorAdicionalController;
  late TextEditingController _descricaoAdicionalController;

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
    _valorAdicionalController = TextEditingController(
      text: widget.servico.valorAdicional > 0 
          ? widget.servico.valorAdicional.toStringAsFixed(2).replaceAll('.', ',')
          : '',
    );
    _descricaoAdicionalController = TextEditingController(
      text: widget.servico.descricaoAdicional ?? '',
    );
  }

  @override
  void dispose() {
    _nomeController.dispose();
    _descricaoController.dispose();
    _precoController.dispose();
    _valorAdicionalController.dispose();
    _descricaoAdicionalController.dispose();
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

    final valorAdicionalTexto = _valorAdicionalController.text.trim().replaceAll(',', '.');
    final valorAdicional = double.tryParse(valorAdicionalTexto) ?? 0.0;
    
    // Debug para verificar valores antes de salvar
    debugPrint('>>> SALVANDO SERVIÇO:');
    debugPrint('>>> Nome: ${_nomeController.text}');
    debugPrint('>>> Preço Base: $preco');
    debugPrint('>>> Valor Adicional Texto: ${_valorAdicionalController.text}');
    debugPrint('>>> Valor Adicional Parseado: $valorAdicional');
    debugPrint('>>> Descrição Adicional: ${_descricaoAdicionalController.text}');
    
    final servicoAtualizado = Servico(
      id: widget.servico.id,
      nome: _nomeController.text,
      descricao: _descricaoController.text.isEmpty ? null : _descricaoController.text,
      preco: preco,
      valorAdicional: valorAdicional,
      descricaoAdicional: _descricaoAdicionalController.text.isEmpty ? null : _descricaoAdicionalController.text,
      createdAt: widget.servico.createdAt,
      updatedAt: DateTime.now(),
    );
    
    debugPrint('>>> Serviço Criado:');
    debugPrint('>>> Preço: ${servicoAtualizado.preco}');
    debugPrint('>>> Valor Adicional: ${servicoAtualizado.valorAdicional}');
    debugPrint('>>> Preço Total: ${servicoAtualizado.precoTotal}');

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
                  labelText: 'Preço Base (R\$) *',
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
              const SizedBox(height: 12),
              TextField(
                controller: _valorAdicionalController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: TextStyle(color: colorScheme.onSurface),
                enabled: true,
                decoration: InputDecoration(
                  labelText: 'Valor Adicional (R\$)',
                  hintText: 'Ex: 10,00',
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
                      color: Colors.orange,
                      width: 2,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _descricaoAdicionalController,
                style: TextStyle(color: colorScheme.onSurface),
                maxLines: 3,
                enabled: true,
                decoration: InputDecoration(
                  labelText: 'Descrição do Adicional (Opcional)',
                  hintText: 'Ex: Lavagem premium, Corte + barba...',
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
                      color: Colors.orange,
                      width: 2,
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
