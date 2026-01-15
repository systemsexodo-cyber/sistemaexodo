import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/usuario.dart';
import '../models/permissao.dart';
import '../models/tela_sistema.dart';
import '../services/auth_service.dart';
import '../services/permission_service.dart';
import '../theme.dart';

/// Página para gerenciar permissões de usuários
class GerenciarPermissoesPage extends StatefulWidget {
  final Usuario? usuario; // Se fornecido, edita apenas este usuário

  const GerenciarPermissoesPage({super.key, this.usuario});

  @override
  State<GerenciarPermissoesPage> createState() => _GerenciarPermissoesPageState();
}

class _GerenciarPermissoesPageState extends State<GerenciarPermissoesPage> {
  final PermissionService _permissionService = PermissionService();
  Usuario? _usuarioSelecionado;
  Set<String> _permissoesSelecionadas = {};
  Set<String> _permissoesNegadas = {};
  Set<String> _telasOcultas = {}; // Telas que o usuário não pode ver
  bool _carregando = false;
  final TextEditingController _buscaController = TextEditingController();
  String _filtroCategoria = 'Todas';

  @override
  void initState() {
    super.initState();
    _usuarioSelecionado = widget.usuario;
    if (_usuarioSelecionado != null) {
      _carregarPermissoesUsuario();
    }
    _buscaController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _buscaController.dispose();
    super.dispose();
  }

  void _carregarPermissoesUsuario() {
    if (_usuarioSelecionado == null) return;

    setState(() {
      _permissoesSelecionadas = Set.from(
        _usuarioSelecionado!.permissoesPersonalizadas ?? {},
      );
      _permissoesNegadas = Set.from(
        _usuarioSelecionado!.permissoesNegadas ?? {},
      );
      _telasOcultas = Set.from(
        _usuarioSelecionado!.telasOcultas ?? {},
      );
    });
  }

  Future<void> _salvarPermissoes() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final usuarioAtual = authService.usuarioAtual;
    
    // Verificar se o usuário atual é master, "user" ou administrador
    final podeGerenciar = usuarioAtual != null && 
        (usuarioAtual.isMaster || 
         usuarioAtual.email.toLowerCase() == 'user' ||
         usuarioAtual.tipo == TipoUsuario.administrador);
    
    if (!podeGerenciar) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Apenas o usuário master, "user" ou administrador pode gerenciar permissões'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    
    if (_usuarioSelecionado == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecione um usuário primeiro'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _carregando = true;
    });

    try {
      final authService = Provider.of<AuthService>(context, listen: false);

      // Atualizar usuário com novas permissões
      final usuarioAtualizado = _usuarioSelecionado!.copyWith(
        permissoesPersonalizadas: _permissoesSelecionadas.isEmpty
            ? null
            : _permissoesSelecionadas,
        permissoesNegadas: _permissoesNegadas.isEmpty
            ? null
            : _permissoesNegadas,
        telasOcultas: _telasOcultas.isEmpty
            ? null
            : _telasOcultas.toList(),
        updatedAt: DateTime.now(),
      );

      // Salvar no serviço
      await authService.atualizarUsuario(usuarioAtualizado);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Permissões salvas com sucesso!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao salvar permissões: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _carregando = false;
        });
      }
    }
  }

  void _togglePermissao(TipoPermissao permissao, bool adicionar) {
    setState(() {
      final codigo = permissao.codigo;
      
      if (adicionar) {
        // Adicionar permissão personalizada
        _permissoesSelecionadas.add(codigo);
        _permissoesNegadas.remove(codigo); // Remove da lista negada se estiver
      } else {
        // Remover permissão personalizada
        _permissoesSelecionadas.remove(codigo);
        
        // Se a permissão está nas permissões padrão do tipo, adicionar à lista negada
        final permissoesPadrao = _permissionService.obterPermissoesPadrao(
          _usuarioSelecionado!.tipo,
        );
        if (permissoesPadrao.contains(codigo)) {
          _permissoesNegadas.add(codigo);
        }
      }
    });
  }

  bool _temPermissao(TipoPermissao permissao) {
    if (_usuarioSelecionado == null) return false;
    
    final codigo = permissao.codigo;
    
    // Se está nas permissões personalizadas, tem
    if (_permissoesSelecionadas.contains(codigo)) {
      return true;
    }
    
    // Se está nas permissões negadas, não tem
    if (_permissoesNegadas.contains(codigo)) {
      return false;
    }
    
    // Verificar permissões padrão do tipo
    final permissoesPadrao = _permissionService.obterPermissoesPadrao(
      _usuarioSelecionado!.tipo,
    );
    return permissoesPadrao.contains(codigo);
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    final usuarioAtual = authService.usuarioAtual;
    
    // Verificar se o usuário atual é master, "user" ou administrador
    final podeGerenciar = usuarioAtual != null && 
        (usuarioAtual.isMaster || 
         usuarioAtual.email.toLowerCase() == 'user' ||
         usuarioAtual.tipo == TipoUsuario.administrador);
    
    if (!podeGerenciar) {
      return AppTheme.appBackground(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            title: const Text('Gerenciar Permissões'),
            centerTitle: true,
            backgroundColor: Colors.transparent,
            elevation: 0,
          ),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.lock_outline,
                    size: 80,
                    color: Colors.red.shade300,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Acesso Restrito',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Apenas o usuário master, "user" ou administrador pode gerenciar permissões de usuários.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    
    // Master e "user" podem ver TODOS os usuários de TODAS as empresas
    final todosUsuarios = authService.usuarios.where((u) => u.ativo).toList();
    final isUser = usuarioAtual.email.toLowerCase() == 'user';
    
    final permissoesPorCategoria = _permissionService.obterPermissoesPorCategoria();

    return AppTheme.appBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Gerenciar Permissões'),
          centerTitle: true,
          backgroundColor: Colors.transparent,
          elevation: 0,
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 16.0),
              child: Center(
                child: Chip(
                  avatar: Icon(
                    isUser ? Icons.person : Icons.admin_panel_settings,
                    size: 18,
                    color: isUser ? Colors.blue : Colors.amber,
                  ),
                  label: Text(
                    isUser ? 'User - Todas as Empresas' : 'Master - Todas as Empresas',
                    style: TextStyle(fontSize: 12, color: Colors.white),
                  ),
                  backgroundColor: isUser ? Colors.blue.shade700 : Colors.amber.shade700,
                ),
              ),
            ),
          ],
        ),
        body: _usuarioSelecionado == null && widget.usuario == null
            ? _buildSelecaoUsuario(todosUsuarios)
            : _buildEditorPermissoes(permissoesPorCategoria),
      ),
    );
  }

  Widget _buildSelecaoUsuario(List<Usuario> usuarios) {
    if (usuarios.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.people_outline,
                size: 80,
                color: Colors.white54,
              ),
              const SizedBox(height: 16),
              Text(
                'Nenhum usuário encontrado',
                style: TextStyle(
                  fontSize: 18,
                  color: Colors.white70,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Não há usuários cadastrados no sistema.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.white54,
                ),
              ),
            ],
          ),
        ),
      );
    }
    
    // Agrupar usuários por empresa
    final usuariosPorEmpresa = <String, List<Usuario>>{};
    final authService = Provider.of<AuthService>(context, listen: false);
    
    for (final usuario in usuarios) {
      final empresaId = usuario.empresaId ?? 'Sem Empresa';
      if (!usuariosPorEmpresa.containsKey(empresaId)) {
        usuariosPorEmpresa[empresaId] = [];
      }
      usuariosPorEmpresa[empresaId]!.add(usuario);
    }
    
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: usuariosPorEmpresa.length,
      itemBuilder: (context, index) {
        final empresaId = usuariosPorEmpresa.keys.elementAt(index);
        final usuariosDaEmpresa = usuariosPorEmpresa[empresaId]!;
        
        // Buscar nome da empresa
        String nomeEmpresa = 'Sem Empresa';
        final empresasPermitidas = authService.getEmpresasDoUsuario();
        if (empresaId != 'Sem Empresa' && empresasPermitidas.isNotEmpty) {
          try {
            final empresa = empresasPermitidas.firstWhere(
              (e) => e.id == empresaId,
            );
            nomeEmpresa = empresa.nomeExibicao;
          } catch (e) {
            nomeEmpresa = 'Empresa não encontrada';
          }
        }
        
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 16, bottom: 8, left: 4),
              child: Row(
                children: [
                  Icon(
                    Icons.business,
                    size: 18,
                    color: Colors.blue.shade300,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    nomeEmpresa,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue.shade200,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade700,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${usuariosDaEmpresa.length} usuário(s)',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            ...usuariosDaEmpresa.map((usuario) {
              final isMaster = usuario.isMaster;
              
              return Card(
                margin: const EdgeInsets.only(bottom: 8, left: 16),
                child: ListTile(
                  leading: Stack(
                    children: [
                      CircleAvatar(
                        backgroundColor: _getColorPorTipo(usuario.tipo),
                        child: Text(
                          usuario.nome[0].toUpperCase(),
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                      if (isMaster)
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              color: Colors.amber,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 1),
                            ),
                            child: Icon(
                              Icons.star,
                              size: 12,
                              color: Colors.white,
                            ),
                          ),
                        ),
                    ],
                  ),
                  title: Row(
                    children: [
                      Expanded(child: Text(usuario.nome)),
                      if (isMaster)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.amber.shade700,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            'MASTER',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                    ],
                  ),
                  subtitle: Text('${usuario.tipo.nome} • ${usuario.email}'),
                  trailing: const Icon(Icons.arrow_forward_ios),
                  onTap: () {
                    setState(() {
                      _usuarioSelecionado = usuario;
                      _carregarPermissoesUsuario();
                    });
                  },
                ),
              );
            }).toList(),
            const SizedBox(height: 8),
          ],
        );
      },
    );
  }

  Widget _buildEditorPermissoes(Map<String, List<TipoPermissao>> permissoesPorCategoria) {
    return Column(
      children: [
        // Cabeçalho com informações do usuário
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.black26,
          child: Column(
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: _getColorPorTipo(_usuarioSelecionado!.tipo),
                    child: Text(
                      _usuarioSelecionado!.nome[0].toUpperCase(),
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _usuarioSelecionado!.nome,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '${_usuarioSelecionado!.tipo.nome} • ${_usuarioSelecionado!.email}',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (widget.usuario == null)
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        setState(() {
                          _usuarioSelecionado = null;
                          _permissoesSelecionadas.clear();
                          _permissoesNegadas.clear();
                          _telasOcultas.clear();
                        });
                      },
                    ),
                ],
              ),
              // Mostrar empresa do usuário
              if (_usuarioSelecionado!.empresaId != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      Icons.business,
                      size: 16,
                      color: Colors.blue.shade300,
                    ),
                    const SizedBox(width: 8),
                    Builder(
                      builder: (context) {
                        final authService = Provider.of<AuthService>(context, listen: false);
                        String nomeEmpresa = 'Empresa não encontrada';
                        final empresasPermitidas = authService.getEmpresasDoUsuario();
                        if (empresasPermitidas.isNotEmpty) {
                          try {
                            final empresa = empresasPermitidas.firstWhere(
                              (e) => e.id == _usuarioSelecionado!.empresaId,
                            );
                            nomeEmpresa = empresa.nomeExibicao;
                          } catch (e) {
                            nomeEmpresa = 'Empresa não encontrada';
                          }
                        }
                        return Text(
                          'Empresa: $nomeEmpresa',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.blue.shade200,
                            fontStyle: FontStyle.italic,
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),

        // Estatísticas de permissões
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: _buildEstatisticasPermissoes(),
        ),

        // Barra de busca e filtros
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.black26,
          child: Column(
            children: [
              TextField(
                controller: _buscaController,
                decoration: InputDecoration(
                  hintText: 'Buscar permissões...',
                  hintStyle: TextStyle(color: Colors.white54),
                  prefixIcon: Icon(Icons.search, color: Colors.white54),
                  suffixIcon: _buscaController.text.isNotEmpty
                      ? IconButton(
                          icon: Icon(Icons.clear, color: Colors.white54),
                          onPressed: () {
                            _buscaController.clear();
                            setState(() {});
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.1),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.white30),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.white30),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.blueAccent),
                  ),
                ),
                style: TextStyle(color: Colors.white),
                onChanged: (value) => setState(() {}),
              ),
              const SizedBox(height: 12),
              // Filtro de categoria
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildFiltroChip('Todas', _filtroCategoria == 'Todas'),
                    const SizedBox(width: 8),
                    ...permissoesPorCategoria.keys.map((cat) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _buildFiltroChip(cat, _filtroCategoria == cat),
                    )),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // Ações rápidas
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _marcarTodasPermissoes,
                      icon: Icon(Icons.check_box, size: 18),
                      label: Text('Marcar Todas'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.green,
                        side: BorderSide(color: Colors.green),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _desmarcarTodasPermissoes,
                      icon: Icon(Icons.check_box_outline_blank, size: 18),
                      label: Text('Desmarcar Todas'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: BorderSide(color: Colors.red),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _resetarParaPadrao,
                      icon: Icon(Icons.refresh, size: 18),
                      label: Text('Resetar'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.blue,
                        side: BorderSide(color: Colors.blue),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // Área scrollável com lista de permissões e seção de telas
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              children: [
                // Lista de permissões por categoria (com filtros)
                _buildListaPermissoesFiltrada(permissoesPorCategoria),

        // Seção de controle de telas
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.black26,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.visibility_off, color: Colors.orange, size: 24),
                  const SizedBox(width: 8),
                  const Text(
                    'Ocultar Telas',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${_telasOcultas.length} oculta(s)',
                      style: TextStyle(
                        color: Colors.orange,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Selecione as telas que este usuário NÃO poderá ver ou acessar:',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.white70,
                ),
              ),
              const SizedBox(height: 12),
              ...TelaSistema.porCategoria().entries.map((entry) {
                final categoria = entry.key;
                final telas = entry.value;
                return _buildCategoriaTelas(categoria, telas);
              }),
            ],
          ),
        ),
              ],
            ),
          ),
        ),

        // Botão de salvar
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.black26,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 10,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _carregando ? null : _salvarPermissoes,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: Colors.blue,
              ),
              child: _carregando
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Text(
                      'Salvar Permissões',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEstatisticasPermissoes() {
    if (_usuarioSelecionado == null) return const SizedBox.shrink();
    
    final permissoesPadrao = _permissionService.obterPermissoesPadrao(_usuarioSelecionado!.tipo);
    final totalPadrao = permissoesPadrao.length;
    final totalPersonalizadas = _permissoesSelecionadas.length;
    final totalNegadas = _permissoesNegadas.length;
    final totalAtivas = _contarPermissoesAtivas();
    final totalDisponiveis = TipoPermissao.values.length;
    final percentualAtivas = totalDisponiveis > 0 
        ? ((totalAtivas / totalDisponiveis) * 100).toStringAsFixed(1)
        : '0.0';
    
    return Row(
      children: [
        Expanded(
          child: _buildEstatisticaCard(
            'Total Ativas',
            '$totalAtivas/$totalDisponiveis',
            Colors.green,
            Icons.check_circle,
            subtitle: '$percentualAtivas%',
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildEstatisticaCard(
            'Padrão',
            totalPadrao.toString(),
            Colors.blue,
            Icons.settings,
            subtitle: 'Tipo: ${_usuarioSelecionado!.tipo.nome}',
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildEstatisticaCard(
            'Personalizadas',
            totalPersonalizadas.toString(),
            Colors.amber,
            Icons.star,
            subtitle: 'Adicionadas',
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildEstatisticaCard(
            'Negadas',
            totalNegadas.toString(),
            Colors.red,
            Icons.block,
            subtitle: 'Removidas',
          ),
        ),
      ],
    );
  }

  Widget _buildEstatisticaCard(
    String label,
    String value,
    Color color,
    IconData icon, {
    String? subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.4), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(width: 6),
              Text(
                value,
                style: TextStyle(
                  color: color,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(
                color: Colors.white54,
                fontSize: 9,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }

  int _contarPermissoesAtivas() {
    if (_usuarioSelecionado == null) return 0;
    
    int total = 0;
    
    for (final permissao in TipoPermissao.values) {
      if (_temPermissao(permissao)) {
        total++;
      }
    }
    
    return total;
  }

  Widget _buildCategoriaPermissoes(String categoria, List<TipoPermissao> permissoes) {
    // As permissões já vêm filtradas do método _buildListaPermissoesFiltrada
    final permissoesFiltradas = permissoes;
    
    if (permissoesFiltradas.isEmpty) return const SizedBox.shrink();
    
    final totalNaCategoria = permissoesFiltradas.length;
    final ativasNaCategoria = permissoesFiltradas.where((p) => _temPermissao(p)).length;
    
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: ExpansionTile(
        leading: Icon(
          _getIconeCategoria(categoria),
          color: Colors.blueAccent,
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                categoria,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.blueAccent.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '$ativasNaCategoria/$totalNaCategoria',
                style: TextStyle(
                  color: Colors.blueAccent,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        subtitle: permissoesFiltradas.length < permissoes.length
            ? Text(
                '${permissoesFiltradas.length} de ${permissoes.length} permissões',
                style: TextStyle(fontSize: 12, color: Colors.white54),
              )
            : null,
        children: [
          // Botão de selecionar todas
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      _selecionarTodasCategoria(permissoesFiltradas, true);
                    },
                    icon: Icon(Icons.check_box, size: 18),
                    label: Text('Selecionar Todas'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.green,
                      side: BorderSide(color: Colors.green),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      _selecionarTodasCategoria(permissoesFiltradas, false);
                    },
                    icon: Icon(Icons.check_box_outline_blank, size: 18),
                    label: Text('Desselecionar Todas'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: BorderSide(color: Colors.red),
                    ),
                  ),
                ),
              ],
            ),
          ),
          ...permissoesFiltradas.map((permissao) => _buildPermissaoItem(permissao)),
        ],
      ),
    );
  }

  Widget _buildPermissaoItem(TipoPermissao permissao) {
    final temPermissao = _temPermissao(permissao);
    final isPersonalizada = _permissoesSelecionadas.contains(permissao.codigo);
    final isNegada = _permissoesNegadas.contains(permissao.codigo);
    
    final permissoesPadrao = _usuarioSelecionado != null
        ? _permissionService.obterPermissoesPadrao(_usuarioSelecionado!.tipo)
        : <String>{};
    final isPadrao = permissoesPadrao.contains(permissao.codigo) && !isNegada && !isPersonalizada;
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isPersonalizada
            ? Colors.amber.withOpacity(0.1)
            : isNegada
                ? Colors.red.withOpacity(0.1)
                : isPadrao
                    ? Colors.blue.withOpacity(0.1)
                    : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isPersonalizada
              ? Colors.amber.withOpacity(0.3)
              : isNegada
                  ? Colors.red.withOpacity(0.3)
                  : isPadrao
                      ? Colors.blue.withOpacity(0.3)
                      : Colors.transparent,
          width: 1,
        ),
      ),
      child: CheckboxListTile(
        title: Row(
          children: [
            Expanded(
              child: Text(
                permissao.nome,
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  color: temPermissao ? Colors.white : Colors.white70,
                ),
              ),
            ),
            if (isPersonalizada)
              Tooltip(
                message: 'Permissão personalizada (adicionada manualmente)',
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.amber.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.star, size: 12, color: Colors.amber),
                      const SizedBox(width: 4),
                      Text(
                        'Personalizada',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.amber,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (isNegada)
              Tooltip(
                message: 'Permissão negada (removida do padrão)',
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.block, size: 12, color: Colors.red),
                      const SizedBox(width: 4),
                      Text(
                        'Negada',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.red,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (isPadrao && !isNegada && !isPersonalizada)
              Tooltip(
                message: 'Permissão padrão do tipo de usuário',
                child: Icon(
                  Icons.info_outline,
                  size: 16,
                  color: Colors.blueAccent,
                ),
              ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              permissao.descricao,
              style: TextStyle(fontSize: 12, color: Colors.white54),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(
                  Icons.info_outline,
                  size: 12,
                  color: Colors.white38,
                ),
                const SizedBox(width: 4),
                Text(
                  'Código: ${permissao.codigo}',
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.white38,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ],
        ),
        value: temPermissao,
        onChanged: (value) {
          _togglePermissao(permissao, value ?? false);
        },
        activeColor: Colors.green,
        checkColor: Colors.white,
        secondary: Tooltip(
          message: permissao.descricao,
          child: Icon(
            Icons.help_outline,
            size: 20,
            color: Colors.white54,
          ),
        ),
      ),
    );
  }

  IconData _getIconeCategoria(String categoria) {
    switch (categoria.toLowerCase()) {
      case 'vendas':
        return Icons.shopping_cart;
      case 'produtos':
        return Icons.inventory;
      case 'clientes':
        return Icons.person;
      case 'estoque':
        return Icons.warehouse;
      case 'financeiro':
        return Icons.account_balance_wallet;
      case 'relatórios':
        return Icons.bar_chart;
      case 'configurações':
        return Icons.settings;
      case 'nfce':
      case 'nfc-e':
        return Icons.receipt;
      case 'caixa':
        return Icons.point_of_sale;
      case 'cozinha':
      case 'bar':
        return Icons.restaurant;
      default:
        return Icons.category;
    }
  }

  void _selecionarTodasCategoria(List<TipoPermissao> permissoes, bool selecionar) {
    setState(() {
      for (final permissao in permissoes) {
        if (selecionar) {
          // Adicionar como personalizada se não for padrão
          final permissoesPadrao = _usuarioSelecionado != null
              ? _permissionService.obterPermissoesPadrao(_usuarioSelecionado!.tipo)
              : <String>{};
          
          if (!permissoesPadrao.contains(permissao.codigo)) {
            _permissoesSelecionadas.add(permissao.codigo);
          }
          _permissoesNegadas.remove(permissao.codigo);
        } else {
          // Remover personalizada e adicionar como negada
          _permissoesSelecionadas.remove(permissao.codigo);
          final permissoesPadrao = _usuarioSelecionado != null
              ? _permissionService.obterPermissoesPadrao(_usuarioSelecionado!.tipo)
              : <String>{};
          
          if (permissoesPadrao.contains(permissao.codigo)) {
            _permissoesNegadas.add(permissao.codigo);
          }
        }
      }
    });
  }

  Color _getColorPorTipo(TipoUsuario tipo) {
    switch (tipo) {
      case TipoUsuario.administrador:
        return Colors.red;
      case TipoUsuario.gerente:
        return Colors.orange;
      case TipoUsuario.operador:
        return Colors.blue;
      case TipoUsuario.vendedor:
        return Colors.green;
    }
  }

  // Ações rápidas globais
  void _marcarTodasPermissoes() {
    setState(() {
      final permissoesPadrao = _usuarioSelecionado != null
          ? _permissionService.obterPermissoesPadrao(_usuarioSelecionado!.tipo)
          : <String>{};
      
      for (final permissao in TipoPermissao.values) {
        if (!permissoesPadrao.contains(permissao.codigo)) {
          _permissoesSelecionadas.add(permissao.codigo);
        }
        _permissoesNegadas.remove(permissao.codigo);
      }
    });
  }

  void _desmarcarTodasPermissoes() {
    setState(() {
      final permissoesPadrao = _usuarioSelecionado != null
          ? _permissionService.obterPermissoesPadrao(_usuarioSelecionado!.tipo)
          : <String>{};
      
      _permissoesSelecionadas.clear();
      _permissoesNegadas.clear();
      
      // Negar todas as permissões padrão
      for (final codigo in permissoesPadrao) {
        _permissoesNegadas.add(codigo);
      }
    });
  }

  void _resetarParaPadrao() {
    setState(() {
      _permissoesSelecionadas.clear();
      _permissoesNegadas.clear();
    });
  }

  Widget _buildFiltroChip(String label, bool selecionado) {
    return FilterChip(
      label: Text(label),
      selected: selecionado,
      onSelected: (value) {
        setState(() {
          _filtroCategoria = value ? label : 'Todas';
        });
      },
      selectedColor: Colors.blueAccent.withOpacity(0.3),
      checkmarkColor: Colors.blueAccent,
      labelStyle: TextStyle(
        color: selecionado ? Colors.blueAccent : Colors.white70,
        fontWeight: selecionado ? FontWeight.bold : FontWeight.normal,
      ),
    );
  }

  Widget _buildListaPermissoesFiltrada(Map<String, List<TipoPermissao>> permissoesPorCategoria) {
    final busca = _buscaController.text.toLowerCase();
    final categoriasFiltradas = <String, List<TipoPermissao>>{};
    
    for (final entry in permissoesPorCategoria.entries) {
      final categoria = entry.key;
      final permissoes = entry.value;
      
      // Filtrar por categoria
      if (_filtroCategoria != 'Todas' && categoria != _filtroCategoria) {
        continue;
      }
      
      // Filtrar por busca
      final permissoesFiltradas = busca.isEmpty
          ? permissoes
          : permissoes.where((p) =>
              p.nome.toLowerCase().contains(busca) ||
              p.descricao.toLowerCase().contains(busca) ||
              p.codigo.toLowerCase().contains(busca)).toList();
      
      if (permissoesFiltradas.isNotEmpty) {
        categoriasFiltradas[categoria] = permissoesFiltradas;
      }
    }
    
    if (categoriasFiltradas.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.search_off, size: 64, color: Colors.white54),
              const SizedBox(height: 16),
              Text(
                'Nenhuma permissão encontrada',
                style: TextStyle(color: Colors.white70, fontSize: 16),
              ),
              if (busca.isNotEmpty || _filtroCategoria != 'Todas') ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _buscaController.clear();
                      _filtroCategoria = 'Todas';
                    });
                  },
                  child: Text('Limpar filtros'),
                ),
              ],
            ],
          ),
        ),
      );
    }
    
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      itemCount: categoriasFiltradas.length,
      itemBuilder: (context, index) {
        final categoria = categoriasFiltradas.keys.elementAt(index);
        final permissoes = categoriasFiltradas[categoria]!;
        
        return _buildCategoriaPermissoes(categoria, permissoes);
      },
    );
  }

  Widget _buildCategoriaTelas(String categoria, List<TelaSistema> telas) {
    final telasOcultasNaCategoria = telas.where((t) => _telasOcultas.contains(t.codigo)).length;
    
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: const Color(0xFF2A2A3E),
      child: ExpansionTile(
        leading: Icon(
          _getIconeCategoriaTela(categoria),
          color: Colors.orange,
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                categoria,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
            if (telasOcultasNaCategoria > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$telasOcultasNaCategoria/${telas.length}',
                  style: TextStyle(
                    color: Colors.orange,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
        children: telas.map((tela) {
          final isOculta = _telasOcultas.contains(tela.codigo);
          return CheckboxListTile(
            title: Text(
              tela.nome,
              style: TextStyle(
                color: isOculta ? Colors.red.shade300 : Colors.white,
                decoration: isOculta ? TextDecoration.lineThrough : null,
              ),
            ),
            value: isOculta,
            onChanged: (value) {
              setState(() {
                if (value == true) {
                  _telasOcultas.add(tela.codigo);
                } else {
                  _telasOcultas.remove(tela.codigo);
                }
              });
            },
            activeColor: Colors.red,
            checkColor: Colors.white,
            secondary: Icon(
              isOculta ? Icons.visibility_off : Icons.visibility,
              color: isOculta ? Colors.red : Colors.grey,
            ),
          );
        }).toList(),
      ),
    );
  }

  IconData _getIconeCategoriaTela(String categoria) {
    switch (categoria) {
      case 'Vendas':
        return Icons.point_of_sale;
      case 'Cadastros':
        return Icons.inventory;
      case 'Estoque':
        return Icons.warehouse;
      case 'Financeiro':
        return Icons.account_balance_wallet;
      case 'Relatórios':
        return Icons.bar_chart;
      case 'Operacional':
        return Icons.restaurant;
      case 'Configurações':
        return Icons.settings;
      case 'Dashboard':
        return Icons.dashboard;
      default:
        return Icons.category;
    }
  }
}

