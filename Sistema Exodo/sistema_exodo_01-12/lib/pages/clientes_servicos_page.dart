import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../services/data_service.dart';
import '../models/cliente.dart';
import '../theme.dart';
import 'cliente_servico_detalhes_page.dart';

class ClientesServicosPage extends StatefulWidget {
  const ClientesServicosPage({super.key});

  @override
  State<ClientesServicosPage> createState() => _ClientesServicosPageState();
}

class _ClientesServicosPageState extends State<ClientesServicosPage> {
  final _buscaController = TextEditingController();
  String _termoBusca = '';

  @override
  void dispose() {
    _buscaController.dispose();
    super.dispose();
  }

  List<Cliente> _filtrarClientes(List<Cliente> clientes) {
    if (_termoBusca.isEmpty) return clientes;
    
    final buscaLower = _termoBusca.toLowerCase();
    return clientes.where((cliente) {
      return cliente.nome.toLowerCase().contains(buscaLower) ||
             cliente.telefone.toLowerCase().contains(buscaLower) ||
             (cliente.email != null && cliente.email!.toLowerCase().contains(buscaLower));
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final dataService = Provider.of<DataService>(context);
    final clientes = dataService.clientes;
    final clientesFiltrados = _filtrarClientes(clientes);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AppTheme.appBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Clientes de Serviços'),
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: Colors.white,
          actions: [
            IconButton(
              icon: const Icon(Icons.person_add),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const CadastrarClienteServicoPage(),
                  ),
                );
              },
              tooltip: 'Cadastrar Cliente',
            ),
          ],
        ),
        body: Column(
          children: [
            // Barra de busca
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _buscaController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Buscar cliente...',
                  labelStyle: const TextStyle(color: Colors.white70),
                  hintText: 'Nome, telefone ou email',
                  hintStyle: const TextStyle(color: Colors.white54),
                  prefixIcon: const Icon(Icons.search, color: Colors.white70),
                  suffixIcon: _termoBusca.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, color: Colors.white70),
                          onPressed: () {
                            setState(() {
                              _termoBusca = '';
                              _buscaController.clear();
                            });
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: const Color(0xFF181A1B),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: (value) {
                  setState(() {
                    _termoBusca = value;
                  });
                },
              ),
            ),
            // Lista de clientes
            Expanded(
              child: clientesFiltrados.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _termoBusca.isEmpty ? Icons.people_outline : Icons.search_off,
                            size: 64,
                            color: Colors.white.withOpacity(0.5),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _termoBusca.isEmpty
                                ? 'Nenhum cliente cadastrado'
                                : 'Nenhum cliente encontrado',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.7),
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: clientesFiltrados.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final cliente = clientesFiltrados[index];
                        final pedidosCliente = dataService.pedidos
                            .where((p) => p.clienteId == cliente.id && p.servicos.isNotEmpty)
                            .toList();
                        final totalServicos = pedidosCliente.length;
                        
                        return Card(
                          elevation: theme.cardTheme.elevation ?? 2,
                          shape: theme.cardTheme.shape,
                          color: theme.cardTheme.color,
                          child: ListTile(
                            leading: CircleAvatar(
                              radius: 28,
                              backgroundColor: colorScheme.primary.withOpacity(0.2),
                              backgroundImage: cliente.fotoPath != null && File(cliente.fotoPath!).existsSync()
                                  ? FileImage(File(cliente.fotoPath!))
                                  : null,
                              child: cliente.fotoPath == null || !File(cliente.fotoPath!).existsSync()
                                  ? Icon(
                                      Icons.person,
                                      size: 32,
                                      color: colorScheme.primary,
                                    )
                                  : null,
                            ),
                            title: Text(
                              cliente.nome,
                              style: TextStyle(
                                color: colorScheme.onSurface,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (cliente.telefone.isNotEmpty)
                                  Row(
                                    children: [
                                      const Icon(Icons.phone, size: 14, color: Colors.white70),
                                      const SizedBox(width: 4),
                                      Text(
                                        cliente.telefone,
                                        style: TextStyle(
                                          color: colorScheme.onSurfaceVariant,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    const Icon(Icons.calendar_today, size: 14, color: Colors.white70),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Cadastrado em ${DateFormat('dd/MM/yyyy').format(cliente.createdAt)}',
                                      style: TextStyle(
                                        color: colorScheme.onSurfaceVariant,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                                if (totalServicos > 0) ...[
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      const Icon(Icons.work, size: 14, color: Colors.orange),
                                      const SizedBox(width: 4),
                                      Text(
                                        '$totalServicos serviço${totalServicos > 1 ? 's' : ''} realizado${totalServicos > 1 ? 's' : ''}',
                                        style: const TextStyle(
                                          color: Colors.orange,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                            trailing: Icon(
                              Icons.arrow_forward_ios,
                              size: 16,
                              color: colorScheme.onSurfaceVariant,
                            ),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => ClienteServicoDetalhesPage(cliente: cliente),
                                ),
                              );
                            },
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// Página de cadastro de cliente para serviços
class CadastrarClienteServicoPage extends StatefulWidget {
  const CadastrarClienteServicoPage({super.key});

  @override
  State<CadastrarClienteServicoPage> createState() => _CadastrarClienteServicoPageState();
}

class _CadastrarClienteServicoPageState extends State<CadastrarClienteServicoPage> {
  final _formKey = GlobalKey<FormState>();
  final _nomeController = TextEditingController();
  final _telefoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _observacoesController = TextEditingController();
  final _dadosExtrasController = TextEditingController();
  
  String? _fotoPath;
  bool _isLoading = false;
  final ImagePicker _picker = ImagePicker();

  @override
  void dispose() {
    _nomeController.dispose();
    _telefoneController.dispose();
    _emailController.dispose();
    _observacoesController.dispose();
    _dadosExtrasController.dispose();
    super.dispose();
  }

  Future<void> _selecionarFoto() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 85,
      );
      
      if (image != null) {
        setState(() {
          _fotoPath = image.path;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao selecionar foto: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _tirarFoto() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 85,
      );
      
      if (image != null) {
        setState(() {
          _fotoPath = image.path;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao tirar foto: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _salvarCliente() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final dataService = Provider.of<DataService>(context, listen: false);
      
      // Parse dados extras (JSON simples)
      Map<String, dynamic>? dadosExtras;
      if (_dadosExtrasController.text.isNotEmpty) {
        try {
          // Tentar parsear como JSON, se falhar, salvar como texto simples
          dadosExtras = {'texto': _dadosExtrasController.text};
        } catch (_) {
          dadosExtras = {'texto': _dadosExtrasController.text};
        }
      }

      final cliente = Cliente(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        nome: _nomeController.text.trim(),
        telefone: _telefoneController.text.trim(),
        email: _emailController.text.trim().isEmpty ? null : _emailController.text.trim(),
        observacoes: _observacoesController.text.trim().isEmpty ? null : _observacoesController.text.trim(),
        fotoPath: _fotoPath,
        dadosExtras: dadosExtras,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await dataService.addCliente(cliente);

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cliente cadastrado com sucesso!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao cadastrar cliente: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AppTheme.appBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Cadastrar Cliente'),
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: Colors.white,
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Foto do cliente
                Center(
                  child: Stack(
                    children: [
                      CircleAvatar(
                        radius: 60,
                        backgroundColor: colorScheme.primary.withOpacity(0.2),
                        backgroundImage: _fotoPath != null && File(_fotoPath!).existsSync()
                            ? FileImage(File(_fotoPath!))
                            : null,
                        child: _fotoPath == null || !File(_fotoPath!).existsSync()
                            ? Icon(
                                Icons.person,
                                size: 60,
                                color: colorScheme.primary,
                              )
                            : null,
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          decoration: BoxDecoration(
                            color: colorScheme.primary,
                            shape: BoxShape.circle,
                          ),
                          child: IconButton(
                            icon: const Icon(Icons.camera_alt, color: Colors.white),
                            onPressed: () {
                              showModalBottomSheet(
                                context: context,
                                backgroundColor: const Color(0xFF1E1E2E),
                                shape: const RoundedRectangleBorder(
                                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                                ),
                                builder: (context) => SafeArea(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      ListTile(
                                        leading: const Icon(Icons.photo_library, color: Colors.white),
                                        title: const Text('Galeria', style: TextStyle(color: Colors.white)),
                                        onTap: () {
                                          Navigator.pop(context);
                                          _selecionarFoto();
                                        },
                                      ),
                                      ListTile(
                                        leading: const Icon(Icons.camera_alt, color: Colors.white),
                                        title: const Text('Câmera', style: TextStyle(color: Colors.white)),
                                        onTap: () {
                                          Navigator.pop(context);
                                          _tirarFoto();
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                // Nome
                TextFormField(
                  controller: _nomeController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Nome *',
                    labelStyle: const TextStyle(color: Colors.white70),
                    filled: true,
                    fillColor: const Color(0xFF181A1B),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    prefixIcon: const Icon(Icons.person, color: Colors.white70),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Informe o nome do cliente';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                // Telefone
                TextFormField(
                  controller: _telefoneController,
                  style: const TextStyle(color: Colors.white),
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: 'Telefone *',
                    labelStyle: const TextStyle(color: Colors.white70),
                    filled: true,
                    fillColor: const Color(0xFF181A1B),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    prefixIcon: const Icon(Icons.phone, color: Colors.white70),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Informe o telefone do cliente';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                // Email
                TextFormField(
                  controller: _emailController,
                  style: const TextStyle(color: Colors.white),
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    labelText: 'Email (Opcional)',
                    labelStyle: const TextStyle(color: Colors.white70),
                    filled: true,
                    fillColor: const Color(0xFF181A1B),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    prefixIcon: const Icon(Icons.email, color: Colors.white70),
                  ),
                ),
                const SizedBox(height: 16),
                // Observações
                TextFormField(
                  controller: _observacoesController,
                  style: const TextStyle(color: Colors.white),
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: 'Observações',
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
                // Dados Extras
                TextFormField(
                  controller: _dadosExtrasController,
                  style: const TextStyle(color: Colors.white),
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: 'Dados Extras',
                    hintText: 'Informações adicionais sobre o cliente',
                    labelStyle: const TextStyle(color: Colors.white70),
                    hintStyle: const TextStyle(color: Colors.white38),
                    filled: true,
                    fillColor: const Color(0xFF181A1B),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                // Botão Salvar
                ElevatedButton(
                  onPressed: _isLoading ? null : _salvarCliente,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colorScheme.primary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Text(
                          'Cadastrar Cliente',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
