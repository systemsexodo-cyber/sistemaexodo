import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../models/empresa.dart';
import '../widgets/exodo_logo.dart';
import '../theme.dart';
import 'home_page.dart';

/// Página para selecionar a empresa
class SelecionarEmpresaPage extends StatefulWidget {
  const SelecionarEmpresaPage({super.key});

  @override
  State<SelecionarEmpresaPage> createState() => _SelecionarEmpresaPageState();
}

class _SelecionarEmpresaPageState extends State<SelecionarEmpresaPage> {
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);

    return AppTheme.appBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Selecionar Empresa'),
          automaticallyImplyLeading: false,
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
                    const SizedBox(height: 32),
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
          Text(
            'Entre em contato com o administrador',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.white54,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpresasList(BuildContext context, AuthService authService) {
    final empresas = authService.empresas.where((e) => e.ativo).toList();

    return ListView.builder(
      itemCount: empresas.length,
      itemBuilder: (context, index) {
        final empresa = empresas[index];
        return _buildEmpresaCard(context, empresa, authService);
      },
    );
  }

  Widget _buildEmpresaCard(
    BuildContext context,
    Empresa empresa,
    AuthService authService,
  ) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: InkWell(
        onTap: _isLoading ? null : () async {
          setState(() => _isLoading = true);
          try {
            await authService.selecionarEmpresa(empresa);
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
}


