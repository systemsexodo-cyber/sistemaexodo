import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'dart:typed_data';
import '../services/auth_service.dart';
import '../services/data_service.dart';
import '../services/excel_import_service.dart';
import '../models/empresa.dart';
import '../widgets/exodo_logo.dart';
import '../theme.dart';
import 'home_page.dart';
import 'adicionar_empresa_page.dart';
import 'gerenciar_usuarios_page.dart';
import 'login_page.dart';

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
        appBar: AppBar(
          title: const Text('Selecionar Empresa'),
          automaticallyImplyLeading: false,
          actions: [
            IconButton(
              icon: const Icon(Icons.logout),
              tooltip: 'Sair e voltar ao login',
              onPressed: () async {
                final authService = Provider.of<AuthService>(context, listen: false);
                final dataService = Provider.of<DataService>(context, listen: false);
                
                // Limpar empresa do DataService primeiro
                await dataService.definirEmpresaAtual(null);
                
                // Fazer logout
                await authService.logout();
                
                if (context.mounted) {
                  // Usar Navigator.pushAndRemoveUntil para garantir que não volte para empresas
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const LoginPage(),
                    ),
                    (route) => false, // Remove todas as rotas anteriores
                  );
                }
              },
            ),
          ],
        ),
        body: Stack(
          children: [
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 20),
                    const ExodoLogo(fontSize: 48, showSubtitle: true),
                    const SizedBox(height: 32),
                    Text(
                      'Selecione a empresa',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Escolha a empresa que deseja gerenciar',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Colors.white70,
                          ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    // Campo de busca
                    _buildSearchField(),
                    const SizedBox(height: 16),
                    Expanded(
                      child: authService.empresas.isEmpty
                          ? _buildEmptyState(context)
                          : _buildEmpresasList(context, authService),
                    ),
                  ],
                ),
              ),
            ),
            if (_isLoading)
            Container(
              color: Colors.black.withOpacity(0.5),
              child: const Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.blueAccent),
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

  Widget _buildSearchField() {
    return TextField(
      controller: _searchController,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: 'Buscar por nome ou CNPJ...',
        hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
        prefixIcon: const Icon(Icons.search, color: Colors.white70),
        suffixIcon: _searchController.text.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear, color: Colors.white70),
                onPressed: () {
                  setState(() {
                    _searchController.clear();
                  });
                },
              )
            : null,
        filled: true,
        fillColor: Colors.white.withOpacity(0.1),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: Colors.white.withOpacity(0.2),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: Colors.blueAccent,
            width: 2,
          ),
        ),
      ),
      onChanged: (value) {
        setState(() {}); // Atualiza a lista quando o texto muda
      },
    );
  }

  Widget _buildEmpresasList(BuildContext context, AuthService authService) {
    // Se for usuário "user", mostra todas as empresas
    // Caso contrário, mostra apenas empresas vinculadas ao usuário
    final usuarioAtual = authService.usuarioAtual;
    final isUsuarioMaster = usuarioAtual?.email.toLowerCase() == 'user';
    
    List<Empresa> empresas;
    if (isUsuarioMaster) {
      // Usuário "user" vê todas as empresas
      empresas = authService.empresas.where((e) => e.ativo).toList();
    } else {
      // Outros usuários veem apenas empresas vinculadas
      empresas = authService.empresas
          .where((e) => e.ativo && e.id == usuarioAtual?.empresaId)
          .toList();
    }

    // Aplicar filtro de busca
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
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off,
              size: 64,
              color: Colors.white.withOpacity(0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'Nenhuma empresa encontrada',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Colors.white70,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tente buscar por outro termo',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.white54,
                  ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: empresas.length + (isUsuarioMaster ? 1 : 0), // +1 para botão criar
      itemBuilder: (context, index) {
        // Se for o último item e for usuário master, mostra botão criar
        if (isUsuarioMaster && index == empresas.length) {
          return _buildBotaoCriarEmpresa(context);
        }
        
        final empresa = empresas[index];
        return _buildEmpresaCard(context, empresa, authService);
      },
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
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: Colors.greenAccent.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.add_business,
                    color: Colors.greenAccent,
                    size: 32,
                  ),
                ),
                const SizedBox(width: 16),
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

  Widget _buildEmpresaCard(
    BuildContext context,
    Empresa empresa,
    AuthService authService,
  ) {
    final usuarioAtual = authService.usuarioAtual;
    final isUsuarioMaster = usuarioAtual?.email.toLowerCase() == 'user';
    
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: InkWell(
        onTap: _isLoading ? null : () async {
          setState(() => _isLoading = true);
          try {
            await authService.selecionarEmpresa(empresa);
            
            // Notificar DataService sobre a empresa selecionada
            final dataService = Provider.of<DataService>(context, listen: false);
            await dataService.definirEmpresaAtual(empresa.id);
            
            if (context.mounted) {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) => const HomePage(),
                ),
              );
            }
          } catch (e) {
            if (context.mounted) {
              setState(() => _isLoading = false);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Erro ao selecionar empresa: $e'),
                  backgroundColor: Colors.red,
                ),
              );
            }
          }
        },
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              // Ícone da empresa
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.blueAccent.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.business,
                  color: Colors.blueAccent,
                  size: 32,
                ),
              ),
              const SizedBox(width: 16),
              // Informações da empresa
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
                      ),
                    ),
                    if (empresa.razaoSocial != empresa.nomeExibicao) ...[
                      const SizedBox(height: 4),
                      Text(
                        empresa.razaoSocial,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.white.withOpacity(0.7),
                        ),
                      ),
                    ],
                    if (empresa.cnpj != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'CNPJ: ${empresa.cnpj}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withOpacity(0.5),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              // Botões de ação
              IconButton(
                icon: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green, width: 1.5),
                  ),
                  child: const Icon(Icons.file_upload, color: Colors.green, size: 20),
                ),
                tooltip: 'Importar Produtos Excel',
                onPressed: () async {
                  // Selecionar empresa primeiro
                  await authService.selecionarEmpresa(empresa);
                  final dataService = Provider.of<DataService>(context, listen: false);
                  await dataService.definirEmpresaAtual(empresa.id);
                  // Abrir importação
                  _importarProdutosExcel(context);
                },
              ),
              if (isUsuarioMaster)
                IconButton(
                  icon: const Icon(Icons.edit, color: Colors.white54),
                  tooltip: 'Editar Empresa',
                  onPressed: () async {
                    final resultado = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => AdicionarEmpresaPage(empresa: empresa),
                      ),
                    );
                    if (resultado == true && mounted) {
                      setState(() {});
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Empresa atualizada com sucesso!'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  },
                ),
              if (isUsuarioMaster) ...[
                IconButton(
                  icon: const Icon(Icons.people, color: Colors.white54),
                  tooltip: 'Gerenciar Usuários',
                  onPressed: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => GerenciarUsuariosPage(
                          empresa: empresa,
                        ),
                      ),
                    );
                  },
                ),
              ],
              const Icon(
                Icons.arrow_forward_ios,
                color: Colors.white54,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoItem(String icon, String texto, Color cor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text(icon, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              texto,
              style: TextStyle(
                color: Colors.white.withOpacity(0.8),
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEstatisticaCard(String icon, int valor, String label, Color cor) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cor.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cor.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Text(
            icon,
            style: const TextStyle(fontSize: 24),
          ),
          const SizedBox(height: 4),
          Text(
            valor.toString(),
            style: TextStyle(
              color: cor,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: 11,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Future<void> _importarProdutosExcel(BuildContext context) async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final dataService = Provider.of<DataService>(context, listen: false);

    // Verificar se há empresa selecionada
    if (authService.empresaAtual == null) {
      if (authService.empresas.isEmpty) {
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

      // MOSTRAR DIÁLOGO DE PROGRESSO IMEDIATAMENTE
      if (!mounted) return;
      
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
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
                const Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.green),
                    strokeWidth: 4,
                  ),
                ),
                const SizedBox(height: 20),
                const Center(
                  child: Text(
                    'Processando planilha...\nPor favor, aguarde.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      // Processar importação (diálogo já está aberto)
      try {
        final resultado = await ExcelImportService.importarProdutosDeBytes(
          bytes,
          dataService,
        );

        if (mounted) {
          Navigator.pop(context); // Fechar diálogo de progresso

          // Mostrar resultado
          final mensagem = resultado['mensagens'] as List<String>;
          final sucesso = resultado['sucesso'] as int;
          final atualizados = resultado['atualizados'] as int;
          final duplicados = resultado['duplicados'] as int;
          final erros = resultado['erros'] as int;

          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              backgroundColor: const Color(0xFF1E1E2E),
              title: const Text(
                'Resultado da Importação',
                style: TextStyle(color: Colors.white),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '✅ Novos: $sucesso\n'
                      '🔄 Atualizados: $atualizados\n'
                      '⚠️ Duplicados ignorados: $duplicados\n'
                      '❌ Erros: $erros',
                      style: const TextStyle(color: Colors.white70),
                    ),
                    if (mensagem.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      const Text(
                        'Detalhes:',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...mensagem.take(10).map((m) => Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                              m,
                              style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 11,
                              ),
                            ),
                          )),
                      if (mensagem.length > 10)
                        Text(
                          '... e mais ${mensagem.length - 10} mensagens',
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 11,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                    ],
                  ],
                ),
              ),
              actions: [
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
      } catch (e) {
        if (mounted) {
          Navigator.pop(context); // Fechar loading
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Erro ao importar: $e'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 5),
            ),
          );
        }
      }
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
}


