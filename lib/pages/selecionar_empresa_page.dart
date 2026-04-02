import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'dart:typed_data';
import 'dart:async';
import '../services/auth_service.dart';
import '../services/data_service.dart';
import '../services/excel_import_service.dart';
import '../models/empresa.dart';
import '../models/usuario.dart';
import '../widgets/exodo_logo.dart';
import '../theme.dart';
import 'home_page.dart';
import 'adicionar_empresa_page.dart';
import 'gerenciar_usuarios_page.dart';
import 'login_page.dart';
import '../services/google_drive_service.dart';
import '../services/bridge_management_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'empresas_page.dart';

/// Página para selecionar a empresa
class SelecionarEmpresaPage extends StatefulWidget {
  const SelecionarEmpresaPage({super.key});

  @override
  State<SelecionarEmpresaPage> createState() => _SelecionarEmpresaPageState();
}

class _SelecionarEmpresaPageState extends State<SelecionarEmpresaPage> {
  bool _isLoading = false;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Iniciar verificação de backup automático (Google Drive)
    _verificarBackupAutomatico();
  }

  Future<void> _verificarBackupAutomatico() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final usuario = authService.usuarioAtual;
    
    // Apenas tenta backup se for admin/master
    if (usuario != null && (usuario.email.toLowerCase() == 'user' || usuario.isMaster)) {
      // Pequeno delay para não sobrecarregar o início da tela
      await Future.delayed(const Duration(seconds: 3));
      await GoogleDriveService.instance.verificarERealizarBackupAutomatico();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);

    return AppTheme.appBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: Padding(
            padding: const EdgeInsets.only(left: 16),
            child: const ExodoLogoCompact(fontSize: 28),
          ),
          title: Text(
            'Portal Êxodo',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 22,
              letterSpacing: -0.5,
              color: Colors.white.withOpacity(0.95),
            ),
          ),
          actions: [
            if (authService.usuarioAtual?.email.toLowerCase() == 'user')
              IconButton(
                icon: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blueAccent.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.settings, color: Colors.blueAccent, size: 20),
                ),
                tooltip: 'Configurações de Empresas',
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const EmpresasPage()),
                  );
                },
              ),
            const SizedBox(width: 8),
            IconButton(
              icon: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.logout, color: Colors.white70, size: 20),
              ),
              tooltip: 'Sair',
              onPressed: () async {
                final authService = Provider.of<AuthService>(context, listen: false);
                final dataService = Provider.of<DataService>(context, listen: false);
                await dataService.definirEmpresaAtual(null);
                await authService.logout();
                if (context.mounted) {
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (context) => const LoginPage()),
                    (route) => false,
                  );
                }
              },
            ),
            const SizedBox(width: 16),
          ],
        ),
        body: Stack(
          children: [
            SafeArea(
              child: CustomScrollView(
                physics: const BouncingScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(height: 12),
                          const Center(child: ExodoLogo(fontSize: 42, showSubtitle: true)),
                          const SizedBox(height: 32),
                          
                          // Hero section with better typography
                          Column(
                            children: [
                              Text(
                                'Bem-vindo de volta',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.6),
                                  fontSize: 16,
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                authService.usuarioAtual?.nome ?? 'Usuário',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 28,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -0.5,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 32),

                          // Essential Admin Cards
                          if (authService.usuarioAtual?.email.toLowerCase() == 'user') ...[
                            _buildCardGoogleDrive(context, authService),
                            const SizedBox(height: 16),
                            _buildCardBridgeManagement(context, authService),
                            const SizedBox(height: 24),
                          ],

                          // User Info Card - redesigned
                          _buildUsuarioInfoCard(context, authService),
                          const SizedBox(height: 32),

                          // Search and selection header
                          Row(
                            children: [
                              Container(
                                width: 4,
                                height: 24,
                                decoration: BoxDecoration(
                                  color: Colors.blueAccent,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                              const SizedBox(width: 12),
                              const Text(
                                'Selecionar Empresa',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          _buildSearchField(),
                          const SizedBox(height: 16),
                        ],
                      ),
                    ),
                  ),
                  
                  // The company list
                  authService.getEmpresasDoUsuario().isEmpty
                      ? SliverFillRemaining(
                          hasScrollBody: false,
                          child: _buildEmptyState(context),
                        )
                      : SliverPadding(
                          padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
                          sliver: _buildEmpresasListSliver(context, authService),
                        ),
                ],
              ),
            ),
            if (_isLoading)
              Container(
                color: Colors.black.withOpacity(0.6),
                child: const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.blueAccent),
                        strokeWidth: 3,
                      ),
                      SizedBox(height: 16),
                      Text(
                        'Carregando...',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    final usuarioAtual = authService.usuarioAtual;
    final isUsuarioMaster = usuarioAtual?.email.toLowerCase() == 'user';
    
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.business_outlined,
            size: 64,
            color: Colors.white.withOpacity(0.3),
          ),
          const SizedBox(height: 16),
          Text(
            'Nenhuma empresa cadastrada',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.white70,
                ),
          ),
          const SizedBox(height: 8),
          if (isUsuarioMaster) ...[
            Text(
              'Crie uma nova empresa para começar',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.white54,
                  ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () async {
                final resultado = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const AdicionarEmpresaPage(),
                  ),
                );
                
                if (resultado == true && mounted) {
                  setState(() {});
                }
              },
              icon: const Icon(Icons.add_business),
              label: const Text('Criar Primeira Empresa'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
          ] else ...[
            Text(
              'Entre em contato com o administrador',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.white54,
                  ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildUsuarioInfoCard(BuildContext context, AuthService authService) {
    final usuario = authService.usuarioAtual;
    if (usuario == null) return const SizedBox.shrink();

    return StatefulBuilder(
      builder: (context, setState) {
        bool _senhaVisivel = false;
        
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.06),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Colors.white.withOpacity(0.1),
              width: 1.5,
            ),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.blueAccent.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.person_outline, color: Colors.blueAccent, size: 24),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              usuario.nome,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 17,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.blueAccent.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                usuario.tipo == TipoUsuario.administrador ? 'ADMIN' : 
                                usuario.tipo == TipoUsuario.gerente ? 'GERENTE' : 'OPERADOR',
                                style: const TextStyle(
                                  color: Colors.blueAccent,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ],
                        ),
                        Text(
                          usuario.email,
                          style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.lock_outline, color: Colors.white54, size: 16),
                    const SizedBox(width: 12),
                    Text(
                      '••••••••',
                      style: TextStyle(color: Colors.white.withOpacity(0.7), letterSpacing: 2),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                      ),
                      onPressed: () => _mostrarDialogoAlterarSenha(context, authService, usuario),
                      icon: const Icon(Icons.edit_outlined, size: 14),
                      label: const Text('Alterar Senha', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w400,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSearchField() {
    return Container(
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: TextField(
        controller: _searchController,
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
        decoration: InputDecoration(
          hintText: 'Buscar por nome ou CNPJ...',
          hintStyle: TextStyle(color: Colors.white.withOpacity(0.4), fontWeight: FontWeight.w400),
          prefixIcon: Icon(Icons.search_rounded, color: Colors.blueAccent.withAlpha(180)),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear_rounded, color: Colors.white54),
                  onPressed: () {
                    setState(() => _searchController.clear());
                  },
                )
              : null,
          filled: true,
          fillColor: Colors.white.withOpacity(0.08),
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide(color: Colors.white.withOpacity(0.15)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide(color: Colors.white.withOpacity(0.12)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: Colors.blueAccent, width: 2),
          ),
        ),
        onChanged: (value) => setState(() {}),
      ),
    );
  }

  Widget _buildEmpresasListSliver(BuildContext context, AuthService authService) {
    final usuarioAtual = authService.usuarioAtual;
    final isUsuarioMaster = usuarioAtual?.email.toLowerCase() == 'user';
    
    List<Empresa> empresas = authService.getEmpresasDoUsuario();
    final searchText = _searchController.text.toLowerCase().trim();
    if (searchText.isNotEmpty) {
      empresas = empresas.where((empresa) {
        final nomeMatch = empresa.nomeExibicao.toLowerCase().contains(searchText) ||
            empresa.razaoSocial.toLowerCase().contains(searchText);
        final cnpjMatch = empresa.cnpj?.toLowerCase().contains(searchText) ?? false;
        return nomeMatch || cnpjMatch;
      }).toList();
    }

    if (empresas.isEmpty && searchText.isNotEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.only(top: 40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.search_off_rounded, size: 64, color: Colors.white.withOpacity(0.2)),
              const SizedBox(height: 16),
              Text(
                'Nenhuma empresa encontrada',
                style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 16),
              ),
            ],
          ),
        ),
      );
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          if (isUsuarioMaster && index == empresas.length) {
            return _buildBotaoCriarEmpresa(context);
          }
          return _buildEmpresaCard(context, empresas[index], authService);
        },
        childCount: empresas.length + (isUsuarioMaster ? 1 : 0),
      ),
    );
  }
  
  Widget _buildBotaoCriarEmpresa(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 16, bottom: 16),
      child: Card(
        child: InkWell(
          onTap: () async {
            final resultado = await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const AdicionarEmpresaPage(),
              ),
            );
            
            if (resultado == true && mounted) {
              // Recarrega a lista de empresas
              setState(() {});
            }
          },
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.greenAccent.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.add_business,
                    color: Colors.greenAccent,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Criar Nova Empresa',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Cadastrar uma nova empresa no sistema',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.arrow_forward_ios,
                  color: Colors.white54,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmpresaCard(BuildContext context, Empresa empresa, AuthService authService) {
    final usuarioAtual = authService.usuarioAtual;
    final isUsuarioMaster = usuarioAtual?.email.toLowerCase() == 'user';
    
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withOpacity(0.08),
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: _isLoading ? null : () async {
            setState(() => _isLoading = true);
            try {
              await authService.selecionarEmpresa(empresa);
              final dataService = Provider.of<DataService>(context, listen: false);
              dataService.setEmpresaAtual(empresa);
              await dataService.definirEmpresaAtual(empresa.id);
              if (context.mounted) {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (context) => const HomePage()),
                );
              }
            } catch (e) {
              if (context.mounted) {
                setState(() => _isLoading = false);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red),
                );
              }
            }
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Icon or Logo
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.blueAccent.withOpacity(0.2), Colors.blueAccent.withOpacity(0.05)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.blueAccent.withOpacity(0.2)),
                  ),
                  child: const Icon(Icons.business_rounded, color: Colors.blueAccent, size: 28),
                ),
                const SizedBox(width: 16),
                // Details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        empresa.nomeExibicao,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: -0.2,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.fingerprint, size: 12, color: Colors.white.withOpacity(0.4)),
                          const SizedBox(width: 4),
                          Text(
                            empresa.cnpj ?? 'Sem CNPJ',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white.withOpacity(0.4),
                              fontFamily: 'monospace',
                            ),
                          ),
                          const SizedBox(width: 12),
                          // Online indicator
                          Consumer<DataService>(
                            builder: (context, dataService, _) {
                              final bool isBridgeOnline = dataService.isEmpresaBridgeOnline(empresa.cnpj);
                              if (!isBridgeOnline) return const SizedBox.shrink();
                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.green.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: Colors.green.withOpacity(0.3)),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.green.withOpacity(0.1),
                                      blurRadius: 10,
                                      spreadRadius: 1,
                                    ),
                                  ],
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 6,
                                      height: 6,
                                      decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle),
                                    ),
                                    const SizedBox(width: 6),
                                    const Text(
                                      'ONLINE',
                                      style: TextStyle(color: Colors.green, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 0.5),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // Actions
                if (isUsuarioMaster)
                  PopupMenuButton<String>(
                    icon: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.05),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.more_vert_rounded, color: Colors.white54, size: 20),
                    ),
                    onSelected: (value) {
                      switch (value) {
                        case 'edit':
                          Navigator.push(context, MaterialPageRoute(builder: (context) => AdicionarEmpresaPage(empresa: empresa))).then((_) => setState(() {}));
                          break;
                        case 'users':
                          Navigator.push(context, MaterialPageRoute(builder: (context) => GerenciarUsuariosPage(empresa: empresa)));
                          break;
                        case 'reiniciar':
                          _selecionarPCEDispararComando(context, 'restart', 'Reiniciar Emissor');
                          break;
                        case 'importar':
                          _importarProdutosExcel(context);
                          break;
                        case 'limpar':
                          _confirmarExcluirTodosProdutos(context, Provider.of<DataService>(context, listen: false));
                          break;
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit_outlined, size: 18), SizedBox(width: 12), Text('Editar')])),
                      const PopupMenuItem(value: 'users', child: Row(children: [Icon(Icons.people_outline, size: 18), SizedBox(width: 12), Text('Usuários')])),
                      const PopupMenuDivider(),
                      const PopupMenuItem(value: 'reiniciar', child: Row(children: [Icon(Icons.restart_alt_rounded, color: Colors.blueAccent, size: 18), SizedBox(width: 12), Text('Reiniciar Emissor')])),
                      const PopupMenuItem(value: 'importar', child: Row(children: [Icon(Icons.file_upload_outlined, color: Colors.green, size: 18), SizedBox(width: 12), Text('Importar Excel')])),
                      const PopupMenuItem(value: 'limpar', child: Row(children: [Icon(Icons.delete_sweep_outlined, color: Colors.redAccent, size: 18), SizedBox(width: 12), Text('Limpar Produtos')])),
                    ],
                  ),
                if (!isUsuarioMaster)
                  Icon(Icons.chevron_right_rounded, color: Colors.white.withOpacity(0.2)),
              ],
            ),
          ),
        ),
      ),
    );
  }


  /// Realiza o backup de todas as empresas para o Google Drive
  Future<void> _realizarBackupGoogleDrive(BuildContext context) async {
    final driveService = GoogleDriveService.instance;
    
    // Mostrar diálogo de progresso
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: const Text('Backup Google Drive', style: TextStyle(color: Colors.white)),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Colors.orange),
            SizedBox(height: 24),
            Text(
              'Realizando exportação e upload de todas as empresas...\nIsso pode levar alguns minutos.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70),
            ),
          ],
        ),
      ),
    );

    try {
      final resultado = await driveService.realizarBackupTodasEmpresas();
      
      if (mounted) {
        Navigator.pop(context); // Fechar loading

        if (resultado['sucesso'] == true) {
          final detalhes = resultado['detalhes'];
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              backgroundColor: const Color(0xFF1E1E2E),
              title: const Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green),
                  SizedBox(width: 12),
                  Text('Backup Concluído', style: TextStyle(color: Colors.white)),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                   Text('Total de empresas: ${detalhes['total']}', style: const TextStyle(color: Colors.white70)),
                   Text('Sucesso: ${detalhes['sucesso']}', style: const TextStyle(color: Colors.white)),
                   if (detalhes['falha'] > 0)
                    Text('Falhas: ${detalhes['falha']}', style: const TextStyle(color: Colors.redAccent)),
                   const SizedBox(height: 16),
                   Text('Pasta no Drive: ${detalhes['pasta']}', style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Erro no backup: ${resultado['mensagem']}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro inesperado: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Widget _buildCardGoogleDrive(BuildContext context, AuthService authService) {
    if (authService.usuarioAtual?.email.toLowerCase() != 'user') return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF1E88E5).withOpacity(0.3),
            const Color(0xFF1565C0).withOpacity(0.1),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF42A5F5).withOpacity(0.4), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1E88E5).withOpacity(0.15),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _realizarBackupGoogleDrive(context),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF42A5F5),
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF42A5F5).withOpacity(0.4),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.cloud_done_rounded, color: Colors.white, size: 30),
                  ),
                  const SizedBox(width: 20),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Backup Global',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            letterSpacing: -0.5,
                          ),
                        ),
                        SizedBox(height: 6),
                        Text(
                          'Sincronizar todas as empresas com a nuvem do Google Drive.',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.white70,
                            height: 1.3,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white38, size: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _importarProdutosExcel(BuildContext context) async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final dataService = Provider.of<DataService>(context, listen: false);

    // Verificar se há empresa selecionada
    if (authService.empresaAtual == null) {
      final empresasPermitidas = authService.getEmpresasDoUsuario();
      if (empresasPermitidas.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Nenhuma empresa cadastrada. Adicione uma empresa primeiro.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Selecione uma empresa antes de importar produtos'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 3),
          ),
        );
        return;
      }
    }

    // Mostrar diálogo de instruções
    final continuar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: const Text(
          'Importar Produtos do Excel',
          style: TextStyle(color: Colors.white),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Formato esperado do Excel:',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Coluna A: Código (opcional)\n'
                'Coluna B: Nome (obrigatório)\n'
                'Coluna C: Descrição (opcional)\n'
                'Coluna D: Unidade (padrão: UN)\n'
                'Coluna E: Grupo (padrão: Sem Grupo)\n'
                'Coluna F: Preço (obrigatório)\n'
                'Coluna G: Preço de Custo (opcional)\n'
                'Coluna H: Estoque (padrão: 0)\n'
                'Coluna I: Código de Barras (opcional)',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  '⚠️ A primeira linha será ignorada (cabeçalho).\n'
                  '⚠️ Produtos duplicados serão ignorados.\n'
                  '⚠️ Produtos existentes serão atualizados.',
                  style: TextStyle(color: Colors.orange, fontSize: 11),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('Continuar'),
          ),
        ],
      ),
    );

    if (continuar != true) return;

    // Selecionar arquivo
    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
        withData: true, // IMPORTANTE: true para funcionar no web
      );
      
      if (result == null || result.files.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('⚠️ Nenhum arquivo selecionado'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return; // Usuário cancelou
      }

      final file = result.files.single;
      final nomeArquivo = file.name;
      Uint8List? bytes;
      
      // No web, usar bytes diretamente; em outras plataformas, pode usar path ou bytes
      if (file.bytes != null) {
        bytes = file.bytes;
      } else if (file.path != null && !kIsWeb) {
        final arquivo = File(file.path!);
        if (await arquivo.exists()) {
          bytes = await arquivo.readAsBytes();
        }
      }
      
      if (bytes == null || bytes.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('❌ Erro: Não foi possível ler o arquivo'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      // MOSTRAR DIÁLOGO DE PROGRESSO DINÂMICO
      if (!mounted) return;
      
      int processados = 0;
      int total = 0;
      String etapa = 'Iniciando...';
      
      // StatefulBuilder para atualizar o diálogo em tempo real
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) {
            // Função para atualizar o progresso dentro do StatefulBuilder
            void atualizarProgresso(int p, int t, String e) {
              processados = p;
              total = t;
              etapa = e;
              setDialogState(() {}); // Atualiza o diálogo
            }
            
            // Iniciar importação em background apenas uma vez
            if (total == 0 && etapa == 'Iniciando...') {
              Future.microtask(() {
                ExcelImportService.importarProdutosDeBytes(
                  bytes!,
                  dataService,
                  onProgress: atualizarProgresso,
                ).then((resultado) {
                  if (mounted) {
                    Navigator.of(context).pop(); // Fechar diálogo de progresso
                    
                  // Mostrar resultado
                  final mensagem = resultado['mensagens'] as List<String>;
                  final sucesso = resultado['sucesso'] as int;
                  final atualizados = resultado['atualizados'] as int;
                  final duplicados = resultado['duplicados'] as int;
                  final erros = resultado['erros'] as int;

                  // Separar mensagens por tipo
                  final mensagensErro = mensagem.where((m) => m.contains('❌') || m.contains('⚠️') || m.contains('Erro')).toList();
                  final mensagensInfo = mensagem.where((m) => !m.contains('❌') && !m.contains('⚠️') && !m.contains('Erro')).toList();

                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      backgroundColor: const Color(0xFF1E1E2E),
                      title: Row(
                        children: [
                          Icon(
                            erros > 0 ? Icons.warning_amber_rounded : Icons.check_circle,
                            color: erros > 0 ? Colors.orange : Colors.green,
                            size: 28,
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'Resultado da Importação',
                              style: TextStyle(color: Colors.white, fontSize: 20),
                            ),
                          ),
                        ],
                      ),
                      content: SizedBox(
                        width: MediaQuery.of(context).size.width * 0.9,
                        child: SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Resumo
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.blue.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.blue.withOpacity(0.3)),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _buildResumoItemLinha('✅', 'Novos importados', sucesso, Colors.green),
                                    _buildResumoItemLinha('🔄', 'Atualizados', atualizados, Colors.blue),
                                    _buildResumoItemLinha('⚠️', 'Duplicados ignorados', duplicados, Colors.orange),
                                    _buildResumoItemLinha('❌', 'Erros', erros, Colors.red),
                                  ],
                                ),
                              ),
                              
                              // Mensagens de erro (se houver)
                              if (mensagensErro.isNotEmpty) ...[
                                const SizedBox(height: 20),
                                Row(
                                  children: [
                                    const Icon(Icons.error_outline, color: Colors.red, size: 20),
                                    const SizedBox(width: 8),
                                    const Text(
                                      'Erros e Avisos:',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Container(
                                  constraints: const BoxConstraints(maxHeight: 300),
                                  decoration: BoxDecoration(
                                    color: Colors.red.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.red.withOpacity(0.3)),
                                  ),
                                  child: ListView.builder(
                                    shrinkWrap: true,
                                    itemCount: mensagensErro.length,
                                    itemBuilder: (context, index) {
                                      final msg = mensagensErro[index];
                                      return Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                        child: Row(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Icon(
                                              msg.contains('❌') ? Icons.cancel : Icons.warning_amber,
                                              color: msg.contains('❌') ? Colors.red : Colors.orange,
                                              size: 16,
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                msg.replaceAll('❌', '').replaceAll('⚠️', '').trim(),
                                                style: const TextStyle(
                                                  color: Colors.white70,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ],
                              
                              // Mensagens informativas
                              if (mensagensInfo.isNotEmpty && mensagensInfo.length <= 5) ...[
                                const SizedBox(height: 16),
                                ...mensagensInfo.map((m) => Padding(
                                      padding: const EdgeInsets.only(bottom: 6),
                                      child: Row(
                                        children: [
                                          const Icon(Icons.info_outline, color: Colors.blue, size: 16),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              m,
                                              style: const TextStyle(
                                                color: Colors.white54,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    )),
                              ],
                            ],
                          ),
                        ),
                      ),
                      actions: [
                        if (mensagensErro.length > 10)
                          TextButton.icon(
                            onPressed: () {
                              Navigator.pop(context);
                              _mostrarTodosErros(context, mensagensErro);
                            },
                            icon: const Icon(Icons.list, color: Colors.orange),
                            label: const Text('Ver todos os erros'),
                          ),
                        ElevatedButton(
                          onPressed: () => Navigator.pop(context),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                          child: const Text('OK'),
                        ),
                      ],
                    ),
                  );

                    if (sucesso > 0 || atualizados > 0) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            '✅ ${sucesso + atualizados} produtos processados com sucesso!',
                          ),
                          backgroundColor: Colors.green,
                          duration: const Duration(seconds: 3),
                        ),
                      );
                    }
                  }
                }).catchError((e) {
                  if (mounted) {
                    Navigator.of(context).pop(); // Fechar loading
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Erro ao importar: $e'),
                        backgroundColor: Colors.red,
                        duration: const Duration(seconds: 5),
                      ),
                    );
                  }
                });
              });
            }
            
            return AlertDialog(
              backgroundColor: const Color(0xFF1E1E2E),
              contentPadding: const EdgeInsets.all(24),
              title: const Row(
                children: [
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.green),
                      strokeWidth: 3,
                    ),
                  ),
                  SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      '📊 Importando Produtos',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 400,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.insert_drive_file, color: Colors.blue, size: 24),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Arquivo:',
                                  style: TextStyle(color: Colors.white70, fontSize: 11),
                                ),
                                Text(
                                  nomeArquivo,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    // Barra de progresso
                    if (total > 0) ...[
                      LinearProgressIndicator(
                        value: processados / total,
                        backgroundColor: Colors.grey.withOpacity(0.3),
                        valueColor: const AlwaysStoppedAnimation<Color>(Colors.green),
                        minHeight: 8,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '$processados / $total',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '${total > 0 ? ((processados / total) * 100).toStringAsFixed(0) : 0}%',
                            style: const TextStyle(
                              color: Colors.green,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                    ] else
                      const Center(
                        child: CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.green),
                          strokeWidth: 4,
                        ),
                      ),
                    const SizedBox(height: 16),
                    Center(
                      child: Text(
                        etapa,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white70, fontSize: 14),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );
      
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao selecionar arquivo: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  Widget _buildResumoItemLinha(String icon, String label, int valor, Color cor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Text(icon, style: const TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ],
          ),
          Text(
            valor.toString(),
            style: TextStyle(
              color: cor,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  void _mostrarTodosErros(BuildContext context, List<String> erros) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.red),
            const SizedBox(width: 12),
            Text(
              'Todos os Erros (${erros.length})',
              style: const TextStyle(color: Colors.white),
            ),
          ],
        ),
        content: SizedBox(
          width: MediaQuery.of(context).size.width * 0.9,
          height: MediaQuery.of(context).size.height * 0.6,
          child: ListView.builder(
            itemCount: erros.length,
            itemBuilder: (context, index) {
              final erro = erros[index];
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.withOpacity(0.3)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        erro.contains('❌') ? Icons.cancel : Icons.warning_amber,
                        color: erro.contains('❌') ? Colors.red : Colors.orange,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          erro.replaceAll('❌', '').replaceAll('⚠️', '').trim(),
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmarExcluirTodosProdutos(BuildContext context, DataService dataService) async {
    final totalProdutos = dataService.produtos.length;

    if (totalProdutos == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não há produtos para excluir'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning, color: Colors.red, size: 28),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Excluir Todos os Produtos',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Tem certeza que deseja excluir TODOS os $totalProdutos produtos?',
              style: const TextStyle(color: Colors.white70, fontSize: 16),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.withOpacity(0.5)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.error_outline, color: Colors.red, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '⚠️ Esta ação não pode ser desfeita!',
                      style: TextStyle(
                        color: Colors.red,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            child: const Text('Excluir Todos'),
          ),
        ],
      ),
    );

    if (confirmar == true && mounted) {
      try {
        await dataService.deleteAllProdutos(confirmar: true);
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ Todos os $totalProdutos produtos foram excluídos com sucesso!'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('❌ Erro ao excluir produtos: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Widget _buildCardBridgeManagement(BuildContext context, AuthService authService) {
    if (authService.usuarioAtual?.email.toLowerCase() != 'user') return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFFFB8C00).withOpacity(0.3),
            const Color(0xFFE65100).withOpacity(0.1),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFFFB74D).withOpacity(0.4), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFB8C00).withOpacity(0.15),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _mostrarDialogoGerenciamentoBridge(context),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFB74D),
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFFFB74D).withOpacity(0.4),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.terminal_rounded, color: Colors.white, size: 30),
                  ),
                  const SizedBox(width: 20),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Gerenciar Emissor',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            letterSpacing: -0.5,
                          ),
                        ),
                        SizedBox(height: 6),
                        Text(
                          'Acesso remoto: updates, reinício de serviços e identificação de PCs.',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.white70,
                            height: 1.3,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.settings_remote_rounded, color: Colors.white38, size: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBridgeAction_Divider() {
    return Container(
      height: 1,
      color: Colors.white.withOpacity(0.05),
    );
  }

  void _mostrarDialogoGerenciamentoBridge(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.terminal, color: Colors.orange),
            SizedBox(width: 12),
            Text('Comandos do Emissor', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Estes comandos serão enviados para os computadores que estão rodando o Bridge NFC-e.',
              style: TextStyle(color: Colors.white70, fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            _buildBridgeActionTile(
              context,
              icon: Icons.play_arrow,
              color: Colors.orange,
              title: 'Iniciar Forçado (Watchdog)',
              subtitle: 'Aciona o monitor para abrir o emissor se estiver fechado.',
              onTap: () => _selecionarPCEDispararComando(context, 'start', 'Iniciar'),
            ),
            const SizedBox(height: 12),
            _buildBridgeAction_Divider(),
            const SizedBox(height: 12),
            _buildBridgeActionTile(
              context,
              icon: Icons.system_update,
              color: Colors.green,
              title: 'Atualizar Software (Nuvem/Cloud)',
              subtitle: 'Baixa a versão oficial mais recente enviada via App.',
              onTap: () => _selecionarPCEDispararComando(context, 'update', 'Atualizar'),
            ),
            const SizedBox(height: 12),
            _buildBridgeActionTile(
              context,
              icon: Icons.restart_alt,
              color: Colors.blue,
              title: 'Reiniciar Serviços',
              subtitle: 'Força o reinício do emissor.',
              onTap: () => _selecionarPCEDispararComando(context, 'restart', 'Reiniciar'),
            ),
            const SizedBox(height: 12),
            _buildBridgeActionTile(
              context,
              icon: Icons.cloud_upload,
              color: Colors.pink,
              title: 'Subir Atualização (.exe)',
              subtitle: 'Faz upload manual da nova versão e diponibiliza.',
              onTap: () => _selecionarESubirNovaVersao(context),
            ),
            const SizedBox(height: 12),
            _buildBridgeActionTile(
              context,
              icon: Icons.info_outline,
              color: Colors.purple,
              title: 'Identificar Máquinas',
              subtitle: 'Solicita nome do PC e versão do Windows.',
              onTap: () => _selecionarPCEDispararComando(context, 'identify', 'Identificar'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('FECHAR', style: TextStyle(color: Colors.white54)),
          ),
        ],
      ),
    );
  }

  Widget _buildBridgeActionTile(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                   Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                   Text(subtitle, style: const TextStyle(color: Colors.white54, fontSize: 11)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: color.withOpacity(0.5)),
          ],
        ),
      ),
    );
  }

  void _selecionarPCEDispararComando(BuildContext pageContext, String comando, String acaoTitulo, {Map<String, dynamic>? extraData}) {
    showDialog(
      context: pageContext,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: Text('Selecione o PC para $acaoTitulo', style: const TextStyle(color: Colors.white, fontSize: 18)),
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('bridge_status')
                .snapshots(),
            builder: (streamContext, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(child: Text('Erro: ${snapshot.error}', style: const TextStyle(color: Colors.white)));
              }

              final docs = snapshot.data?.docs ?? [];
              
              if (docs.isEmpty) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(20.0),
                    child: Text('Nenhum emissor encontrado no banco de dados.', style: TextStyle(color: Colors.white54, fontSize: 13), textAlign: TextAlign.center),
                  ),
                );
              }

              return ListView(
                children: [
                  ListTile(
                    leading: const Icon(Icons.computer, color: Colors.white),
                    title: const Text('TODOS OS COMPUTADORES', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
                    onTap: () {
                      Navigator.pop(dialogContext);
                      _confirmarComandoBridge(pageContext, comando, 'Deseja $acaoTitulo em TODOS os emissores simultaneamente?', targetPc: null, extraData: extraData);
                    },
                  ),
                  const Divider(color: Colors.white24),
                  // Lista de Pcs Específicos
                  ...(() {
                    try {
                      final List<Widget> tiles = [];
                      final filteredDocs = docs.where((doc) => !doc.id.startsWith('watchdog_')).toList();
                      
                      for (var doc in filteredDocs) {
                        final dynamic rawData = doc.data();
                        if (rawData == null || rawData is! Map) continue;
                        
                        final data = rawData as Map<String, dynamic>;
                        final pcName = (data['pc_name'] ?? doc.id).toString();
                        final bool isOnline = data['online'] == true;
                        
                        // Procurar status do watchdog para este PC de forma segura
                        Map<String, dynamic>? watchdogData;
                        for (var d in docs) {
                          if (d.id == 'watchdog_$pcName') {
                            final dRaw = d.data();
                            if (dRaw is Map) {
                              watchdogData = dRaw as Map<String, dynamic>;
                            }
                            break;
                          }
                        }
                        
                        final bool watchdogOnline = watchdogData != null && (watchdogData['online'] == true);

                        tiles.add(ListTile(
                          leading: Icon(
                            Icons.desktop_windows, 
                            color: isOnline ? Colors.green : (watchdogOnline ? Colors.orange : Colors.grey)
                          ),
                          title: Text(pcName, style: const TextStyle(color: Colors.white)),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                isOnline ? 'Bridge Online' : 'Bridge Offline',
                                style: TextStyle(color: isOnline ? Colors.green : Colors.red, fontSize: 11),
                              ),
                              Text(
                                watchdogOnline ? '🛡️ Proteção Ativa' : '⚠️ Proteção Offline',
                                style: TextStyle(color: watchdogOnline ? Colors.orange : Colors.grey, fontSize: 10),
                              ),
                              if (data['ultima_empresa'] != null)
                                Text(
                                  '🏢 ${data['ultima_empresa']}',
                                  style: const TextStyle(color: Colors.blueAccent, fontSize: 10, fontWeight: FontWeight.bold),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                            ],
                          ),
                          trailing: const Icon(Icons.send, color: Colors.white24, size: 16),
                          onTap: () {
                            Navigator.pop(dialogContext);
                        _confirmarComandoBridge(pageContext, comando, 'Deseja $acaoTitulo no PC: $pcName?', targetPc: pcName, extraData: extraData);
                      },
                    ));
                  }
                      return tiles;
                    } catch (e) {
                      debugPrint('Erro ao construir lista de PCs: $e');
                      return [Text('Erro na lista: $e', style: const TextStyle(color: Colors.red))];
                    }
                  })(),
                ],
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
          ),
        ],
      ),
    );
  }

  void _confirmarComandoBridge(BuildContext context, String comando, String pergunta, {String? targetPc, Map<String, dynamic>? extraData}) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF2E2E3E),
        title: const Text('Confirmar Comando', style: TextStyle(color: Colors.white)),
        content: Text(pergunta, style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('NÃO'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(dialogContext); // Fecha confirmação
              
              try {
                debugPrint('>>> [BridgeManager] Enviando comando "$comando" para PC: ${targetPc ?? "Todos"}');
                
                if (mounted) {
                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('📤 Enviando comando "$comando"...'),
                      backgroundColor: Colors.blueAccent,
                      duration: const Duration(seconds: 2),
                    ),
                  );
                }

                final docRef = await BridgeManagementService.instance.enviarComando(comando, targetPc: targetPc, extraData: extraData);
                
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('✅ Comando "$comando" postado! Aguardando resposta do PC...'),
                      backgroundColor: Colors.indigo,
                      duration: const Duration(seconds: 4),
                    ),
                  );
                }

                // Monitorar Resposta em Tempo Real (Ouvir o Documento apenas uma vez ou por stream limitada)
                int checkCount = 0;
                late StreamSubscription sub;
                
                sub = docRef.snapshots().listen((snapshot) {
                  if (!snapshot.exists || !mounted) {
                    sub.cancel();
                    return;
                  }
                  
                  final data = snapshot.data() as Map<String, dynamic>;
                  final status = data['status'];
                  final resultado = data['resultado'] ?? '';
                  final processorPc = data['processor_pc'] ?? '';

                  // Gerenciamento de Timeout Interno
                  checkCount++;
                  if (status == 'pendente' && checkCount > 15) { // ~15-20 segundos sem sair de pendente
                    sub.cancel();
                    ScaffoldMessenger.of(context).hideCurrentSnackBar();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('⚠️ O PC parece estar OFFLINE ou o Bridge está fechado. Verifique se o ícone laranja está aberto no PC.'),
                        backgroundColor: Colors.brown,
                        duration: Duration(seconds: 8),
                      ),
                    );
                    return;
                  }

                  if (status == 'processando') {
                    ScaffoldMessenger.of(context).hideCurrentSnackBar();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('⏳ $comando: Processando em $processorPc...'),
                        backgroundColor: Colors.orange,
                        duration: const Duration(seconds: 10),
                      ),
                    );
                  } 
                  else if (status == 'concluido' || status == 'autorizada') { // 'autorizada' para nfce
                    final bool sucesso = data['sucesso'] == true || status == 'autorizada';
                    
                    ScaffoldMessenger.of(context).hideCurrentSnackBar();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Row(
                          children: [
                            Icon(sucesso ? Icons.check_circle : Icons.error, color: Colors.white),
                            const SizedBox(width: 8),
                            Expanded(child: Text(sucesso ? '✅ Sucesso ($processorPc): $resultado' : '❌ Erro ($processorPc): $resultado')),
                          ],
                        ),
                        backgroundColor: sucesso ? Colors.green : Colors.red,
                        duration: const Duration(seconds: 15),
                        action: SnackBarAction(label: 'OK', textColor: Colors.white, onPressed: () {}),
                      ),
                    );
                  }
                  else if (status == 'erro') {
                    ScaffoldMessenger.of(context).hideCurrentSnackBar();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('❌ Falha ($processorPc): $resultado'),
                        backgroundColor: Colors.red,
                        duration: const Duration(seconds: 15),
                        action: SnackBarAction(label: 'OK', textColor: Colors.white, onPressed: () {}),
                      ),
                    );
                  }
                });

              } catch (e) {
                debugPrint('>>> [BridgeManager] Erro ao enviar comando: $e');
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('❌ Erro no Envio: $e'), 
                      backgroundColor: Colors.red,
                      duration: const Duration(seconds: 10),
                    ),
                  );
                }
              }
            },
            child: const Text('SIM'),
          ),
        ],
      ),
    );
  }

  Future<void> _selecionarESubirNovaVersao(BuildContext context) async {
    Navigator.pop(context); // Fechar dialog atual
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['exe'],
      );

      if (result != null && result.files.single.bytes != null) {
        final file = result.files.single;
        
        // Perguntar a versão
        final versionController = TextEditingController(text: "2.8");
        final bool? confirm = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: const Color(0xFF1E1E2E),
            title: const Text('Confirmar Upload', style: TextStyle(color: Colors.white)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Arquivo selecionado: ${file.name} (${(file.size / 1024 / 1024).toStringAsFixed(2)} MB)', style: const TextStyle(color: Colors.white70)),
                const SizedBox(height: 16),
                TextField(
                  controller: versionController,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Versão a distribuir',
                    labelStyle: TextStyle(color: Colors.white54),
                    enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white30)),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(child: const Text('Cancelar'), onPressed: () => Navigator.pop(context, false)),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.pink),
                child: const Text('Iniciar Upload', style: TextStyle(color: Colors.white)),
                onPressed: () => Navigator.pop(context, true),
              ),
            ],
          ),
        );

        if (confirm == true && mounted) {
          // Mostrar progresso
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => const AlertDialog(
              backgroundColor: Color(0xFF1E1E2E),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Colors.pink),
                  SizedBox(height: 16),
                  Text('Fazendo upload para a Nuvem...', style: TextStyle(color: Colors.white)),
                  SizedBox(height: 4),
                  Text('Isso pode levar alguns minutos (35MB).', style: TextStyle(color: Colors.white54, fontSize: 12)),
                ],
              ),
            ),
          );

          await BridgeManagementService.instance.subirNovaVersaoBridge(
            file, 
            versionController.text.trim(),
            (progress) {} // Sem atualização em real time por simplicidade visual
          );

          if (mounted) {
            Navigator.pop(context); // Fecha dialog de progresso
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('✅ Upload concluído! Os clientes na versão 2.8+ agora podem atualizar via APP.'), backgroundColor: Colors.green),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        if (Navigator.canPop(context)) Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro no upload: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _mostrarDialogoAlterarSenha(BuildContext context, AuthService authService, Usuario usuario) {
    final formKey = GlobalKey<FormState>();
    final senhaAtualController = TextEditingController();
    final novaSenhaController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: const Text('Alterar Senha', style: TextStyle(color: Colors.white)),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: senhaAtualController,
                obscureText: true,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Senha Atual',
                  labelStyle: TextStyle(color: Colors.white70),
                  enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white30)),
                  focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.blueAccent)),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) return 'Campo obrigatório';
                  if (value != usuario.senha) return 'Senha atual incorreta';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: novaSenhaController,
                obscureText: true,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Nova Senha',
                  labelStyle: TextStyle(color: Colors.white70),
                  enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white30)),
                  focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.blueAccent)),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) return 'Campo obrigatório';
                  if (value.length < 3) return 'Mínimo de 3 caracteres';
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () async {
              if (formKey.currentState!.validate()) {
                try {
                  final usuarioAtualizado = usuario.copyWith(senha: novaSenhaController.text);
                  await authService.atualizarUsuario(usuarioAtualizado);
                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Senha alterada com sucesso!'), backgroundColor: Colors.green),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Erro ao alterar senha: $e'), backgroundColor: Colors.red),
                    );
                  }
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
            child: const Text('Salvar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}




