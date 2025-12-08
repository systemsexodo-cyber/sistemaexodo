import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:file_picker/file_picker.dart';
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
  
  int? _crt; // Código de Regime Tributário
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
  final _codigoIBGEController = TextEditingController();
  
  // Campos NFC-e
  final _senhaCertificadoController = TextEditingController();
  final _cscController = TextEditingController();
  final _cscIdTokenController = TextEditingController();
  final _serieNFCeController = TextEditingController();
  String? _certificadoDigitalUrl;
  String? _certificadoDigitalBytes; // Bytes do certificado em base64
  String? _certificadoDigitalNome;
  bool _ambienteHomologacao = true; // Padrão: homologação
  
  Color _corPrimaria = Colors.blueAccent;
  Color _corSecundaria = Colors.blue;

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
    _crt = empresa.crt;
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
    _codigoIBGEController.text = empresa.codigoIBGE ?? '';
    
    // Campos NFC-e
    _certificadoDigitalUrl = empresa.certificadoDigitalUrl;
    _certificadoDigitalBytes = empresa.certificadoDigitalBytes;
    _certificadoDigitalNome = _certificadoDigitalUrl != null 
        ? _certificadoDigitalUrl!.split('/').last 
        : (_certificadoDigitalBytes != null ? 'Certificado carregado' : null);
    _senhaCertificadoController.text = empresa.senhaCertificado ?? '';
    _cscController.text = empresa.csc ?? '';
    _cscIdTokenController.text = empresa.cscIdToken ?? '';
    _serieNFCeController.text = empresa.serieNFCe ?? '1';
    _ambienteHomologacao = empresa.ambienteHomologacao ?? true;
    
    // Converter cores hex para Color
    if (empresa.corPrimaria != null && empresa.corPrimaria!.isNotEmpty) {
      _corPrimaria = _hexToColor(empresa.corPrimaria!) ?? Colors.blueAccent;
    }
    if (empresa.corSecundaria != null && empresa.corSecundaria!.isNotEmpty) {
      _corSecundaria = _hexToColor(empresa.corSecundaria!) ?? Colors.blue;
    }
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
    _senhaCertificadoController.dispose();
    _cscController.dispose();
    _cscIdTokenController.dispose();
    _serieNFCeController.dispose();
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
      crt: _crt,
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
      codigoIBGE: _codigoIBGEController.text.trim().isEmpty
          ? null
          : _codigoIBGEController.text.trim(),
      corPrimaria: _colorToHex(_corPrimaria),
      corSecundaria: _colorToHex(_corSecundaria),
      ativo: widget.empresa?.ativo ?? true,
      createdAt: widget.empresa?.createdAt ?? agora,
      updatedAt: agora,
      certificadoDigitalUrl: _certificadoDigitalUrl,
      certificadoDigitalBytes: _certificadoDigitalBytes,
      senhaCertificado: _senhaCertificadoController.text.trim().isEmpty
          ? null
          : _senhaCertificadoController.text.trim(),
      csc: _cscController.text.trim().isEmpty
          ? null
          : _cscController.text.trim(),
      cscIdToken: _cscIdTokenController.text.trim().isEmpty
          ? null
          : _cscIdTokenController.text.trim(),
      serieNFCe: _serieNFCeController.text.trim().isEmpty
          ? '1'
          : _serieNFCeController.text.trim(),
      ambienteHomologacao: _ambienteHomologacao,
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
              _buildCrtDropdown(),

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
              _buildTextField(
                controller: _codigoIBGEController,
                label: 'Código IBGE do Município (7 dígitos)',
                icon: Icons.numbers,
                keyboardType: TextInputType.number,
                helperText: 'Código IBGE do município para emissão de NFC-e',
              ),

              const SizedBox(height: 24),

              // Configurações NFC-e
              _buildSectionTitle('Configurações NFC-e (Opcional)'),
              _buildCertificadoUpload(),
              const SizedBox(height: 16),
              _buildTextField(
                controller: _senhaCertificadoController,
                label: 'Senha do Certificado Digital',
                icon: Icons.lock,
                keyboardType: TextInputType.text,
                obscureText: true,
              ),
              _buildTextField(
                controller: _cscController,
                label: 'CSC (Código de Segurança do Contribuinte)',
                icon: Icons.security,
                hintText: 'Fornecido pela SEFAZ',
                helperText: 'Código alfanumérico fornecido pela SEFAZ',
              ),
              _buildTextField(
                controller: _cscIdTokenController,
                label: 'ID Token CSC',
                icon: Icons.vpn_key,
                hintText: 'ID Token do CSC fornecido pela SEFAZ',
                helperText: 'Identificador do token CSC',
              ),
              const SizedBox(height: 16),
              // Série da NFC-e
              _buildTextField(
                controller: _serieNFCeController,
                label: 'Série da NFC-e',
                icon: Icons.confirmation_number,
                hintText: 'Ex: 1',
                helperText: 'Série da NFC-e (padrão: 1). Cada empresa deve ter sua própria série.',
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),
              // Ambiente (Homologação/Produção)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.1),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _ambienteHomologacao ? Icons.bug_report : Icons.verified_user,
                          color: _ambienteHomologacao ? Colors.orange : Colors.green,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'Ambiente de Emissão',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () => setState(() => _ambienteHomologacao = true),
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: _ambienteHomologacao
                                    ? Colors.orange.withOpacity(0.2)
                                    : Colors.white.withOpacity(0.05),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: _ambienteHomologacao
                                      ? Colors.orange
                                      : Colors.white.withOpacity(0.2),
                                  width: _ambienteHomologacao ? 2 : 1,
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.bug_report,
                                    color: _ambienteHomologacao ? Colors.orange : Colors.white54,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Homologação',
                                    style: TextStyle(
                                      color: _ambienteHomologacao ? Colors.orange : Colors.white54,
                                      fontWeight: _ambienteHomologacao ? FontWeight.bold : FontWeight.normal,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: GestureDetector(
                            onTap: () => setState(() => _ambienteHomologacao = false),
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: !_ambienteHomologacao
                                    ? Colors.green.withOpacity(0.2)
                                    : Colors.white.withOpacity(0.05),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: !_ambienteHomologacao
                                      ? Colors.green
                                      : Colors.white.withOpacity(0.2),
                                  width: !_ambienteHomologacao ? 2 : 1,
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.verified_user,
                                    color: !_ambienteHomologacao ? Colors.green : Colors.white54,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Produção',
                                    style: TextStyle(
                                      color: !_ambienteHomologacao ? Colors.green : Colors.white54,
                                      fontWeight: !_ambienteHomologacao ? FontWeight.bold : FontWeight.normal,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _ambienteHomologacao
                          ? '⚠️ Ambiente de testes. Use para validar antes de produção.'
                          : '✅ Ambiente de produção. NFC-e emitidas terão validade fiscal.',
                      style: TextStyle(
                        color: _ambienteHomologacao ? Colors.orange.shade300 : Colors.green.shade300,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Cores (opcional)
              _buildSectionTitle('Personalização (Opcional)'),
              _buildColorPicker(
                label: 'Cor Primária',
                icon: Icons.palette,
                color: _corPrimaria,
                onColorChanged: (color) {
                  setState(() {
                    _corPrimaria = color;
                  });
                },
              ),
              const SizedBox(height: 16),
              _buildColorPicker(
                label: 'Cor Secundária',
                icon: Icons.palette_outlined,
                color: _corSecundaria,
                onColorChanged: (color) {
                  setState(() {
                    _corSecundaria = color;
                  });
                },
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
    String? helperText,
    TextInputType? keyboardType,
    int? maxLength,
    bool obscureText = false,
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
        obscureText: obscureText,
        decoration: InputDecoration(
          labelText: label,
          hintText: hintText,
          helperText: helperText,
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

  /// Widget para upload do certificado digital
  Widget _buildCertificadoUpload() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: InkWell(
        onTap: _selecionarCertificado,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Colors.white.withOpacity(0.2),
            ),
          ),
          child: Row(
            children: [
              const Icon(Icons.upload_file, color: Colors.white70),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Certificado Digital (.pfx)',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _certificadoDigitalNome ?? 'Nenhum arquivo selecionado',
                      style: TextStyle(
                        color: _certificadoDigitalNome != null 
                            ? Colors.white70 
                            : Colors.white54,
                        fontSize: 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (_certificadoDigitalNome != null)
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white70),
                  onPressed: () {
          setState(() {
            _certificadoDigitalUrl = null;
            _certificadoDigitalBytes = null;
            _certificadoDigitalNome = null;
          });
                  },
                  tooltip: 'Remover certificado',
                ),
              const SizedBox(width: 8),
              const Icon(
                Icons.arrow_forward_ios,
                color: Colors.white54,
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Seleciona o arquivo do certificado digital
  Future<void> _selecionarCertificado() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pfx', 'p12'],
        withData: true,
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.single;
        
        if (file.bytes != null) {
          // Converter bytes para base64 para armazenar no localStorage
          final base64Bytes = base64Encode(file.bytes!);
          setState(() {
            _certificadoDigitalNome = file.name;
            _certificadoDigitalBytes = base64Bytes;
            // Manter URL apenas para referência (nome do arquivo)
            _certificadoDigitalUrl = 'certificados/${DateTime.now().millisecondsSinceEpoch}_${file.name}';
          });

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('✓ Certificado "${file.name}" selecionado'),
                backgroundColor: Colors.green,
                duration: const Duration(seconds: 2),
              ),
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('⚠️ Erro ao ler o arquivo do certificado'),
                backgroundColor: Colors.orange,
              ),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao selecionar certificado: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Widget para seleção do CRT (Código de Regime Tributário)
  Widget _buildCrtDropdown() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: DropdownButtonFormField<int>(
        value: _crt,
        decoration: InputDecoration(
          labelText: 'Regime Tributário (CRT)',
          hintText: 'Selecione o regime tributário',
          helperText: 'Código de Regime Tributário para emissão de NFC-e',
          prefixIcon: const Icon(Icons.account_balance, color: Colors.white70),
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
        dropdownColor: const Color(0xFF2D2D3E),
        style: const TextStyle(color: Colors.white),
        icon: const Icon(Icons.arrow_drop_down, color: Colors.white70),
        items: const [
          DropdownMenuItem<int>(
            value: 1,
            child: Text('1 - Simples Nacional'),
          ),
          DropdownMenuItem<int>(
            value: 2,
            child: Text('2 - Simples Nacional - Excesso de Sublimite'),
          ),
          DropdownMenuItem<int>(
            value: 3,
            child: Text('3 - Regime Normal'),
          ),
        ],
        onChanged: (value) {
          setState(() {
            _crt = value;
          });
        },
      ),
    );
  }

  /// Converte Color para hex string
  String _colorToHex(Color color) {
    return '#${color.value.toRadixString(16).substring(2).toUpperCase()}';
  }

  /// Converte hex string para Color
  Color? _hexToColor(String hex) {
    try {
      final hexCode = hex.replaceAll('#', '');
      return Color(int.parse('FF$hexCode', radix: 16));
    } catch (e) {
      return null;
    }
  }

  /// Widget para seleção de cor
  Widget _buildColorPicker({
    required String label,
    required IconData icon,
    required Color color,
    required ValueChanged<Color> onColorChanged,
  }) {
    return InkWell(
      onTap: () => _mostrarColorPicker(context, color, onColorChanged),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.white.withOpacity(0.2),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.white70),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                ),
              ),
            ),
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Colors.white.withOpacity(0.3),
                  width: 2,
                ),
              ),
            ),
            const SizedBox(width: 8),
            const Icon(
              Icons.arrow_forward_ios,
              color: Colors.white54,
              size: 16,
            ),
          ],
        ),
      ),
    );
  }

  /// Mostra o seletor de cor
  void _mostrarColorPicker(
    BuildContext context,
    Color corAtual,
    ValueChanged<Color> onColorChanged,
  ) {
    Color corSelecionada = corAtual;
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E2E),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text(
            'Selecionar Cor',
            style: TextStyle(color: Colors.white),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Preview da cor atual
              Container(
                width: double.infinity,
                height: 60,
                decoration: BoxDecoration(
                  color: corSelecionada,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white.withOpacity(0.3)),
                ),
                child: Center(
                  child: Text(
                    'Cor Selecionada: ${_colorToHex(corSelecionada)}',
                    style: TextStyle(
                      color: corSelecionada.computeLuminance() > 0.5
                          ? Colors.black
                          : Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Cores Predefinidas:',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              // Cores predefinidas
              Flexible(
                child: SingleChildScrollView(
                  child: _buildColorGrid(
                    [
                      Colors.blueAccent,
                      Colors.blue,
                      Colors.indigo,
                      Colors.purple,
                      Colors.pink,
                      Colors.red,
                      Colors.orange,
                      Colors.amber,
                      Colors.yellow,
                      Colors.lime,
                      Colors.green,
                      Colors.teal,
                      Colors.cyan,
                      Colors.brown,
                      Colors.grey,
                      Colors.black,
                    ],
                    corSelecionada,
                    (cor) {
                      setState(() {
                        corSelecionada = cor;
                      });
                    },
                  ),
                ),
              ),
            ],
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
              onPressed: () {
                onColorChanged(corSelecionada);
                Navigator.of(context).pop();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: corSelecionada,
                foregroundColor: corSelecionada.computeLuminance() > 0.5
                    ? Colors.black
                    : Colors.white,
              ),
              child: const Text('Usar Esta Cor'),
            ),
          ],
        ),
      ),
    );
  }

  /// Grid de cores predefinidas
  Widget _buildColorGrid(
    List<Color> cores,
    Color corSelecionada,
    ValueChanged<Color> onColorChanged,
  ) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: cores.map((cor) {
        final isSelecionada = cor.value == corSelecionada.value;
        return GestureDetector(
          onTap: () {
            onColorChanged(cor);
          },
          child: Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: cor,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isSelecionada ? Colors.white : Colors.white.withOpacity(0.3),
                width: isSelecionada ? 3 : 1,
              ),
            ),
            child: isSelecionada
                ? const Icon(
                    Icons.check,
                    color: Colors.white,
                    size: 20,
                  )
                : null,
          ),
        );
      }).toList(),
    );
  }
}


