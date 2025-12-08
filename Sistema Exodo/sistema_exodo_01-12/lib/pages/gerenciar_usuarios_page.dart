import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../models/usuario.dart';
import '../models/empresa.dart';
import '../theme.dart';

/// Página para gerenciar usuários de uma empresa
class GerenciarUsuariosPage extends StatefulWidget {
  final Empresa empresa;

  const GerenciarUsuariosPage({
    super.key,
    required this.empresa,
  });

  @override
  State<GerenciarUsuariosPage> createState() => _GerenciarUsuariosPageState();
}

class _GerenciarUsuariosPageState extends State<GerenciarUsuariosPage> {
  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    final usuarioAtual = authService.usuarioAtual;
    final isUsuarioMaster = usuarioAtual?.email.toLowerCase() == 'user';
    
    // Verificar se o usuário pode gerenciar usuários
    if (!isUsuarioMaster) {
      return AppTheme.appBackground(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            title: const Text('Gerenciar Usuários'),
          ),
          body: const Center(
            child: Text(
              'Apenas o administrador pode gerenciar usuários',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ),
      );
    }

    // Obter usuários da empresa
    final usuariosDaEmpresa = authService.getUsuariosDaEmpresa(widget.empresa.id);

    return AppTheme.appBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text('Usuários - ${widget.empresa.nomeExibicao}'),
          actions: [
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: 'Adicionar Usuário',
              onPressed: () => _mostrarDialogoCriarUsuario(context, authService),
            ),
          ],
        ),
        body: usuariosDaEmpresa.isEmpty
            ? _buildEmptyState(context, authService)
            : _buildListaUsuarios(context, usuariosDaEmpresa, authService),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, AuthService authService) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.person_outline,
            size: 64,
            color: Colors.white.withOpacity(0.3),
          ),
          const SizedBox(height: 16),
          Text(
            'Nenhum usuário cadastrado',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.white70,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Crie um usuário para esta empresa',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.white54,
                ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () => _mostrarDialogoCriarUsuario(context, authService),
            icon: const Icon(Icons.person_add),
            label: const Text('Criar Primeiro Usuário'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildListaUsuarios(
    BuildContext context,
    List<Usuario> usuarios,
    AuthService authService,
  ) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: usuarios.length,
      itemBuilder: (context, index) {
        final usuario = usuarios[index];
        return _buildUsuarioCard(context, usuario, authService);
      },
    );
  }

  Widget _buildUsuarioCard(
    BuildContext context,
    Usuario usuario,
    AuthService authService,
  ) {
    bool _senhaVisivel = false;
    
    return StatefulBuilder(
      builder: (context, setState) {
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: Colors.blueAccent.withOpacity(0.2),
              child: Icon(
                Icons.person,
                color: Colors.blueAccent,
              ),
            ),
            title: Text(
              usuario.nome,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  usuario.email,
                  style: TextStyle(color: Colors.white.withOpacity(0.7)),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Senha: ${_senhaVisivel ? usuario.senha : '••••••••'}',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.7),
                          fontSize: 12,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        _senhaVisivel ? Icons.visibility : Icons.visibility_off,
                        color: Colors.white54,
                        size: 18,
                      ),
                      onPressed: () {
                        setState(() {
                          _senhaVisivel = !_senhaVisivel;
                        });
                      },
                      tooltip: _senhaVisivel ? 'Ocultar senha' : 'Mostrar senha',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: usuario.ativo
                            ? Colors.green.withOpacity(0.2)
                            : Colors.red.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        usuario.ativo ? 'Ativo' : 'Inativo',
                        style: TextStyle(
                          color: usuario.ativo ? Colors.green : Colors.red,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.blueAccent.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        usuario.tipoNome,
                        style: const TextStyle(
                          color: Colors.blueAccent,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            trailing: PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: Colors.white54),
              itemBuilder: (context) => [
                PopupMenuItem<String>(
                  value: 'editar',
                  child: const Row(
                    children: [
                      Icon(Icons.edit, size: 20),
                      SizedBox(width: 8),
                      Text('Editar'),
                    ],
                  ),
                ),
                PopupMenuItem<String>(
                  value: usuario.ativo ? 'desativar' : 'ativar',
                  child: Row(
                    children: [
                      Icon(
                        usuario.ativo ? Icons.block : Icons.check_circle,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(usuario.ativo ? 'Desativar' : 'Ativar'),
                    ],
                  ),
                ),
                const PopupMenuDivider(),
                PopupMenuItem<String>(
                  value: 'excluir',
                  child: const Row(
                    children: [
                      Icon(Icons.delete, size: 20, color: Colors.red),
                      SizedBox(width: 8),
                      Text('Excluir', style: TextStyle(color: Colors.red)),
                    ],
                  ),
                ),
              ],
              onSelected: (value) {
                switch (value) {
                  case 'editar':
                    _mostrarDialogoEditarUsuario(context, authService, usuario);
                    break;
                  case 'ativar':
                  case 'desativar':
                    _alterarStatusUsuario(context, authService, usuario);
                    break;
                  case 'excluir':
                    _confirmarExclusaoUsuario(context, authService, usuario);
                    break;
                }
              },
            ),
          ),
        );
      },
    );
  }

  void _mostrarDialogoCriarUsuario(
    BuildContext context,
    AuthService authService,
  ) {
    final formKey = GlobalKey<FormState>();
    final nomeController = TextEditingController();
    final emailController = TextEditingController();
    final senhaController = TextEditingController();
    final telefoneController = TextEditingController();
    TipoUsuario tipoSelecionado = TipoUsuario.operador;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E2E),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text(
            'Criar Usuário',
            style: TextStyle(color: Colors.white),
          ),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: nomeController,
                    decoration: const InputDecoration(
                      labelText: 'Nome',
                      labelStyle: TextStyle(color: Colors.white70),
                      enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: Colors.white30),
                      ),
                      focusedBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: Colors.blueAccent),
                      ),
                    ),
                    style: const TextStyle(color: Colors.white),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Nome é obrigatório';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: emailController,
                    decoration: const InputDecoration(
                      labelText: 'Email/Login',
                      labelStyle: TextStyle(color: Colors.white70),
                      enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: Colors.white30),
                      ),
                      focusedBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: Colors.blueAccent),
                      ),
                    ),
                    style: const TextStyle(color: Colors.white),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Email é obrigatório';
                      }
                      // Verificar se já existe
                      final usuarios = authService.getUsuariosDaEmpresa(widget.empresa.id);
                      if (usuarios.any((u) => u.email.toLowerCase() == value.toLowerCase())) {
                        return 'Email já cadastrado';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: senhaController,
                    decoration: const InputDecoration(
                      labelText: 'Senha',
                      labelStyle: TextStyle(color: Colors.white70),
                      enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: Colors.white30),
                      ),
                      focusedBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: Colors.blueAccent),
                      ),
                    ),
                    style: const TextStyle(color: Colors.white),
                    obscureText: true,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Senha é obrigatória';
                      }
                      if (value.length < 3) {
                        return 'Senha deve ter pelo menos 3 caracteres';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: telefoneController,
                    decoration: const InputDecoration(
                      labelText: 'Telefone (opcional)',
                      labelStyle: TextStyle(color: Colors.white70),
                      enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: Colors.white30),
                      ),
                      focusedBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: Colors.blueAccent),
                      ),
                    ),
                    style: const TextStyle(color: Colors.white),
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<TipoUsuario>(
                    value: tipoSelecionado,
                    decoration: const InputDecoration(
                      labelText: 'Tipo de Usuário',
                      labelStyle: TextStyle(color: Colors.white70),
                      enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: Colors.white30),
                      ),
                      focusedBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: Colors.blueAccent),
                      ),
                    ),
                    dropdownColor: const Color(0xFF2A2A3E),
                    style: const TextStyle(color: Colors.white),
                    items: TipoUsuario.values.map((tipo) {
                      return DropdownMenuItem(
                        value: tipo,
                        child: Text(tipo.nome),
                      );
                    }).toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() {
                          tipoSelecionado = value;
                        });
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                'Cancelar',
                style: TextStyle(color: Colors.white54),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                if (formKey.currentState!.validate()) {
                  final agora = DateTime.now();
                  final novoUsuario = Usuario(
                    id: DateTime.now().millisecondsSinceEpoch.toString(),
                    nome: nomeController.text.trim(),
                    email: emailController.text.trim().toLowerCase(),
                    senha: senhaController.text,
                    telefone: telefoneController.text.trim().isEmpty
                        ? null
                        : telefoneController.text.trim(),
                    tipo: tipoSelecionado,
                    empresaId: widget.empresa.id,
                    ativo: true,
                    createdAt: agora,
                    updatedAt: agora,
                  );

                  try {
                    await authService.adicionarUsuario(novoUsuario);
                    if (context.mounted) {
                      Navigator.of(context).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Usuário criado com sucesso!'),
                          backgroundColor: Colors.green,
                        ),
                      );
                      setState(() {});
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Erro ao criar usuário: $e'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueAccent,
                foregroundColor: Colors.white,
              ),
              child: const Text('Criar'),
            ),
          ],
        ),
      ),
    );
  }

  void _mostrarDialogoEditarUsuario(
    BuildContext context,
    AuthService authService,
    Usuario usuario,
  ) {
    final formKey = GlobalKey<FormState>();
    final nomeController = TextEditingController(text: usuario.nome);
    final emailController = TextEditingController(text: usuario.email);
    final senhaController = TextEditingController();
    final telefoneController = TextEditingController(text: usuario.telefone ?? '');
    TipoUsuario tipoSelecionado = usuario.tipo;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E2E),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text(
            'Editar Usuário',
            style: TextStyle(color: Colors.white),
          ),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: nomeController,
                    decoration: const InputDecoration(
                      labelText: 'Nome',
                      labelStyle: TextStyle(color: Colors.white70),
                      enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: Colors.white30),
                      ),
                      focusedBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: Colors.blueAccent),
                      ),
                    ),
                    style: const TextStyle(color: Colors.white),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Nome é obrigatório';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: emailController,
                    decoration: const InputDecoration(
                      labelText: 'Email/Login',
                      labelStyle: TextStyle(color: Colors.white70),
                      enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: Colors.white30),
                      ),
                      focusedBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: Colors.blueAccent),
                      ),
                    ),
                    style: const TextStyle(color: Colors.white),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Email é obrigatório';
                      }
                      // Verificar se já existe (exceto o próprio usuário)
                      final usuarios = authService.getUsuariosDaEmpresa(widget.empresa.id);
                      if (usuarios.any((u) =>
                          u.id != usuario.id &&
                          u.email.toLowerCase() == value.toLowerCase())) {
                        return 'Email já cadastrado';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: senhaController,
                    decoration: const InputDecoration(
                      labelText: 'Nova Senha (deixe vazio para manter)',
                      labelStyle: TextStyle(color: Colors.white70),
                      enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: Colors.white30),
                      ),
                      focusedBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: Colors.blueAccent),
                      ),
                    ),
                    style: const TextStyle(color: Colors.white),
                    obscureText: true,
                    validator: (value) {
                      if (value != null && value.isNotEmpty && value.length < 3) {
                        return 'Senha deve ter pelo menos 3 caracteres';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: telefoneController,
                    decoration: const InputDecoration(
                      labelText: 'Telefone (opcional)',
                      labelStyle: TextStyle(color: Colors.white70),
                      enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: Colors.white30),
                      ),
                      focusedBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: Colors.blueAccent),
                      ),
                    ),
                    style: const TextStyle(color: Colors.white),
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<TipoUsuario>(
                    value: tipoSelecionado,
                    decoration: const InputDecoration(
                      labelText: 'Tipo de Usuário',
                      labelStyle: TextStyle(color: Colors.white70),
                      enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: Colors.white30),
                      ),
                      focusedBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: Colors.blueAccent),
                      ),
                    ),
                    dropdownColor: const Color(0xFF2A2A3E),
                    style: const TextStyle(color: Colors.white),
                    items: TipoUsuario.values.map((tipo) {
                      return DropdownMenuItem(
                        value: tipo,
                        child: Text(tipo.nome),
                      );
                    }).toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() {
                          tipoSelecionado = value;
                        });
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                'Cancelar',
                style: TextStyle(color: Colors.white54),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                if (formKey.currentState!.validate()) {
                  final usuarioAtualizado = usuario.copyWith(
                    nome: nomeController.text.trim(),
                    email: emailController.text.trim().toLowerCase(),
                    senha: senhaController.text.isEmpty
                        ? usuario.senha
                        : senhaController.text,
                    telefone: telefoneController.text.trim().isEmpty
                        ? null
                        : telefoneController.text.trim(),
                    tipo: tipoSelecionado,
                    updatedAt: DateTime.now(),
                  );

                  try {
                    await authService.atualizarUsuario(usuarioAtualizado);
                    if (context.mounted) {
                      Navigator.of(context).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Usuário atualizado com sucesso!'),
                          backgroundColor: Colors.green,
                        ),
                      );
                      setState(() {});
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Erro ao atualizar usuário: $e'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueAccent,
                foregroundColor: Colors.white,
              ),
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
  }

  void _alterarStatusUsuario(
    BuildContext context,
    AuthService authService,
    Usuario usuario,
  ) async {
    final novoStatus = !usuario.ativo;
    final usuarioAtualizado = usuario.copyWith(
      ativo: novoStatus,
      updatedAt: DateTime.now(),
    );

    try {
      await authService.atualizarUsuario(usuarioAtualizado);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              novoStatus
                  ? 'Usuário ativado com sucesso!'
                  : 'Usuário desativado com sucesso!',
            ),
            backgroundColor: Colors.green,
          ),
        );
        setState(() {});
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
  }

  void _confirmarExclusaoUsuario(
    BuildContext context,
    AuthService authService,
    Usuario usuario,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Text(
          'Confirmar Exclusão',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'Deseja realmente excluir o usuário "${usuario.nome}"?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text(
              'Cancelar',
              style: TextStyle(color: Colors.white54),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                await authService.removerUsuario(usuario.id);
                if (context.mounted) {
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Usuário excluído com sucesso!'),
                      backgroundColor: Colors.green,
                    ),
                  );
                  setState(() {});
                }
              } catch (e) {
                if (context.mounted) {
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Erro ao excluir usuário: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
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

