import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sistema_exodo_novo/models/funcionario.dart';
import 'package:sistema_exodo_novo/models/usuario.dart';
import 'package:sistema_exodo_novo/services/data_service.dart';
import 'package:sistema_exodo_novo/services/auth_service.dart';
import 'package:sistema_exodo_novo/theme.dart';
import 'package:sistema_exodo_novo/widgets/sync_status_widget.dart';
import 'comissoes_page.dart';
import 'motoristas_page.dart';
import 'vendedor_dashboard_page.dart';

class FuncionariosPage extends StatefulWidget {
  const FuncionariosPage({super.key});

  @override
  State<FuncionariosPage> createState() => _FuncionariosPageState();
}

class _FuncionariosPageState extends State<FuncionariosPage> {
  final TextEditingController _buscaController = TextEditingController();
  final GlobalKey<_FuncionariosListTabState> _funcionariosTabKey =
      GlobalKey<_FuncionariosListTabState>();
  String _termoBusca = '';
  bool _mostrarBusca = false;

  @override
  void dispose() {
    _buscaController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: AppTheme.appBackground(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            title: const Text('Gestão de Colaboradores'),
            backgroundColor: Colors.transparent,
            elevation: 0,
            bottom: const TabBar(
              isScrollable: true,
              tabs: [
                Tab(icon: Icon(Icons.people), text: 'Funcionários'),
                Tab(icon: Icon(Icons.motorcycle), text: 'Motoboy/Motorista'),
                Tab(icon: Icon(Icons.monetization_on), text: 'Comissões'),
                Tab(icon: Icon(Icons.dashboard_customize), text: 'Dashboard'),
              ],
            ),
            actions: [
              const SyncStatusWidget(),
              IconButton(
                icon: Icon(
                  _mostrarBusca ? Icons.search_off : Icons.search,
                  color: _mostrarBusca
                      ? Colors.greenAccent
                      : Theme.of(context).colorScheme.onPrimary,
                ),
                tooltip: _mostrarBusca ? 'Fechar busca' : 'Buscar funcionários',
                onPressed: () {
                  setState(() {
                    _mostrarBusca = !_mostrarBusca;
                    if (!_mostrarBusca) {
                      _termoBusca = '';
                      _buscaController.clear();
                    }
                  });
                },
              ),
              IconButton(
                icon: const Icon(Icons.add),
                tooltip: 'Adicionar funcionário',
                onPressed: () =>
                    _funcionariosTabKey.currentState?._mostrarDialogoCriarFuncionario(),
              ),
            ],
          ),
          body: TabBarView(
            children: [
              _FuncionariosListTab(key: _funcionariosTabKey),
              const MotoristasPage(isEmbedded: true),
              const ComissoesPage(),
              const VendedorDashboardPage(),
            ],
          ),
        ),
      ),
    );
  }
}

class _FuncionariosListTab extends StatefulWidget {
  const _FuncionariosListTab({super.key});

  @override
  State<_FuncionariosListTab> createState() => _FuncionariosListTabState();
}

class _FuncionariosListTabState extends State<_FuncionariosListTab> {
  final TextEditingController _buscaController = TextEditingController();
  String _termoBusca = '';
  bool _mostrarBusca = false;

  @override
  void dispose() {
    _buscaController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dataService = Provider.of<DataService>(context);
    final funcionarios = _filtrarFuncionarios(dataService.funcionarios);

    return Column(
      children: [
            // Barra de busca
            if (_mostrarBusca)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF23272A).withOpacity(0.5),
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(16),
                    bottomRight: Radius.circular(16),
                  ),
                ),
                child: TextField(
                  controller: _buscaController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Buscar funcionário...',
                    hintStyle: const TextStyle(color: Colors.white54),
                    prefixIcon: const Icon(Icons.search, color: Colors.white70),
                    suffixIcon: _buscaController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, color: Colors.white70),
                            onPressed: () {
                              _buscaController.clear();
                              setState(() {
                                _termoBusca = '';
                              });
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: const Color(0xFF23272A),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.white24),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.white24),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.white54),
                    ),
                  ),
                  onChanged: (value) {
                    setState(() {
                      _termoBusca = value;
                    });
                  },
                ),
              ),

            // Lista de funcionários
            Expanded(
              child: funcionarios.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.person_outline,
                            size: 64,
                            color: Colors.white.withOpacity(0.5),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _termoBusca.isNotEmpty
                                ? 'Nenhum funcionário encontrado'
                                : 'Nenhum funcionário cadastrado',
                            style: TextStyle(
                              fontSize: 18,
                              color: Colors.white.withOpacity(0.7),
                            ),
                          ),
                          const SizedBox(height: 8),
                          if (_termoBusca.isEmpty)
                            ElevatedButton.icon(
                              onPressed: () => _mostrarDialogoCriarFuncionario(),
                              icon: const Icon(Icons.add),
                              label: const Text('Cadastrar Primeiro Funcionário'),
                            ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: funcionarios.length,
                      itemBuilder: (context, index) {
                        final funcionario = funcionarios[index];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: funcionario.ativo
                                  ? Theme.of(context).colorScheme.primary
                                  : Colors.grey,
                              child: Text(
                                funcionario.nome[0].toUpperCase(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            title: Text(
                              funcionario.nome,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: funcionario.ativo
                                    ? Colors.white
                                    : Colors.white70,
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (funcionario.telefone != null)
                                  Text(
                                    '📞 ${funcionario.telefone}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.white70,
                                    ),
                                  ),
                                if (funcionario.email != null)
                                  Text(
                                    '✉️ ${funcionario.email}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.white70,
                                    ),
                                  ),
                                if (!funcionario.ativo)
                                  const Text(
                                    '❌ Inativo',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.red,
                                    ),
                                  ),
                                if (funcionario.porcentagemComissao > 0 || funcionario.valorComissao > 0)
                                  Text(
                                    funcionario.tipoComissao == 'Porcentagem'
                                        ? '💰 Comissão: ${funcionario.porcentagemComissao.toStringAsFixed(1)}%'
                                        : '💰 Comissão: R\$ ${funcionario.valorComissao.toStringAsFixed(2)}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.greenAccent,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                              ],
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit),
                                  color: Colors.blue,
                                  tooltip: 'Editar',
                                  onPressed: () =>
                                      _mostrarDialogoEditarFuncionario(funcionario),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete),
                                  color: Colors.red,
                                  tooltip: 'Excluir',
                                  onPressed: () =>
                                      _confirmarExcluirFuncionario(funcionario),
                                ),
                              ],
                            ),
                            onTap: () =>
                                _mostrarDialogoEditarFuncionario(funcionario),
                          ),
                        );
                      },
                    ),
            ),
      ],
    );
  }

  List<Funcionario> _filtrarFuncionarios(List<Funcionario> funcionarios) {
    if (_termoBusca.isEmpty) {
      return funcionarios;
    }
    final termo = _termoBusca.toLowerCase();
    return funcionarios.where((f) {
      return f.nome.toLowerCase().contains(termo) ||
          (f.telefone?.toLowerCase().contains(termo) ?? false) ||
          (f.email?.toLowerCase().contains(termo) ?? false);
    }).toList();
  }

  void _mostrarDialogoCriarFuncionario() {
    final nomeController = TextEditingController();
    final telefoneController = TextEditingController();
    final emailController = TextEditingController();
    final senhaController = TextEditingController();
    final observacoesController = TextEditingController();
    final comissaoController = TextEditingController(text: '0');
    String tipoComissao = 'Porcentagem';
    bool ativo = true;
    bool temAcesso = false;
    bool obscureSenha = true;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF10151B),
            title: const Text(
              'Cadastrar Funcionário / Vendedor',
              style: TextStyle(color: Colors.white),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: nomeController,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'Nome *',
                      labelStyle: TextStyle(color: Colors.white70),
                      border: OutlineInputBorder(),
                    ),
                    autofocus: true,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: telefoneController,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'Telefone',
                      labelStyle: TextStyle(color: Colors.white70),
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: emailController,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'E-mail',
                      labelStyle: TextStyle(color: Colors.white70),
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.emailAddress,
                  ),

                  const SizedBox(height: 16),
                  TextFormField(
                    controller: observacoesController,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'Observações',
                      labelStyle: TextStyle(color: Colors.white70),
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: tipoComissao,
                    dropdownColor: const Color(0xFF10151B),
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'Tipo de Comissão',
                      labelStyle: TextStyle(color: Colors.white70),
                      border: OutlineInputBorder(),
                    ),
                    items: ['Porcentagem', 'Fixo'].map((String value) {
                      return DropdownMenuItem<String>(
                        value: value,
                        child: Text(value),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() {
                        tipoComissao = value ?? 'Porcentagem';
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: comissaoController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: tipoComissao == 'Porcentagem' ? 'Porcentagem de Comissão (%)' : 'Valor Fixo de Comissão (R\$)',
                      labelStyle: const TextStyle(color: Colors.white70),
                      border: const OutlineInputBorder(),
                      suffixText: tipoComissao == 'Porcentagem' ? '%' : 'R\$',
                      helperText: 'Será cobrada em cima do valor do serviço',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                  const SizedBox(height: 16),
                  CheckboxListTile(
                    title: const Text(
                      'Ativo',
                      style: TextStyle(color: Colors.white),
                    ),
                    value: ativo,
                    onChanged: (value) {
                      setState(() {
                        ativo = value ?? true;
                      });
                    },
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
                  if (nomeController.text.trim().isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Informe o nome do funcionário'),
                        backgroundColor: Colors.red,
                      ),
                    );
                    return;
                  }

                  if (temAcesso && senhaController.text.trim().isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Informe uma senha para o acesso ao sistema'),
                        backgroundColor: Colors.red,
                      ),
                    );
                    return;
                  }

                  _criarFuncionario(
                    nomeController.text.trim(),
                    telefoneController.text.trim().isEmpty
                        ? null
                        : telefoneController.text.trim(),
                    emailController.text.trim().isEmpty
                        ? null
                        : emailController.text.trim(),
                    temAcesso ? senhaController.text.trim() : null,
                    observacoesController.text.trim().isEmpty
                        ? null
                        : observacoesController.text.trim(),
                    ativo,
                    temAcesso,
                    tipoComissao == 'Porcentagem' ? (double.tryParse(comissaoController.text.replaceAll(',', '.')) ?? 0.0) : 0.0,
                    tipoComissao,
                    tipoComissao == 'Fixo' ? (double.tryParse(comissaoController.text.replaceAll(',', '.')) ?? 0.0) : 0.0,
                  );
                  Navigator.pop(context);
                },
                child: const Text('Cadastrar'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _mostrarDialogoEditarFuncionario(Funcionario funcionario) {
    final nomeController = TextEditingController(text: funcionario.nome);
    final telefoneController = TextEditingController(text: funcionario.telefone ?? '');
    final emailController = TextEditingController(text: funcionario.email ?? '');
    final senhaController = TextEditingController(text: '');
    final observacoesController =
        TextEditingController(text: funcionario.observacoes ?? '');
    final comissaoController = TextEditingController(
      text: funcionario.tipoComissao == 'Porcentagem' 
          ? funcionario.porcentagemComissao.toString() 
          : funcionario.valorComissao.toString()
    );
    String tipoComissao = funcionario.tipoComissao;
    bool ativo = funcionario.ativo;
    bool temAcesso = funcionario.temAcesso;
    bool obscureSenha = true;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF10151B),
            title: const Text(
              'Editar Funcionário / Vendedor',
              style: TextStyle(color: Colors.white),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: nomeController,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'Nome *',
                      labelStyle: TextStyle(color: Colors.white70),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: telefoneController,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'Telefone',
                      labelStyle: TextStyle(color: Colors.white70),
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: emailController,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'E-mail',
                      labelStyle: TextStyle(color: Colors.white70),
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.emailAddress,
                  ),

                  const SizedBox(height: 16),
                  TextFormField(
                    controller: observacoesController,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'Observações',
                      labelStyle: TextStyle(color: Colors.white70),
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: tipoComissao,
                    dropdownColor: const Color(0xFF10151B),
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'Tipo de Comissão',
                      labelStyle: TextStyle(color: Colors.white70),
                      border: OutlineInputBorder(),
                    ),
                    items: ['Porcentagem', 'Fixo'].map((String value) {
                      return DropdownMenuItem<String>(
                        value: value,
                        child: Text(value),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() {
                        tipoComissao = value ?? 'Porcentagem';
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: comissaoController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: tipoComissao == 'Porcentagem' ? 'Porcentagem de Comissão (%)' : 'Valor Fixo de Comissão (R\$)',
                      labelStyle: const TextStyle(color: Colors.white70),
                      border: const OutlineInputBorder(),
                      suffixText: tipoComissao == 'Porcentagem' ? '%' : 'R\$',
                      helperText: 'Será cobrada em cima do valor do serviço',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                  const SizedBox(height: 16),
                  CheckboxListTile(
                    title: const Text(
                      'Ativo',
                      style: TextStyle(color: Colors.white),
                    ),
                    value: ativo,
                    onChanged: (value) {
                      setState(() {
                        ativo = value ?? true;
                      });
                    },
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
                if (nomeController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Informe o nome do funcionário'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }

                if (temAcesso && !funcionario.temAcesso && senhaController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Informe uma senha para o acesso ao sistema'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }

                Navigator.pop(context);
                _atualizarFuncionario(
                  funcionario,
                  nomeController.text.trim(),
                  telefoneController.text.trim().isEmpty
                      ? null
                      : telefoneController.text.trim(),
                  emailController.text.trim().isEmpty
                      ? null
                      : emailController.text.trim(),
                  temAcesso && senhaController.text.trim().isNotEmpty
                      ? senhaController.text.trim()
                      : funcionario.senha,
                  observacoesController.text.trim().isEmpty
                      ? null
                      : observacoesController.text.trim(),
                  ativo,
                  temAcesso,
                  tipoComissao == 'Porcentagem' ? (double.tryParse(comissaoController.text.replaceAll(',', '.')) ?? 0.0) : 0.0,
                  tipoComissao,
                  tipoComissao == 'Fixo' ? (double.tryParse(comissaoController.text.replaceAll(',', '.')) ?? 0.0) : 0.0,
                );
              },
              child: const Text('Salvar'),
            ),
          ],
          );
        },
      ),
    );
  }

  Future<void> _criarFuncionario(
    String nome,
    String? telefone,
    String? email,
    String? senha,
    String? observacoes,
    bool ativo,
    bool temAcesso,
    double porcentagemComissao,
    String tipoComissao,
    double valorComissao,
  ) async {
    final dataService = Provider.of<DataService>(context, listen: false);
    final authService = Provider.of<AuthService>(context, listen: false);

    final funcionarioId = DateTime.now().millisecondsSinceEpoch.toString();
    
    final funcionario = Funcionario(
      id: funcionarioId,
      nome: nome,
      telefone: telefone,
      email: email,
      senha: senha,
      observacoes: observacoes,
      ativo: ativo,
      temAcesso: temAcesso,
      porcentagemComissao: porcentagemComissao,
      tipoComissao: tipoComissao,
      valorComissao: valorComissao,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    // Salvar funcionário
    await dataService.addFuncionario(funcionario);

    // Se o funcionário tem acesso, criar usuário automaticamente
    if (temAcesso && email != null && email.isNotEmpty && senha != null && senha.isNotEmpty) {
      try {
        final empresaId = authService.empresaAtual?.id;
        if (empresaId != null) {
          final usuario = Usuario(
            id: 'func_$funcionarioId',
            nome: nome,
            email: email.toLowerCase().trim(),
            senha: senha,
            telefone: telefone,
            tipo: TipoUsuario.vendedor,
            empresaId: empresaId,
            funcionarioId: funcionarioId,
            ativo: ativo,
            isMaster: false,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          );
          
          await authService.adicionarUsuario(usuario);
          debugPrint('>>> Usuário criado automaticamente para funcionário: $nome');
        }
      } catch (e) {
        debugPrint('>>> Erro ao criar usuário para funcionário: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Funcionário cadastrado, mas erro ao criar acesso: $e'),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 5),
            ),
          );
        }
      }
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Funcionário "$nome" cadastrado com sucesso!${temAcesso ? " Acesso ao sistema criado." : ""}'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _atualizarFuncionario(
    Funcionario funcionario,
    String nome,
    String? telefone,
    String? email,
    String? senha,
    String? observacoes,
    bool ativo,
    bool temAcesso,
    double porcentagemComissao,
    String tipoComissao,
    double valorComissao,
  ) async {
    final dataService = Provider.of<DataService>(context, listen: false);
    final authService = Provider.of<AuthService>(context, listen: false);

    final funcionarioAtualizado = funcionario.copyWith(
      nome: nome,
      telefone: telefone,
      email: email,
      senha: senha,
      observacoes: observacoes,
      ativo: ativo,
      temAcesso: temAcesso,
      porcentagemComissao: porcentagemComissao,
      tipoComissao: tipoComissao,
      valorComissao: valorComissao,
      updatedAt: DateTime.now(),
    );

    // Atualizar funcionário
    await dataService.updateFuncionario(funcionarioAtualizado);

    // Gerenciar usuário de acesso
    final empresaId = authService.empresaAtual?.id;
    if (empresaId != null) {
      // Buscar usuário existente
            final usuarios = authService.usuarios;
      final usuarioExistente = usuarios.firstWhere(
        (u) => u.funcionarioId == funcionario.id,
        orElse: () => Usuario(
          id: '',
          nome: '',
          email: '',
          senha: '',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );

      if (temAcesso && email != null && email.isNotEmpty) {
        // Criar ou atualizar usuário
        if (usuarioExistente.id.isEmpty) {
          // Criar novo usuário
          final novoUsuario = Usuario(
            id: 'func_${funcionario.id}',
            nome: nome,
            email: email.toLowerCase().trim(),
            senha: senha ?? '123456', // Senha padrão se não informada
            telefone: telefone,
            tipo: TipoUsuario.vendedor,
            empresaId: empresaId,
            funcionarioId: funcionario.id,
            ativo: ativo,
            isMaster: false,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          );
          await authService.adicionarUsuario(novoUsuario);
          debugPrint('>>> Usuário criado para funcionário: $nome');
        } else {
          // Atualizar usuário existente
          final usuarioAtualizado = usuarioExistente.copyWith(
            nome: nome,
            email: email.toLowerCase().trim(),
            senha: senha != null && senha.isNotEmpty ? senha : usuarioExistente.senha,
            telefone: telefone,
            ativo: ativo,
            updatedAt: DateTime.now(),
          );
          await authService.atualizarUsuario(usuarioAtualizado);
          debugPrint('>>> Usuário atualizado para funcionário: $nome');
        }
      } else if (!temAcesso && usuarioExistente.id.isNotEmpty) {
        // Remover acesso (desativar usuário)
        final usuarioDesativado = usuarioExistente.copyWith(
          ativo: false,
          updatedAt: DateTime.now(),
        );
        await authService.atualizarUsuario(usuarioDesativado);
        debugPrint('>>> Acesso removido do funcionário: $nome');
      }
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Funcionário atualizado com sucesso!'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  void _confirmarExcluirFuncionario(Funcionario funcionario) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF10151B),
        title: const Text(
          'Excluir Funcionário',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'Deseja realmente excluir o funcionário "${funcionario.nome}"?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              final dataService =
                  Provider.of<DataService>(context, listen: false);
              dataService.deleteFuncionario(funcionario.id);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Funcionário "${funcionario.nome}" excluído'),
                  backgroundColor: Colors.orange,
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
}

