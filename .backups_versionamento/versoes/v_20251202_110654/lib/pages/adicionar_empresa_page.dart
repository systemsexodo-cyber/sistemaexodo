import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../services/auth_service.dart';
import '../models/empresa.dart';
import '../theme.dart';

/// Página para adicionar ou editar uma empresa
class AdicionarEmpresaPage extends StatefulWidget {
  final Empresa? empresa;

  const AdicionarEmpresaPage({super.key, this.empresa});

  @override
  State<AdicionarEmpresaPage> createState() => _AdicionarEmpresaPageState();
}

class _AdicionarEmpresaPageState extends State<AdicionarEmpresaPage> {
  final _formKey = GlobalKey<FormState>();
  final _razaoSocialController = TextEditingController();
  final _nomeFantasiaController = TextEditingController();
  final _cnpjController = TextEditingController();
  final _inscricaoEstadualController = TextEditingController();
  final _inscricaoMunicipalController = TextEditingController();
  final _emailController = TextEditingController();
  final _telefoneController = TextEditingController();
  final _celularController = TextEditingController();
  final _siteController = TextEditingController();
  final _enderecoController = TextEditingController();
  final _numeroController = TextEditingController();
  final _complementoController = TextEditingController();
  final _bairroController = TextEditingController();
  final _cidadeController = TextEditingController();
  final _estadoController = TextEditingController();
  final _cepController = TextEditingController();
  final _corPrimariaController = TextEditingController();
  final _corSecundariaController = TextEditingController();

  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    if (widget.empresa != null) {
      _preencherCampos(widget.empresa!);
    }
  }

  void _preencherCampos(Empresa empresa) {
    _razaoSocialController.text = empresa.razaoSocial;
    _nomeFantasiaController.text = empresa.nomeFantasia ?? '';
    _cnpjController.text = empresa.cnpj ?? '';
    _inscricaoEstadualController.text = empresa.inscricaoEstadual ?? '';
    _inscricaoMunicipalController.text = empresa.inscricaoMunicipal ?? '';
    _emailController.text = empresa.email ?? '';
    _telefoneController.text = empresa.telefone ?? '';
    _celularController.text = empresa.celular ?? '';
    _siteController.text = empresa.site ?? '';
    _enderecoController.text = empresa.endereco ?? '';
    _numeroController.text = empresa.numero ?? '';
    _complementoController.text = empresa.complemento ?? '';
    _bairroController.text = empresa.bairro ?? '';
    _cidadeController.text = empresa.cidade ?? '';
    _estadoController.text = empresa.estado ?? '';
    _cepController.text = empresa.cep ?? '';
    _corPrimariaController.text = empresa.corPrimaria ?? '';
    _corSecundariaController.text = empresa.corSecundaria ?? '';
  }

  @override
  void dispose() {
    _razaoSocialController.dispose();
    _nomeFantasiaController.dispose();
    _cnpjController.dispose();
    _inscricaoEstadualController.dispose();
    _inscricaoMunicipalController.dispose();
    _emailController.dispose();
    _telefoneController.dispose();
    _celularController.dispose();
    _siteController.dispose();
    _enderecoController.dispose();
    _numeroController.dispose();
    _complementoController.dispose();
    _bairroController.dispose();
    _cidadeController.dispose();
    _estadoController.dispose();
    _cepController.dispose();
    _corPrimariaController.dispose();
    _corSecundariaController.dispose();
    super.dispose();
  }

  Future<void> _salvar() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isLoading = true);

    final authService = Provider.of<AuthService>(context, listen: false);
    final agora = DateTime.now();

    final empresa = Empresa(
      id: widget.empresa?.id ?? const Uuid().v4(),
      razaoSocial: _razaoSocialController.text.trim(),
      nomeFantasia: _nomeFantasiaController.text.trim().isEmpty
          ? null
          : _nomeFantasiaController.text.trim(),
      cnpj: _cnpjController.text.trim().isEmpty
          ? null
          : _cnpjController.text.trim(),
      inscricaoEstadual: _inscricaoEstadualController.text.trim().isEmpty
          ? null
          : _inscricaoEstadualController.text.trim(),
      inscricaoMunicipal: _inscricaoMunicipalController.text.trim().isEmpty
          ? null
          : _inscricaoMunicipalController.text.trim(),
      email: _emailController.text.trim().isEmpty
          ? null
          : _emailController.text.trim(),
      telefone: _telefoneController.text.trim().isEmpty
          ? null
          : _telefoneController.text.trim(),
      celular: _celularController.text.trim().isEmpty
          ? null
          : _celularController.text.trim(),
      site: _siteController.text.trim().isEmpty
          ? null
          : _siteController.text.trim(),
      endereco: _enderecoController.text.trim().isEmpty
          ? null
          : _enderecoController.text.trim(),
      numero: _numeroController.text.trim().isEmpty
          ? null
          : _numeroController.text.trim(),
      complemento: _complementoController.text.trim().isEmpty
          ? null
          : _complementoController.text.trim(),
      bairro: _bairroController.text.trim().isEmpty
          ? null
          : _bairroController.text.trim(),
      cidade: _cidadeController.text.trim().isEmpty
          ? null
          : _cidadeController.text.trim(),
      estado: _estadoController.text.trim().isEmpty
          ? null
          : _estadoController.text.trim(),
      cep: _cepController.text.trim().isEmpty
          ? null
          : _cepController.text.trim(),
      corPrimaria: _corPrimariaController.text.trim().isEmpty
          ? null
          : _corPrimariaController.text.trim(),
      corSecundaria: _corSecundariaController.text.trim().isEmpty
          ? null
          : _corSecundariaController.text.trim(),
      ativo: widget.empresa?.ativo ?? true,
      createdAt: widget.empresa?.createdAt ?? agora,
      updatedAt: agora,
    );

    try {
      if (widget.empresa == null) {
        await authService.adicionarEmpresa(empresa);
      } else {
        await authService.atualizarEmpresa(empresa);
      }

      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao salvar: $e'),
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
    return AppTheme.appBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(widget.empresa == null ? 'Adicionar Empresa' : 'Editar Empresa'),
        ),
        body: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Informações básicas
              _buildSectionTitle('Informações Básicas'),
              _buildTextField(
                controller: _razaoSocialController,
                label: 'Razão Social *',
                icon: Icons.business,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Campo obrigatório';
                  }
                  return null;
                },
              ),
              _buildTextField(
                controller: _nomeFantasiaController,
                label: 'Nome Fantasia',
                icon: Icons.store,
              ),
              _buildTextField(
                controller: _cnpjController,
                label: 'CNPJ',
                icon: Icons.badge,
              ),
              _buildTextField(
                controller: _inscricaoEstadualController,
                label: 'Inscrição Estadual',
                icon: Icons.description,
              ),
              _buildTextField(
                controller: _inscricaoMunicipalController,
                label: 'Inscrição Municipal',
                icon: Icons.description_outlined,
              ),

              const SizedBox(height: 24),

              // Contato
              _buildSectionTitle('Contato'),
              _buildTextField(
                controller: _emailController,
                label: 'Email',
                icon: Icons.email,
                keyboardType: TextInputType.emailAddress,
              ),
              _buildTextField(
                controller: _telefoneController,
                label: 'Telefone',
                icon: Icons.phone,
                keyboardType: TextInputType.phone,
              ),
              _buildTextField(
                controller: _celularController,
                label: 'Celular',
                icon: Icons.phone_android,
                keyboardType: TextInputType.phone,
              ),
              _buildTextField(
                controller: _siteController,
                label: 'Site',
                icon: Icons.language,
                keyboardType: TextInputType.url,
              ),

              const SizedBox(height: 24),

              // Endereço
              _buildSectionTitle('Endereço'),
              _buildTextField(
                controller: _enderecoController,
                label: 'Endereço',
                icon: Icons.location_on,
              ),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: _buildTextField(
                      controller: _numeroController,
                      label: 'Número',
                      icon: Icons.numbers,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 3,
                    child: _buildTextField(
                      controller: _complementoController,
                      label: 'Complemento',
                      icon: Icons.home,
                    ),
                  ),
                ],
              ),
              _buildTextField(
                controller: _bairroController,
                label: 'Bairro',
                icon: Icons.location_city,
              ),
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: _buildTextField(
                      controller: _cidadeController,
                      label: 'Cidade',
                      icon: Icons.apartment,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 1,
                    child: _buildTextField(
                      controller: _estadoController,
                      label: 'UF',
                      icon: Icons.map,
                      maxLength: 2,
                    ),
                  ),
                ],
              ),
              _buildTextField(
                controller: _cepController,
                label: 'CEP',
                icon: Icons.pin,
                keyboardType: TextInputType.number,
              ),

              const SizedBox(height: 24),

              // Cores (opcional)
              _buildSectionTitle('Personalização (Opcional)'),
              _buildTextField(
                controller: _corPrimariaController,
                label: 'Cor Primária (hex)',
                icon: Icons.palette,
                hintText: '#2196F3',
              ),
              _buildTextField(
                controller: _corSecundariaController,
                label: 'Cor Secundária (hex)',
                icon: Icons.palette_outlined,
                hintText: '#1565C0',
              ),

              const SizedBox(height: 32),

              // Botão salvar
              ElevatedButton(
                onPressed: _isLoading ? null : _salvar,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        widget.empresa == null ? 'Adicionar Empresa' : 'Salvar Alterações',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16, top: 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? hintText,
    TextInputType? keyboardType,
    int? maxLength,
    String? Function(String?)? validator,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        maxLength: maxLength,
        validator: validator,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          labelText: label,
          hintText: hintText,
          prefixIcon: Icon(icon, color: Colors.white70),
          filled: true,
          fillColor: Colors.white.withOpacity(0.1),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.blueAccent, width: 2),
          ),
        ),
      ),
    );
  }
}


