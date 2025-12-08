import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import '../services/auth_service.dart';
import '../services/data_service.dart';
import '../services/excel_import_service.dart';
import '../models/empresa.dart';
import '../theme.dart';
import 'adicionar_empresa_page.dart';
import 'login_page.dart';

/// Página de gerenciamento de empresas
class EmpresasPage extends StatefulWidget {
  const EmpresasPage({super.key});

  @override
  State<EmpresasPage> createState() => _EmpresasPageState();
}

class _EmpresasPageState extends State<EmpresasPage> {
  @override
  Widget build(BuildContext context) {

    return AppTheme.appBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Gerenciar Empresas'),
          actions: [
            // Botão de importar Excel - SEMPRE VISÍVEL
            Container(
              margin: const EdgeInsets.only(right: 8),
              child: IconButton(
                icon: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green, width: 2),
                  ),
                  child: const Icon(Icons.file_upload, color: Colors.green, size: 24),
                ),
                tooltip: 'Importar Produtos do Excel',
                onPressed: () => _importarProdutosExcel(context),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: 'Adicionar Empresa',
              onPressed: () async {
                final resultado = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const AdicionarEmpresaPage(),
                  ),
                );
                if (resultado == true && mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Empresa adicionada com sucesso!'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              },
            ),
            IconButton(
              icon: const Icon(Icons.logout),
              tooltip: 'Voltar para Login',
              onPressed: () async {
                final confirmar = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    backgroundColor: const Color(0xFF1E1E2E),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    title: const Text(
                      'Confirmar Saída',
                      style: TextStyle(color: Colors.white),
                    ),
                    content: const Text(
                      'Deseja realmente sair e voltar para a tela de login?',
                      style: TextStyle(color: Colors.white70),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text(
                          'Cancelar',
                          style: TextStyle(color: Colors.white54),
                        ),
                      ),
                      ElevatedButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Sair'),
                      ),
                    ],
                  ),
                );

                if (confirmar == true && mounted) {
                  final authService = Provider.of<AuthService>(context, listen: false);
                  final dataService = Provider.of<DataService>(context, listen: false);
                  
                  await authService.logout();
                  await dataService.definirEmpresaAtual(null);
                  
                  if (mounted) {
                    Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const LoginPage(),
                      ),
                      (route) => false,
                    );
                  }
                }
              },
            ),
          ],
        ),
        body: Consumer<AuthService>(
          builder: (context, authService, child) {
            return RefreshIndicator(
              onRefresh: () async {
                await authService.carregarEmpresas();
              },
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Card de importação SEMPRE no topo (sempre visível)
                  _buildCardImportacao(context),
                  // Cards das empresas
                  if (authService.empresas.isEmpty)
                    _buildEmptyState()
                  else
                    ...authService.empresas.map((empresa) => _buildEmpresaCard(context, empresa, authService)),
                ],
              ),
            );
          },
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _importarProdutosExcel(context),
          backgroundColor: Colors.green,
          icon: const Icon(Icons.file_upload, color: Colors.white, size: 28),
          label: const Text(
            'IMPORTAR EXCEL',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.business_outlined,
            size: 80,
            color: Colors.white.withOpacity(0.3),
          ),
          const SizedBox(height: 24),
          Text(
            'Nenhuma empresa cadastrada',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: Colors.white70,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Toque no botão + para adicionar uma empresa',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.white54,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardImportacao(BuildContext context) {
    return Consumer<AuthService>(
      builder: (context, authService, _) {
        final empresaAtual = authService.empresaAtual;
        final podeImportar = empresaAtual != null || authService.empresas.length == 1;
        
        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            gradient: podeImportar
                ? LinearGradient(
                    colors: [Colors.green.withOpacity(0.3), Colors.green.withOpacity(0.1)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : LinearGradient(
                    colors: [Colors.orange.withOpacity(0.3), Colors.orange.withOpacity(0.1)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: podeImportar ? Colors.green : Colors.orange,
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: (podeImportar ? Colors.green : Colors.orange).withOpacity(0.3),
                blurRadius: 10,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => _importarProdutosExcel(context),
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: podeImportar ? Colors.green : Colors.orange,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: (podeImportar ? Colors.green : Colors.orange).withOpacity(0.5),
                            blurRadius: 8,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      child: Icon(
                        podeImportar ? Icons.file_upload : Icons.warning,
                        color: Colors.white,
                        size: 36,
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            podeImportar 
                                ? '📊 IMPORTAR PRODUTOS EXCEL'
                                : '⚠️ Selecione uma empresa para importar',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            podeImportar
                                ? empresaAtual != null
                                    ? 'Empresa: ${empresaAtual.nomeExibicao}\nClique para selecionar arquivo Excel'
                                    : 'Clique para importar produtos de um arquivo Excel'
                                : 'Clique no botão "Selecionar" da empresa primeiro',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.white.withOpacity(0.9),
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      podeImportar ? Icons.arrow_forward_ios : Icons.info_outline,
                      color: Colors.white,
                      size: 24,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmpresaCard(
    BuildContext context,
    Empresa empresa,
    AuthService authService,
  ) {
    final isEmpresaAtual = authService.empresaAtual?.id == empresa.id;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: InkWell(
        onTap: () async {
          final resultado = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => AdicionarEmpresaPage(empresa: empresa),
            ),
          );
          if (resultado == true && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Empresa atualizada com sucesso!'),
                backgroundColor: Colors.green,
              ),
            );
          }
        },
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Ícone da empresa
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: isEmpresaAtual
                      ? Colors.green.withOpacity(0.2)
                      : Colors.blueAccent.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.business,
                  color: isEmpresaAtual ? Colors.green : Colors.blueAccent,
                  size: 32,
                ),
              ),
              const SizedBox(width: 16),
              // Informações da empresa
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            empresa.nomeExibicao,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        if (isEmpresaAtual)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.green.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              'Atual',
                              style: TextStyle(
                                color: Colors.green,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
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
                    if (empresa.cidade != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        '${empresa.cidade}${empresa.estado != null ? ' - ${empresa.estado}' : ''}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withOpacity(0.5),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              // Botão de selecionar (se não for a atual)
              if (!isEmpresaAtual)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      await authService.selecionarEmpresa(empresa);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('✅ Empresa ${empresa.nomeExibicao} selecionada! Agora você pode importar produtos.'),
                            backgroundColor: Colors.green,
                            duration: const Duration(seconds: 3),
                          ),
                        );
                        setState(() {}); // Atualizar UI
                      }
                    },
                    icon: const Icon(Icons.check_circle, size: 18),
                    label: const Text('Selecionar', style: TextStyle(fontSize: 12)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                  ),
                ),
              // Menu de ações
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, color: Colors.white54),
                onSelected: (value) async {
                  if (value == 'editar') {
                    final resultado = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => AdicionarEmpresaPage(empresa: empresa),
                      ),
                    );
                    if (resultado == true && mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Empresa atualizada com sucesso!'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  } else if (value == 'selecionar') {
                    await authService.selecionarEmpresa(empresa);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Empresa ${empresa.nomeExibicao} selecionada'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  } else if (value == 'importar_produtos') {
                    // Verificar se a empresa está selecionada
                    if (!isEmpresaAtual) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Selecione a empresa antes de importar produtos'),
                          backgroundColor: Colors.orange,
                        ),
                      );
                      return;
                    }
                    _importarProdutosExcel(context);
                  } else if (value == 'excluir') {
                    _confirmarExclusao(context, empresa, authService);
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'editar',
                    child: Row(
                      children: [
                        Icon(Icons.edit, size: 20),
                        SizedBox(width: 8),
                        Text('Editar'),
                      ],
                    ),
                  ),
                  if (!isEmpresaAtual)
                    const PopupMenuItem(
                      value: 'selecionar',
                      child: Row(
                        children: [
                          Icon(Icons.check_circle, size: 20),
                          SizedBox(width: 8),
                          Text('Selecionar'),
                      ],
                    ),
                  ),
                  if (isEmpresaAtual)
                    const PopupMenuItem(
                      value: 'importar_produtos',
                      child: Row(
                        children: [
                          Icon(Icons.file_upload, size: 20, color: Colors.green),
                          SizedBox(width: 8),
                          Text('Importar Produtos Excel', style: TextStyle(color: Colors.green)),
                        ],
                      ),
                    ),
                  const PopupMenuItem(
                    value: 'excluir',
                    child: Row(
                      children: [
                        Icon(Icons.delete, size: 20, color: Colors.red),
                        SizedBox(width: 8),
                        Text('Excluir', style: TextStyle(color: Colors.red)),
                      ],
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

  void _confirmarExclusao(
    BuildContext context,
    Empresa empresa,
    AuthService authService,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: const Text(
          'Confirmar Exclusão',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'Deseja realmente excluir a empresa "${empresa.nomeExibicao}"?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              await authService.removerEmpresa(empresa.id);
              if (mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Empresa excluída com sucesso!'),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
  }

  /// Importa produtos de um arquivo Excel
  Future<void> _importarProdutosExcel(BuildContext context) async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final dataService = Provider.of<DataService>(context, listen: false);

    // Se não há empresa selecionada, tentar selecionar automaticamente
    if (authService.empresaAtual == null) {
      // Se houver apenas uma empresa, selecionar automaticamente
      if (authService.empresas.length == 1) {
        await authService.selecionarEmpresa(authService.empresas.first);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Empresa ${authService.empresas.first.nomeExibicao} selecionada automaticamente'),
              backgroundColor: Colors.blue,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } else if (authService.empresas.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Nenhuma empresa cadastrada. Adicione uma empresa primeiro.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      } else {
        // Se houver múltiplas empresas, pedir para selecionar
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Selecione uma empresa antes de importar produtos (menu da empresa → Selecionar)'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 4),
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
        withData: false,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao selecionar arquivo: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    if (result == null || result.files.single.path == null) {
      return; // Usuário cancelou
    }

    final arquivo = File(result.files.single.path!);

    // Mostrar loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Importando produtos...'),
              ],
            ),
          ),
        ),
      ),
    );

    // Importar produtos
    try {
      final resultado = await ExcelImportService.importarProdutos(
        arquivo,
        dataService,
      );

      if (mounted) {
        Navigator.pop(context); // Fechar loading

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
          ),
        );
      }
    }
  }
}

