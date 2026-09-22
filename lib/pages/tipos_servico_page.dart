import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/data_service.dart';
import '../models/servico.dart';
import '../theme.dart';
import '../widgets/sync_status_widget.dart';


/// Catálogo de tipos de serviço (o que antes ficava na tela "Serviços").
///
/// Exibe os serviços cadastrados, com preço base, valor adicional e total,
/// permitindo criar, editar e excluir cada tipo de serviço.
class TiposServicoPage extends StatelessWidget {
  const TiposServicoPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    
    return AppTheme.appBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Tipos de Serviço (Cadastro)'),
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: Colors.white,
          actions: [
            IconButton(
              icon: const Icon(Icons.add, color: Colors.greenAccent),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) => const _CriarServicoDialog(),
                );
              },
              tooltip: 'Cadastrar Novo Tipo de Serviço',
            ),
            const SyncStatusWidget(),
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
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.redAccent),
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Deletar Serviço'),
                            content: Text('Tem certeza que deseja deletar o serviço "${servico.nome}"?'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('Cancelar'),
                              ),
                              TextButton(
                                onPressed: () {
                                  dataService.deleteTipoServico(servico.id);
                                  Navigator.pop(context);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Serviço removido com sucesso!'),
                                      backgroundColor: Colors.redAccent,
                                    ),
                                  );
                                },
                                child: const Text('Deletar', style: TextStyle(color: Colors.redAccent)),
                              ),
                            ],
                          ),
                        );
                      },
                      tooltip: 'Deletar serviço',
                    ),
                    const SizedBox(width: 8),
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
  late TextEditingController _duracaoController;
  late TextEditingController _intervaloController;
  late TextEditingController _comissaoController;
  late String _tipoComissao;

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
    _duracaoController = TextEditingController(
      text: widget.servico.duracaoPadraoMinutos?.toString() ?? '60',
    );
    _intervaloController = TextEditingController(
      text: widget.servico.intervaloMinutos?.toString() ?? '0',
    );
    _comissaoController = TextEditingController(
      text: widget.servico.tipoComissao == 'Porcentagem' 
          ? widget.servico.porcentagemComissao.toString().replaceAll('.', ',') 
          : widget.servico.valorComissao.toString().replaceAll('.', ','),
    );
    _tipoComissao = widget.servico.tipoComissao;
  }

  @override
  void dispose() {
    _nomeController.dispose();
    _descricaoController.dispose();
    _precoController.dispose();
    _valorAdicionalController.dispose();
    _descricaoAdicionalController.dispose();
    _duracaoController.dispose();
    _intervaloController.dispose();
    _comissaoController.dispose();
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
    
    final duracao = int.tryParse(_duracaoController.text) ?? 60;
    final intervalo = int.tryParse(_intervaloController.text) ?? 0;
    
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
      duracaoPadraoMinutos: duracao,
      intervaloMinutos: intervalo,
      tipoComissao: _tipoComissao,
      porcentagemComissao: _tipoComissao == 'Porcentagem' ? (double.tryParse(_comissaoController.text.replaceAll(',', '.')) ?? 0.0) : 0.0,
      valorComissao: _tipoComissao == 'Fixo' ? (double.tryParse(_comissaoController.text.replaceAll(',', '.')) ?? 0.0) : 0.0,
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
              const SizedBox(height: 12),
              // Linha: Duração e Intervalo
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _duracaoController,
                      keyboardType: TextInputType.number,
                      style: TextStyle(color: colorScheme.onSurface),
                      decoration: InputDecoration(
                        labelText: 'Duração (min) *',
                        hintText: 'Ex: 40',
                        labelStyle: TextStyle(color: colorScheme.onSurfaceVariant),
                        filled: true,
                        fillColor: theme.inputDecorationTheme.fillColor,
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: colorScheme.outline),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: colorScheme.primary),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _intervaloController,
                      keyboardType: TextInputType.number,
                      style: TextStyle(color: colorScheme.onSurface),
                      decoration: InputDecoration(
                        labelText: 'Intervalo (min)',
                        hintText: 'Ex: 10',
                        labelStyle: TextStyle(color: colorScheme.onSurfaceVariant),
                        filled: true,
                        fillColor: theme.inputDecorationTheme.fillColor,
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: colorScheme.outline),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: colorScheme.primary),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Comissão
              DropdownButtonFormField<String>(
                value: _tipoComissao,
                dropdownColor: theme.dialogBackgroundColor,
                style: TextStyle(color: colorScheme.onSurface),
                decoration: InputDecoration(
                  labelText: 'Tipo de Comissão',
                  labelStyle: TextStyle(color: colorScheme.onSurfaceVariant),
                  filled: true,
                  fillColor: theme.inputDecorationTheme.fillColor,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                items: ['Porcentagem', 'Fixo'].map((String value) {
                  return DropdownMenuItem<String>(
                    value: value,
                    child: Text(value),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _tipoComissao = value ?? 'Porcentagem';
                  });
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _comissaoController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: TextStyle(color: colorScheme.onSurface),
                decoration: InputDecoration(
                  labelText: _tipoComissao == 'Porcentagem' ? 'Comissão (%)' : 'Comissão (R\$)',
                  labelStyle: TextStyle(color: colorScheme.onSurfaceVariant),
                  prefixText: _tipoComissao == 'Porcentagem' ? '' : 'R\$ ',
                  suffixText: _tipoComissao == 'Porcentagem' ? '%' : '',
                  filled: true,
                  fillColor: theme.inputDecorationTheme.fillColor,
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: colorScheme.outline),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: colorScheme.primary),
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

// Modal de cadastro de novo tipo de serviço (Catálogo)
class _CriarServicoDialog extends StatefulWidget {
  const _CriarServicoDialog();

  @override
  State<_CriarServicoDialog> createState() => _CriarServicoDialogState();
}

class _CriarServicoDialogState extends State<_CriarServicoDialog> {
  final _nomeController = TextEditingController();
  final _descricaoController = TextEditingController();
  final _precoController = TextEditingController();
  final _valorAdicionalController = TextEditingController();
  final _descricaoAdicionalController = TextEditingController();
  final _duracaoController = TextEditingController(text: '60');
  final _intervaloController = TextEditingController(text: '0');
  final _comissaoController = TextEditingController(text: '0');
  String _tipoComissao = 'Porcentagem';

  @override
  void dispose() {
    _nomeController.dispose();
    _descricaoController.dispose();
    _precoController.dispose();
    _valorAdicionalController.dispose();
    _descricaoAdicionalController.dispose();
    _duracaoController.dispose();
    _intervaloController.dispose();
    _comissaoController.dispose();
    super.dispose();
  }

  void _cadastrar() {
    final dataService = Provider.of<DataService>(context, listen: false);
    final preco = double.tryParse(_precoController.text.replaceAll(',', '.')) ?? 0.0;
    final valorAdicional = double.tryParse(_valorAdicionalController.text.replaceAll(',', '.')) ?? 0.0;
    final duracao = int.tryParse(_duracaoController.text) ?? 60;
    final intervalo = int.tryParse(_intervaloController.text) ?? 0;

    if (_nomeController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('O nome é obrigatório'), backgroundColor: Colors.red),
      );
      return;
    }

    if (preco <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('O preço deve ser maior que zero'), backgroundColor: Colors.red),
      );
      return;
    }

    final novoServico = Servico(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      nome: _nomeController.text,
      descricao: _descricaoController.text.isEmpty ? null : _descricaoController.text,
      preco: preco,
      valorAdicional: valorAdicional,
      descricaoAdicional: _descricaoAdicionalController.text.isEmpty ? null : _descricaoAdicionalController.text,
      duracaoPadraoMinutos: duracao,
      intervaloMinutos: intervalo,
      tipoComissao: _tipoComissao,
      porcentagemComissao: _tipoComissao == 'Porcentagem' ? (double.tryParse(_comissaoController.text.replaceAll(',', '.')) ?? 0.0) : 0.0,
      valorComissao: _tipoComissao == 'Fixo' ? (double.tryParse(_comissaoController.text.replaceAll(',', '.')) ?? 0.0) : 0.0,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    dataService.addTipoServico(novoServico);
    Navigator.of(context).pop();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Serviço cadastrado no catálogo com sucesso!'),
        backgroundColor: Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF121212),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: MediaQuery.of(context).size.width * 0.95,
          constraints: const BoxConstraints(maxWidth: 800),
          decoration: const BoxDecoration(
            color: Color(0xFF1A1A1A),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header com Gradiente Púrpura (Igual ao original)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF4A148C), Color(0xFF880E4F)],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                ),
                child: const Text(
                  'Cadastrar Novo Serviço',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
              
              Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  children: [
                    // Campo: Nome do Serviço *
                    _buildField(
                      controller: _nomeController,
                      label: 'Nome do Serviço *',
                    ),
                    const SizedBox(height: 12),
                    
                    // Campo: Descrição
                    _buildField(
                      controller: _descricaoController,
                      label: 'Descrição',
                      maxLines: 3,
                    ),
                    const SizedBox(height: 12),
                    
                    // Linha: Preço Base e Valor Adicional
                    Row(
                      children: [
                        Expanded(
                          child: _buildField(
                            controller: _precoController,
                            label: 'Preço Base (R\$) *',
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildField(
                            controller: _valorAdicionalController,
                            label: 'Valor Adicional (R\$)',
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    
                    // Campo: Descrição do Valor Adicional
                    _buildField(
                      controller: _descricaoAdicionalController,
                      label: 'Descrição do Valor Adicional',
                    ),
                    const SizedBox(height: 12),
                    
                    // Linha: Duração e Intervalo
                    Row(
                      children: [
                        Expanded(
                          child: _buildField(
                            controller: _duracaoController,
                            label: 'Duração (min) *',
                            keyboardType: TextInputType.number,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildField(
                            controller: _intervaloController,
                            label: 'Intervalo (min)',
                            keyboardType: TextInputType.number,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    
                    // Linha: Tipo e Valor de Comissão
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFF121212),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.white.withOpacity(0.05)),
                            ),
                            child: DropdownButtonFormField<String>(
                              value: _tipoComissao,
                              dropdownColor: const Color(0xFF1A1A1A),
                              style: const TextStyle(color: Colors.white, fontSize: 14),
                              decoration: const InputDecoration(
                                labelText: 'Tipo de Comissão',
                                labelStyle: TextStyle(color: Colors.white54, fontSize: 13),
                                contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                border: InputBorder.none,
                              ),
                              items: ['Porcentagem', 'Fixo'].map((String value) {
                                return DropdownMenuItem<String>(
                                  value: value,
                                  child: Text(value),
                                );
                              }).toList(),
                              onChanged: (value) {
                                setState(() {
                                  _tipoComissao = value ?? 'Porcentagem';
                                });
                              },
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildField(
                            controller: _comissaoController,
                            label: _tipoComissao == 'Porcentagem' ? 'Comissão (%)' : 'Comissão (R\$)',
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          ),
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 24),
                    
                    // Botões de Ação
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Cancelar', style: TextStyle(color: Colors.white70)),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton(
                          onPressed: _cadastrar,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF4A148C),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          child: const Text('Cadastrar'),
                        ),
                      ],
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

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    int maxLines = 1,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF121212),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        keyboardType: keyboardType,
        style: const TextStyle(color: Colors.white, fontSize: 14),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 13),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          border: InputBorder.none,
          isDense: true,
        ),
      ),
    );
  }
}
