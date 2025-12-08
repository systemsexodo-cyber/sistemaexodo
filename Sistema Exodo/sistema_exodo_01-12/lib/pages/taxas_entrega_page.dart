import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../models/taxa_entrega.dart';
import '../services/data_service.dart';
import '../theme.dart';

/// Página para gerenciar taxas de entrega por bairro
class TaxasEntregaPage extends StatefulWidget {
  const TaxasEntregaPage({super.key});

  @override
  State<TaxasEntregaPage> createState() => _TaxasEntregaPageState();
}

class _TaxasEntregaPageState extends State<TaxasEntregaPage> {
  final TextEditingController _buscaController = TextEditingController();
  String _termoBusca = '';

  @override
  void dispose() {
    _buscaController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dataService = Provider.of<DataService>(context);
    final taxas = _filtrarTaxas(dataService.taxasEntrega);

    return AppTheme.appBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Taxas de Entrega'),
          actions: [
            IconButton(
              icon: const Icon(Icons.search),
              tooltip: 'Buscar',
              onPressed: () => _mostrarBusca(context),
            ),
          ],
        ),
        body: Column(
          children: [
            // Indicador de filtro ativo
            if (_termoBusca.isNotEmpty)
              _buildFiltroAtivo(),

            // Lista de taxas
            Expanded(
              child: taxas.isEmpty
                  ? _buildEmptyState()
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: taxas.length,
                      itemBuilder: (context, index) {
                        return _buildTaxaCard(context, taxas[index], dataService);
                      },
                    ),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _criarNovaTaxa(context, dataService),
          backgroundColor: Colors.green,
          icon: const Icon(Icons.add),
          label: const Text('Nova Taxa'),
        ),
      ),
    );
  }

  Widget _buildFiltroAtivo() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(Icons.filter_alt, color: Colors.greenAccent, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Chip(
              label: Text('Busca: "$_termoBusca"'),
              deleteIcon: const Icon(Icons.close, size: 16),
              onDeleted: () => setState(() {
                _termoBusca = '';
                _buscaController.clear();
              }),
              backgroundColor: Colors.blue.withOpacity(0.3),
              labelStyle: const TextStyle(
                color: Colors.white,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.local_shipping_outlined,
            size: 88,
            color: Colors.blue.shade900,
          ),
          const SizedBox(height: 16),
          Text(
            'Nenhuma taxa cadastrada',
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Cadastre taxas de entrega por bairro',
            style: TextStyle(
              color: Colors.white.withOpacity(0.5),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTaxaCard(
    BuildContext context,
    TaxaEntrega taxa,
    DataService dataService,
  ) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: taxa.ativo ? Colors.green.withOpacity(0.2) : Colors.grey.withOpacity(0.2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            Icons.location_on,
            color: taxa.ativo ? Colors.green : Colors.grey,
            size: 24,
          ),
        ),
        title: Text(
          taxa.bairro,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (taxa.cidade != null) ...[
              Text(
                taxa.cidade!,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.7),
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 4),
            ],
            Text(
              'R\$ ${taxa.valor.toStringAsFixed(2)}',
              style: const TextStyle(
                color: Colors.greenAccent,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!taxa.ativo)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.grey.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Inativa',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                  ),
                ),
              ),
            const SizedBox(width: 8),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: Colors.white54),
              onSelected: (value) {
                if (value == 'editar') {
                  _editarTaxa(context, taxa, dataService);
                } else if (value == 'ativar') {
                  _alterarStatusTaxa(taxa, true, dataService);
                } else if (value == 'desativar') {
                  _alterarStatusTaxa(taxa, false, dataService);
                } else if (value == 'excluir') {
                  _confirmarExclusao(context, taxa, dataService);
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'editar',
                  child: Row(
                    children: [
                      Icon(Icons.edit, size: 18),
                      SizedBox(width: 8),
                      Text('Editar'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: taxa.ativo ? 'desativar' : 'ativar',
                  child: Row(
                    children: [
                      Icon(
                        taxa.ativo ? Icons.block : Icons.check_circle,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Text(taxa.ativo ? 'Desativar' : 'Ativar'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'excluir',
                  child: Row(
                    children: [
                      Icon(Icons.delete, size: 18, color: Colors.red),
                      SizedBox(width: 8),
                      Text('Excluir', style: TextStyle(color: Colors.red)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
        onTap: () => _editarTaxa(context, taxa, dataService),
      ),
    );
  }

  List<TaxaEntrega> _filtrarTaxas(List<TaxaEntrega> taxas) {
    if (_termoBusca.isEmpty) {
      return taxas;
    }

    final termo = _termoBusca.toLowerCase();
    return taxas.where((taxa) {
      return taxa.bairro.toLowerCase().contains(termo) ||
          (taxa.cidade?.toLowerCase().contains(termo) ?? false);
    }).toList();
  }

  void _mostrarBusca(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Buscar Taxas',
          style: TextStyle(color: Colors.white),
        ),
        content: TextField(
          controller: _buscaController,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Bairro ou cidade...',
            hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
            prefixIcon: const Icon(Icons.search, color: Colors.white54),
            filled: true,
            fillColor: Colors.black26,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              _buscaController.clear();
              setState(() => _termoBusca = '');
              Navigator.pop(context);
            },
            child: const Text(
              'Limpar',
              style: TextStyle(color: Colors.white54),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() => _termoBusca = _buscaController.text);
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.greenAccent,
              foregroundColor: Colors.black,
            ),
            child: const Text('Buscar'),
          ),
        ],
      ),
    );
  }

  void _criarNovaTaxa(BuildContext context, DataService dataService) {
    _mostrarDialogoTaxa(context, null, dataService);
  }

  void _editarTaxa(BuildContext context, TaxaEntrega taxa, DataService dataService) {
    _mostrarDialogoTaxa(context, taxa, dataService);
  }

  void _mostrarDialogoTaxa(
    BuildContext context,
    TaxaEntrega? taxa,
    DataService dataService,
  ) {
    final bairroController = TextEditingController(text: taxa?.bairro ?? '');
    final cidadeController = TextEditingController(text: taxa?.cidade ?? '');
    final valorController = TextEditingController(
      text: taxa?.valor.toStringAsFixed(2) ?? '0.00',
    );
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          taxa == null ? 'Nova Taxa de Entrega' : 'Editar Taxa de Entrega',
          style: const TextStyle(color: Colors.white),
        ),
        content: SingleChildScrollView(
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: bairroController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Bairro *',
                    labelStyle: const TextStyle(color: Colors.white70),
                    filled: true,
                    fillColor: Colors.black26,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    prefixIcon: const Icon(Icons.location_on, color: Colors.white54),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Campo obrigatório';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: cidadeController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Cidade',
                    labelStyle: const TextStyle(color: Colors.white70),
                    filled: true,
                    fillColor: Colors.black26,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    prefixIcon: const Icon(Icons.location_city, color: Colors.white54),
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: valorController,
                  style: const TextStyle(color: Colors.white),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Valor da Taxa (R\$) *',
                    labelStyle: const TextStyle(color: Colors.white70),
                    filled: true,
                    fillColor: Colors.black26,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    prefixIcon: const Icon(Icons.attach_money, color: Colors.white54),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Campo obrigatório';
                    }
                    final valor = double.tryParse(value.replaceAll(',', '.'));
                    if (valor == null || valor < 0) {
                      return 'Valor inválido';
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Cancelar',
              style: TextStyle(color: Colors.white54),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                final agora = DateTime.now();
                final novaTaxa = TaxaEntrega(
                  id: taxa?.id ?? const Uuid().v4(),
                  bairro: bairroController.text.trim(),
                  cidade: cidadeController.text.trim().isEmpty
                      ? null
                      : cidadeController.text.trim(),
                  valor: double.parse(
                    valorController.text.replaceAll(',', '.'),
                  ),
                  ativo: taxa?.ativo ?? true,
                  createdAt: taxa?.createdAt ?? agora,
                  updatedAt: agora,
                );

                if (taxa == null) {
                  dataService.addTaxaEntrega(novaTaxa);
                } else {
                  dataService.updateTaxaEntrega(novaTaxa);
                }

                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      taxa == null
                          ? 'Taxa cadastrada com sucesso!'
                          : 'Taxa atualizada com sucesso!',
                    ),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.greenAccent,
              foregroundColor: Colors.black,
            ),
            child: Text(taxa == null ? 'Cadastrar' : 'Salvar'),
          ),
        ],
      ),
    );
  }

  void _alterarStatusTaxa(
    TaxaEntrega taxa,
    bool ativo,
    DataService dataService,
  ) {
    final taxaAtualizada = taxa.copyWith(
      ativo: ativo,
      updatedAt: DateTime.now(),
    );
    dataService.updateTaxaEntrega(taxaAtualizada);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ativo ? 'Taxa ativada com sucesso!' : 'Taxa desativada com sucesso!',
        ),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _confirmarExclusao(
    BuildContext context,
    TaxaEntrega taxa,
    DataService dataService,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Confirmar Exclusão',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'Deseja realmente excluir a taxa de entrega para "${taxa.bairro}"?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Cancelar',
              style: TextStyle(color: Colors.white54),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              dataService.deleteTaxaEntrega(taxa.id);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Taxa excluída com sucesso!'),
                  backgroundColor: Colors.green,
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
  }
}

