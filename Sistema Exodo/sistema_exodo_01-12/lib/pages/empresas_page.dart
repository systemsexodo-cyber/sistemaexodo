import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../models/empresa.dart';
import '../theme.dart';
import 'adicionar_empresa_page.dart';

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
          ],
        ),
        body: Consumer<AuthService>(
          builder: (context, authService, child) {
            if (authService.empresas.isEmpty) {
              return _buildEmptyState();
            }

            return RefreshIndicator(
              onRefresh: () async {
                await authService.carregarEmpresas();
              },
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: authService.empresas.length,
                itemBuilder: (context, index) {
                  final empresa = authService.empresas[index];
                  return _buildEmpresaCard(context, empresa, authService);
                },
              ),
            );
          },
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
}

