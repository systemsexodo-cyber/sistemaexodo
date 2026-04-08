import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import '../services/auth_service.dart';
import '../services/certificado_service.dart';
import '../services/certificado_backend_service.dart';
import '../services/windows_certificate_service.dart';
import '../models/empresa.dart';
import '../models/tela_sistema.dart';
import '../theme.dart';
import '../services/data_service.dart';
import '../services/whatsapp_service.dart';
import 'package:sistema_exodo_novo/pages/whatsapp_gerenciamento_page.dart';

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
  String? _certificadoDigitalNome;
  String? _certificadoDigitalBytes; // Bytes em base64 (fallback se não conseguir salvar arquivo)
  String? _certificadoWindowsThumbprint; // Thumbprint do certificado do Windows
  final _ultimoNumeroNFCeController = TextEditingController(); // Novo: controle de numeração
  bool _ambienteHomologacao = true; // Padrão: homologação
  final _bridgeNfceUrlController = TextEditingController(text: 'http://localhost:8000');

  final _bridgeNfceKeyController = TextEditingController();
  
  // Customizações de Impressão NFC-e

  final _nfceMargemEsquerdaController = TextEditingController(text: '5.0');
  final _nfceLarguraBobinaController = TextEditingController(text: '80.0');
  final _nfceMargemDireitaController = TextEditingController(text: '15.0');
  final _nfceFonteEscalaController = TextEditingController(text: '1.0');

  // Customizações de Impressão Comanda/Mesa
  final _comandaMargemEsqController = TextEditingController(text: '10.0');
  final _comandaMargemDirController = TextEditingController(text: '15.0');
  final _comandaMargemVController = TextEditingController(text: '10.0');
  final _comandaLarguraBobinaController = TextEditingController(text: '80.0');
  final _comandaFonteTituloController = TextEditingController(text: '14.0');
  final _comandaFonteCorpoController = TextEditingController(text: '9.0');
  final _comandaFonteStatusController = TextEditingController(text: '8.0');
  bool _comandaNegrito = true;

  
  Color _corPrimaria = Colors.blueAccent;
  Color _corSecundaria = Colors.blue;
  
  // Controle de acesso às telas
  Set<String> _telasPermitidas = {}; // Vazio = todas permitidas

  // Campos WhatsApp (Evolution API)
  final _whatsappApiUrlController = TextEditingController();
  final _whatsappApiKeyController = TextEditingController();
  final _whatsappInstanceNameController = TextEditingController();
  bool _whatsappAtivo = false;
  String _whatsappTipo = 'evolution'; // 'evolution' ou 'twilio'
  bool _moduloPet = false;
  String? _whatsappConnectionState; // 'open', 'close', ou null
  bool _whatsappTestando = false;

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
    _certificadoDigitalBytes = empresa.configuracoes?['certificadoDigitalBytes'] as String?;
    _certificadoWindowsThumbprint = empresa.configuracoes?['certificadoWindowsThumbprint'] as String?;
    
    debugPrint('>>> [AdicionarEmpresa] Carregando certificado da empresa:');
    debugPrint('>>> [AdicionarEmpresa]   certificadoDigitalUrl: $_certificadoDigitalUrl');
    debugPrint('>>> [AdicionarEmpresa]   certificadoDigitalBytes: ${_certificadoDigitalBytes != null ? "presente (${_certificadoDigitalBytes!.length} chars)" : "null"}');
    debugPrint('>>> [AdicionarEmpresa]   certificadoWindowsThumbprint: $_certificadoWindowsThumbprint');
    
    // Determinar nome do certificado
    if (_certificadoWindowsThumbprint != null) {
      // Se tem thumbprint do Windows, tentar buscar o subject do certificado
      _certificadoDigitalNome = empresa.configuracoes?['certificadoWindowsSubject'] as String? ?? 'Certificado do Windows';
      debugPrint('>>> [AdicionarEmpresa] Certificado do Windows carregado: $_certificadoDigitalNome');
    } else if (_certificadoDigitalUrl != null) {
      _certificadoDigitalNome = _certificadoDigitalUrl!.split('/').last
          .replaceAll('base64:', '')
          .replaceAll('base64:pem:', '')
          .replaceAll('windows:pem:', '');
      debugPrint('>>> [AdicionarEmpresa] Certificado de arquivo carregado: $_certificadoDigitalNome');
    } else {
      _certificadoDigitalNome = null;
      debugPrint('>>> [AdicionarEmpresa] Nenhum certificado encontrado');
    }
    
    _senhaCertificadoController.text = empresa.senhaCertificado ?? '';
    _cscController.text = empresa.csc ?? '';
    _cscIdTokenController.text = empresa.cscIdToken ?? '';
    _serieNFCeController.text = empresa.serieNFCe ?? '1';
    _ambienteHomologacao = empresa.ambienteHomologacao ?? true;
    _ultimoNumeroNFCeController.text = empresa.configuracoes?['ultimo_numero_nfce']?.toString() ?? '';

    _bridgeNfceUrlController.text = empresa.configuracoes?['bridgeNfceUrl'] as String? ?? 'http://localhost:8000';
    _bridgeNfceKeyController.text = empresa.configuracoes?['bridgeNfceKey'] as String? ?? '';

    _nfceMargemEsquerdaController.text = empresa.configuracoes?['nfceMargemEsquerda']?.toString() ?? '5.0';
    _nfceLarguraBobinaController.text = empresa.configuracoes?['nfceLarguraBobina']?.toString() ?? '80.0';
    _nfceMargemDireitaController.text = empresa.configuracoes?['nfceMargemDireita']?.toString() ?? '15.0';
    _nfceFonteEscalaController.text = empresa.configuracoes?['nfceFonteEscala']?.toString() ?? '1.0';
    _comandaMargemEsqController.text = empresa.configuracoes?['comandaMargemEsq']?.toString() ?? 
                                       empresa.configuracoes?['comandaMargemH']?.toString() ?? '10.0';
    _comandaMargemDirController.text = empresa.configuracoes?['comandaMargemDir']?.toString() ?? 
                                       empresa.configuracoes?['comandaMargemH']?.toString() ?? '15.0';
    _comandaMargemVController.text = empresa.configuracoes?['comandaMargemV']?.toString() ?? '10.0';
    _comandaLarguraBobinaController.text = empresa.configuracoes?['comandaLarguraBobina']?.toString() ?? '80.0';
    _comandaFonteTituloController.text = empresa.configuracoes?['comandaFonteTitulo']?.toString() ?? '14.0';
    _comandaFonteCorpoController.text = empresa.configuracoes?['comandaFonteCorpo']?.toString() ?? '9.0';
    _comandaFonteStatusController.text = empresa.configuracoes?['comandaFonteStatus']?.toString() ?? '8.0';
    _comandaNegrito = empresa.configuracoes?['comandaNegrito'] ?? true;

    
    // Converter cores hex para Color
    if (empresa.corPrimaria != null && empresa.corPrimaria!.isNotEmpty) {
      _corPrimaria = _hexToColor(empresa.corPrimaria!) ?? Colors.blueAccent;
    }
    if (empresa.corSecundaria != null && empresa.corSecundaria!.isNotEmpty) {
      _corSecundaria = _hexToColor(empresa.corSecundaria!) ?? Colors.blue;
    }
    
    // Carregar telas permitidas
    _telasPermitidas = empresa.telasPermitidas != null
        ? Set<String>.from(empresa.telasPermitidas!)
        : <String>{}; // Vazio = todas permitidas
    
    // Campos WhatsApp
    _whatsappApiUrlController.text = empresa.whatsappApiUrl ?? '';
    _whatsappApiKeyController.text = empresa.whatsappApiKey ?? '';
    _whatsappInstanceNameController.text = empresa.whatsappInstanceName ?? '';
    _whatsappAtivo = empresa.whatsappAtivo;
    _whatsappTipo = empresa.whatsappTipo ?? 'evolution';
    _moduloPet = empresa.moduloPet;
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
    _whatsappApiUrlController.dispose();
    _whatsappApiKeyController.dispose();
    _whatsappInstanceNameController.dispose();
    _ultimoNumeroNFCeController.dispose();

    _bridgeNfceUrlController.dispose();
    _bridgeNfceKeyController.dispose();

    _nfceMargemEsquerdaController.dispose();
    _nfceLarguraBobinaController.dispose();
    _nfceMargemDireitaController.dispose();
    _nfceFonteEscalaController.dispose();

    super.dispose();
  }

  Future<void> _salvar() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isLoading = true);
    debugPrint('>>> [AdicionarEmpresa] Iniciando salvamento da empresa...');

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final agora = DateTime.now();

      debugPrint('>>> [AdicionarEmpresa] Criando objeto Empresa...');
      final empresa = Empresa(
      id: widget.empresa?.id ?? const Uuid().v4(),
      razaoSocial: _razaoSocialController.text.trim(),
      slug: Empresa.gerarSlug(_nomeFantasiaController.text.trim().isNotEmpty 
          ? _nomeFantasiaController.text.trim() 
          : _razaoSocialController.text.trim()),
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
      telasPermitidas: _telasPermitidas.isEmpty ? null : _telasPermitidas,
      whatsappApiUrl: _whatsappApiUrlController.text.trim().isEmpty
          ? null
          : _whatsappApiUrlController.text.trim(),
      whatsappApiKey: _whatsappApiKeyController.text.trim().isEmpty
          ? null
          : _whatsappApiKeyController.text.trim(),
      whatsappInstanceName: _whatsappInstanceNameController.text.trim().isEmpty
          ? null
          : _whatsappInstanceNameController.text.trim(),
      whatsappTipo: _whatsappTipo,
      whatsappAtivo: _whatsappAtivo,
      moduloPet: _moduloPet,
      configuracoes: {
        ...?widget.empresa?.configuracoes, // Preservar outras configurações
        if (_certificadoDigitalBytes != null)
          'certificadoDigitalBytes': _certificadoDigitalBytes,
        if (_certificadoWindowsThumbprint != null)
          'certificadoWindowsThumbprint': _certificadoWindowsThumbprint,
        if (_certificadoWindowsThumbprint != null && _certificadoDigitalNome != null)
          'certificadoWindowsSubject': _certificadoDigitalNome,
        'bridgeNfceUrl': _bridgeNfceUrlController.text.trim(),
        'bridgeNfceKey': _bridgeNfceKeyController.text.trim(),

        'nfceMargemEsquerda': double.tryParse(_nfceMargemEsquerdaController.text.trim()) ?? 5.0,
        'nfceLarguraBobina': double.tryParse(_nfceLarguraBobinaController.text.trim()) ?? 80.0,
        'nfceMargemDireita': double.tryParse(_nfceMargemDireitaController.text.trim()) ?? 15.0,
        'nfceFonteEscala': double.tryParse(_nfceFonteEscalaController.text.trim()) ?? 1.0,

        'comandaMargemEsq': double.tryParse(_comandaMargemEsqController.text.trim()) ?? 10.0,
        'comandaMargemDir': double.tryParse(_comandaMargemDirController.text.trim()) ?? 15.0,
        'comandaMargemV': double.tryParse(_comandaMargemVController.text.trim()) ?? 10.0,
        'comandaLarguraBobina': double.tryParse(_comandaLarguraBobinaController.text.trim()) ?? 80.0,
        'comandaFonteTitulo': double.tryParse(_comandaFonteTituloController.text.trim()) ?? 14.0,
        'comandaFonteCorpo': double.tryParse(_comandaFonteCorpoController.text.trim()) ?? 9.0,
        'comandaFonteStatus': double.tryParse(_comandaFonteStatusController.text.trim()) ?? 8.0,
        'comandaNegrito': _comandaNegrito,

        'ultimo_numero_nfce': _ultimoNumeroNFCeController.text.trim().isEmpty ? null : _ultimoNumeroNFCeController.text.trim(),
      },
    );

      debugPrint('>>> [AdicionarEmpresa] Objeto Empresa criado. ID: ${empresa.id}');
      debugPrint('>>> [AdicionarEmpresa] Razão Social: ${empresa.razaoSocial}');
      debugPrint('>>> [AdicionarEmpresa] Certificado presente: ${empresa.configuracoes?['certificadoDigitalBytes'] != null ? "SIM" : "NÃO"}');
      
      if (widget.empresa == null) {
        debugPrint('>>> [AdicionarEmpresa] Adicionando nova empresa...');
        await authService.adicionarEmpresa(empresa);
        debugPrint('>>> [AdicionarEmpresa] ✓ Empresa adicionada com sucesso');
      } else {
        debugPrint('>>> [AdicionarEmpresa] Atualizando empresa existente...');
        await authService.atualizarEmpresa(empresa);
        debugPrint('>>> [AdicionarEmpresa] ✓ Empresa atualizada com sucesso');
      }

      if (mounted) {
        debugPrint('>>> [AdicionarEmpresa] Fechando página e retornando...');
        Navigator.pop(context, true);
      }
    } catch (e, stackTrace) {
      debugPrint('>>> [AdicionarEmpresa] ❌ ERRO ao salvar empresa: $e');
      debugPrint('>>> [AdicionarEmpresa] StackTrace: $stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao salvar empresa: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) {
        debugPrint('>>> [AdicionarEmpresa] Finalizando - desativando loading');
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    final usuarioAtual = authService.usuarioAtual;
    
    // Verificar se o usuário é "user" (único que pode acessar configuração da empresa)
    final podeAcessar = usuarioAtual?.email.toLowerCase() == 'user';
    
    if (!podeAcessar) {
      return AppTheme.appBackground(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            title: Text(widget.empresa == null ? 'Adicionar Empresa' : 'Editar Empresa'),
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
                    'Apenas o usuário "user" pode acessar a configuração de empresas.',
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

              _buildSectionTitle('Configurações NFC-e (Executável local)'),
              _buildTextField(
                controller: _bridgeNfceUrlController,
                label: 'URL do Emissor Local (Bridge)',
                icon: Icons.lan,
                hintText: 'http://localhost:8000',
                helperText: 'Se usar o Firebase Online, coloque aqui o link do seu túnel (Zrok/Ngrok)',
              ),
              const SizedBox(height: 8),
              _buildTextField(
                controller: _bridgeNfceKeyController,
                label: 'Chave de API do Emissor',
                icon: Icons.key,
                obscureText: true,
                helperText: 'Chave gerada pelo executável (veja no log do bridge)',
              ),
              const SizedBox(height: 16),
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
              const SizedBox(height: 16),
              _buildSectionTitle('Ajustes de Impressão (NFC-e Térmica)'),
              Row(
                children: [
                  Expanded(
                    child: _buildTextField(
                      controller: _nfceMargemEsquerdaController,
                      label: 'Margem Esq. (mm)',
                      icon: Icons.format_align_left,
                      hintText: '5.0',
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildTextField(
                      controller: _nfceMargemDireitaController,
                      label: 'Margem Dir. (mm)',
                      icon: Icons.format_align_right,
                      hintText: '15.0',
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildTextField(
                controller: _nfceLarguraBobinaController,
                label: 'Largura da Bobina (mm)',
                icon: Icons.print,
                hintText: '80.0 ou 58.0',
                helperText: 'A largura do papel da sua impressora. Geralmente 80.0 (maiorinha) ou 58.0 (pequena/maquininha).',
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),
              _buildTextField(
                controller: _nfceFonteEscalaController,
                label: 'Escala da Fonte (Padrão: 1.0)',
                icon: Icons.format_size,
                hintText: '1.0',
                helperText: 'Ex: 0.8 para diminuir 20%, 1.2 para aumentar 20%',
                keyboardType: TextInputType.number,
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
              _buildTextField(
                controller: _ultimoNumeroNFCeController,
                label: 'Último número da NFC-e emitido',
                icon: Icons.numbers_rounded,
                hintText: 'Ex: 125',
                helperText: 'O sistema somará +1 para a próxima nota (ex: 126). Só altere se a SEFAZ estiver em um número diferente.',
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

              _buildSectionTitle('Ajuste de Todas as Impressões (Geral)'),
              Row(
                children: [
                  Expanded(
                    child: _buildTextField(
                      controller: _comandaMargemEsqController,
                      label: 'Margem Esquerda',
                      icon: Icons.format_align_left,
                      hintText: '10.0',
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildTextField(
                      controller: _comandaMargemDirController,
                      label: 'Margem Direita',
                      icon: Icons.format_align_right,
                      hintText: '15.0',
                      keyboardType: TextInputType.number,
                      helperText: 'Aumente se o valor estiver cortando à direita.',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildTextField(
                controller: _comandaMargemVController,
                label: 'Margem Superior/Inferior',
                icon: Icons.height,
                hintText: '10.0',
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),
              _buildTextField(
                controller: _comandaLarguraBobinaController,
                label: 'Largura Física da Bobina (mm)',
                icon: Icons.print,
                hintText: '80.0 ou 58.0',
                helperText: 'Largura do papel da impressora. Padrão: 80.0 (grande) ou 58.0 (pequena).',
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _buildTextField(
                      controller: _comandaFonteTituloController,
                      label: 'Tam. Fonte Título',
                      icon: Icons.title,
                      hintText: '14.0',
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildTextField(
                      controller: _comandaFonteCorpoController,
                      label: 'Tam. Fonte Itens',
                      icon: Icons.text_fields,
                      hintText: '9.0',
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildTextField(
                      controller: _comandaFonteStatusController,
                      label: 'Tam. Fonte Info',
                      icon: Icons.info_outline,
                      hintText: '8.0',
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SwitchListTile(
                title: const Text('Usar Negrito nos Textos Principais', style: TextStyle(color: Colors.white)),
                subtitle: const Text('Melhora a leitura em algumas impressoras térmicas', style: TextStyle(color: Colors.white60, fontSize: 11)),
                value: _comandaNegrito,
                onChanged: (value) => setState(() => _comandaNegrito = value),
                activeColor: Colors.purple,
                contentPadding: EdgeInsets.zero,
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

              const SizedBox(height: 24),

              // Configurações de Módulos
              _buildSectionTitle('Configurações de Módulos'),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.shade900.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.blue.shade400.withOpacity(0.3),
                  ),
                ),
                child: SwitchListTile(
                  title: const Text(
                    'Módulo Pet Shop',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                  subtitle: const Text(
                    'Habilita funções de agenda de banho, vacinas e cadastro de pets.',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  secondary: const Icon(Icons.pets, color: Colors.blueAccent),
                  value: _moduloPet,
                  onChanged: (value) {
                    setState(() {
                      _moduloPet = value;
                    });
                  },
                  activeColor: Colors.blueAccent,
                ),
              ),

              const SizedBox(height: 24),

              // Configuração WhatsApp (Evolution API)
              _buildSectionTitle('Integração WhatsApp (Evolution API)'),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.green.shade900.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.green.shade400.withOpacity(0.5),
                    width: 1.5,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header com switch
                    Row(
                      children: [
                        Icon(
                          Icons.chat,
                          color: Colors.green.shade300,
                          size: 24,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Notificações WhatsApp',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _whatsappAtivo
                                    ? 'Notificações ativas para agendamentos'
                                    : 'Ative para enviar notificações automáticas',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.white70,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Indicador de status
                        if (_whatsappAtivo && _whatsappConnectionState != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            margin: const EdgeInsets.only(right: 8),
                            decoration: BoxDecoration(
                              color: _whatsappConnectionState == 'open'
                                  ? Colors.green.withOpacity(0.3)
                                  : Colors.red.withOpacity(0.3),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _whatsappConnectionState == 'open'
                                      ? Icons.check_circle
                                      : Icons.error,
                                  size: 14,
                                  color: _whatsappConnectionState == 'open'
                                      ? Colors.green
                                      : Colors.red,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _whatsappConnectionState == 'open'
                                      ? 'Conectado'
                                      : 'Desconectado',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: _whatsappConnectionState == 'open'
                                        ? Colors.green
                                        : Colors.red,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        Switch(
                          value: _whatsappAtivo,
                          activeColor: Colors.green.shade400,
                          onChanged: (value) {
                            setState(() {
                              _whatsappAtivo = value;
                            });
                          },
                        ),
                      ],
                    ),
                    
                    if (_whatsappAtivo) ...[
                      const SizedBox(height: 16),
                      const Divider(color: Colors.white24),
                      const SizedBox(height: 16),
                      
                      // Seletor de Tipo
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Serviço de WhatsApp:',
                              style: TextStyle(color: Colors.white70, fontSize: 13),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                _buildTipoWhatsAppChip('evolution', 'Evolution API (Gratuito/Self-host)'),
                                const SizedBox(width: 8),
                                _buildTipoWhatsAppChip('twilio', 'Twilio Bridge (Pagamento p/ uso)'),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      
                      // URL da API
                      _buildTextField(
                        controller: _whatsappApiUrlController,
                        label: _whatsappTipo == 'evolution' ? 'URL da Evolution API' : 'URL da Ponte no Render',
                        icon: Icons.link,
                        hintText: _whatsappTipo == 'evolution' ? 'https://sua-api.up.railway.app' : 'https://seu-bridge.onrender.com',
                        helperText: _whatsappTipo == 'evolution' 
                          ? 'URL da sua instância Evolution' 
                          : 'URL do serviço que você criou no Render',
                      ),
                      
                      // API Key
                      _buildTextField(
                        controller: _whatsappApiKeyController,
                        label: _whatsappTipo == 'evolution' ? 'API Key' : 'BRIDGE_API_SECRET',
                        icon: Icons.vpn_key,
                        hintText: _whatsappTipo == 'evolution' ? 'Sua API Key' : 'Sua senha do Bridge',
                        helperText: _whatsappTipo == 'evolution' 
                          ? 'Chave de autenticação' 
                          : 'A senha que você configurou no Render',
                        obscureText: true,
                      ),
                      
                      // Nome da Instância (Opcional para Twilio)
                      if (_whatsappTipo == 'evolution') 
                        _buildTextField(
                          controller: _whatsappInstanceNameController,
                          label: 'Nome da Instância',
                          icon: Icons.phone_android,
                          hintText: 'empresa_principal',
                          helperText: 'Nome da instância criada na Evolution API',
                        ),
                      
                      const SizedBox(height: 16),
                      
                      // Botões de ação
                      Row(
                        children: [
                          // Botão Testar Conexão
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _whatsappTestando ? null : _testarConexaoWhatsApp,
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                side: BorderSide(color: Colors.green.shade400),
                              ),
                              icon: _whatsappTestando 
                                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Icon(Icons.refresh, color: Colors.green),
                              label: const Text('TESTAR CONEXÃO', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ],
                      ),
                      
                      // Botão para Gerenciamento Avançado
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => WhatsAppGerenciamentoPage()),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF25D366),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: const Icon(Icons.qr_code_scanner),
                        label: const Text('ABRIR PAINEL DE CONEXÃO (QR CODE)', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),

                      const SizedBox(height: 12),
                      const Text(
                        'Recomendamos utilizar o painel de conexão acima para configurar seu aparelho via QR Code.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white38, fontSize: 11),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 32),

              // Configuração de Acesso às Telas
              _buildSectionTitle('Controle de Acesso às Telas'),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.purple.shade900.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.purple.shade400.withOpacity(0.5),
                    width: 1.5,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.lock_outline, color: Colors.purple.shade300, size: 24),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Telas Permitidas',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _telasPermitidas.isEmpty
                                    ? 'Todas as telas estão permitidas'
                                    : '${_telasPermitidas.length} tela(s) selecionada(s)',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.white70,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: _telasPermitidas.isNotEmpty,
                          activeColor: Colors.purple.shade400,
                          onChanged: (value) {
                            setState(() {
                              if (value) {
                                // Ativar controle: selecionar todas as telas por padrão
                                _telasPermitidas = TelaSistema.values.map((t) => t.codigo).toSet();
                              } else {
                                // Desativar controle: permitir todas
                                _telasPermitidas.clear();
                              }
                            });
                          },
                        ),
                      ],
                    ),
                    if (_telasPermitidas.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      const Divider(color: Colors.white24),
                      const SizedBox(height: 8),
                      Text(
                        'Selecione as telas que podem ser acessadas pelos usuários desta empresa:',
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
                  ],
                ),
              ),

              const SizedBox(height: 32),

              // Botão deletar todos os dados operacionais (apenas quando editando empresa existente)
              if (widget.empresa != null) ...[
                OutlinedButton.icon(
                  onPressed: _isLoading ? null : () => _confirmarDeletarTodosDados(context),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    side: const BorderSide(color: Colors.red, width: 2),
                  ),
                  icon: const Icon(Icons.delete_sweep, color: Colors.red),
                  label: const Text(
                    'Deletar Todos os Dados',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.red),
                  ),
                ),
                const SizedBox(height: 8),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'Deleta produtos, pedidos, vendas, serviços, clientes e agendamentos desta empresa',
                    style: TextStyle(fontSize: 12, color: Colors.white70, fontStyle: FontStyle.italic),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 16),
              ],

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

  /// Testa a conexão com a Evolution API
  Future<void> _testarConexaoWhatsApp() async {
    final url = _whatsappApiUrlController.text.trim();
    final apiKey = _whatsappApiKeyController.text.trim();
    final instanceName = _whatsappInstanceNameController.text.trim();

    if (url.isEmpty || apiKey.isEmpty || instanceName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Preencha todos os campos da configuração WhatsApp'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _whatsappTestando = true);

    try {
      final service = WhatsAppService(
        apiUrl: url,
        apiKey: apiKey,
        instanceName: instanceName,
      );

      final state = await service.verificarConexao();
      
      if (mounted) {
        setState(() {
          _whatsappConnectionState = state;
          _whatsappTestando = false;
        });

        if (state == 'open') {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.white),
                  SizedBox(width: 8),
                  Text('WhatsApp conectado com sucesso!'),
                ],
              ),
              backgroundColor: Colors.green,
            ),
          );
        } else if (state == 'close') {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(Icons.warning, color: Colors.white),
                  SizedBox(width: 8),
                  Text('WhatsApp desconectado. Escaneie o QR Code.'),
                ],
              ),
              backgroundColor: Colors.orange,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(Icons.error, color: Colors.white),
                  SizedBox(width: 8),
                  Text('Não foi possível verificar a conexão'),
                ],
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _whatsappConnectionState = null;
          _whatsappTestando = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao conectar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Mostra o QR Code para conectar o WhatsApp
  Future<void> _mostrarQRCodeWhatsApp() async {
    final url = _whatsappApiUrlController.text.trim();
    final apiKey = _whatsappApiKeyController.text.trim();
    final instanceName = _whatsappInstanceNameController.text.trim();

    if (url.isEmpty || apiKey.isEmpty || instanceName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Preencha todos os campos da configuração WhatsApp'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _whatsappTestando = true);

    try {
      final service = WhatsAppService(
        apiUrl: url,
        apiKey: apiKey,
        instanceName: instanceName,
      );

      // Primeiro tenta criar a instância (se não existir)
      final criada = await service.criarInstancia();
      if (!criada) {
        if (mounted) {
          setState(() => _whatsappTestando = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Erro ao preparar instância no servidor. Verifique a URL e API Key.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      // Em seguida verifica se já está conectado
    final state = await service.verificarConexao();
    
    if (state == 'open') {
      if (mounted) {
        setState(() => _whatsappTestando = false);
        
        final disconnect = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('WhatsApp já Conectado'),
            content: const Text('Esta instância já está conectada a um celular. Deseja desconectar para escanear com outro aparelho?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Desconectar e Ver QR Code', style: TextStyle(color: Colors.orange)),
              ),
            ],
          ),
        );

        if (disconnect == true) {
          setState(() => _whatsappTestando = true);
          final ok = await service.desconectar();
          if (!ok) {
            if (mounted) {
              setState(() => _whatsappTestando = false);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Erro ao desconectar. Tente novamente.'), backgroundColor: Colors.red),
              );
            }
            return;
          }
          // Aguarda um pouco para a API atualizar
          await Future.delayed(const Duration(seconds: 2));
        } else {
          return;
        }
      }
    }

      // Obtém o QR Code
      final qrCodeBase64 = await service.obterQRCode();
      
      if (mounted) {
        setState(() => _whatsappTestando = false);
        
        if (qrCodeBase64 != null) {
          _showQRCodeDialog(qrCodeBase64);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Não foi possível obter o QR Code. Verifique as configurações.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _whatsappTestando = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao obter QR Code: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Exibe o dialog com o QR Code
  void _showQRCodeDialog(String qrCodeBase64) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Color(0xFF1E1E2E),
        title: Row(
          children: [
            Icon(Icons.qr_code, color: Colors.green),
            SizedBox(width: 8),
            Text(
              'Conectar WhatsApp',
              style: TextStyle(color: Colors.white),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: qrCodeBase64.startsWith('data:image')
                  ? Image.memory(
                      base64Decode(qrCodeBase64.split(',').last),
                      width: 250,
                      height: 250,
                    )
                  : Image.memory(
                      base64Decode(qrCodeBase64),
                      width: 250,
                      height: 250,
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          width: 250,
                          height: 250,
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.error, color: Colors.red, size: 48),
                                SizedBox(height: 8),
                                Text(
                                  'Erro ao carregar QR Code',
                                  style: TextStyle(color: Colors.red),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
            SizedBox(height: 16),
            Text(
              'Escaneie este QR Code com seu WhatsApp',
              style: TextStyle(color: Colors.white70),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 8),
            Text(
              'Abra o WhatsApp > Menu > Dispositivos conectados > Conectar dispositivo',
              style: TextStyle(color: Colors.white54, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _testarConexaoWhatsApp(); // Testa a conexão após fechar
            },
            child: Text('Verificar Conexão'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Fechar'),
          ),
        ],
      ),
    );
  }

  Widget _buildTipoWhatsAppChip(String value, String label) {
    final isSelected = _whatsappTipo == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _whatsappTipo = value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? Colors.green.withOpacity(0.2) : Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? Colors.green : Colors.white12,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Center(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isSelected ? Colors.green.shade200 : Colors.white54,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                fontSize: 11,
              ),
            ),
          ),
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
    // SEMPRE mostrar o botão (sem condições)
    final isWindows = _isWindows();
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Botão para selecionar do Windows - SEMPRE VISÍVEL
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  debugPrint('>>> [AdicionarEmpresa] Botão clicado! isWindows: $isWindows');
                  if (isWindows) {
                    _selecionarCertificadoWindows();
                  } else {
                    // Mesmo se não detectar Windows, tentar executar
                    debugPrint('>>> [AdicionarEmpresa] Não detectado como Windows, mas tentando mesmo assim...');
                    _selecionarCertificadoWindows();
                  }
                },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isWindows 
                        ? Colors.blue.withOpacity(0.3)
                        : Colors.grey.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isWindows
                          ? Colors.blueAccent.withOpacity(0.8)
                          : Colors.grey.withOpacity(0.3),
                      width: 2,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.security, 
                        color: isWindows ? Colors.blueAccent : Colors.grey,
                        size: 28,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '🔐 Selecionar Certificado do Windows',
                              style: TextStyle(
                                color: isWindows ? Colors.white : Colors.white54,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              isWindows
                                  ? (_certificadoWindowsThumbprint != null
                                      ? '✓ Certificado selecionado do Windows'
                                      : 'Usar certificado instalado no Windows (Recomendado)')
                                  : 'Disponível apenas no Windows',
                              style: TextStyle(
                                color: isWindows ? Colors.white70 : Colors.white54,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.arrow_forward_ios,
                        color: isWindows ? Colors.blueAccent : Colors.grey,
                        size: 16,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          
          // Divisor "OU" - sempre mostrar
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Expanded(child: Divider(color: Colors.white.withOpacity(0.3))),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'OU',
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: 12,
                    ),
                  ),
                ),
                Expanded(child: Divider(color: Colors.white.withOpacity(0.3))),
              ],
            ),
          ),
          
          // Mensagem informativa sobre uso de arquivo
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Colors.green.withOpacity(0.5),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.green.shade300, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '💡 Você pode usar APENAS o arquivo do certificado (PFX/PEM) sem precisar instalá-lo no Windows!',
                    style: TextStyle(
                      color: Colors.green.shade200,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          // Botão para selecionar arquivo - DESTACADO
          InkWell(
            onTap: _selecionarCertificado,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.greenAccent.withOpacity(0.8),
                  width: 2,
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.upload_file, color: Colors.greenAccent, size: 28),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '📁 Importar Certificado Digital (Arquivo)',
                          style: TextStyle(
                            color: Colors.greenAccent,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Aceita: .pfx, .p12, .pem, .crt',
                          style: TextStyle(
                            color: Colors.green.shade200,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _certificadoDigitalNome ?? 'Clique para selecionar arquivo PFX/PEM',
                          style: TextStyle(
                            color: _certificadoDigitalNome != null 
                                ? Colors.green.shade200 
                                : Colors.green.shade300,
                            fontSize: 14,
                            fontWeight: _certificadoDigitalNome != null ? FontWeight.normal : FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (_certificadoDigitalNome != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            '✓ Certificado carregado com sucesso!',
                            style: TextStyle(
                              color: Colors.green.shade300,
                              fontSize: 11,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (_certificadoDigitalNome != null)
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white70),
                      onPressed: () {
                        setState(() {
                          _certificadoDigitalUrl = null;
                          _certificadoDigitalNome = null;
                          _certificadoDigitalBytes = null;
                          _certificadoWindowsThumbprint = null;
                        });
                      },
                      tooltip: 'Remover certificado',
                    ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.arrow_forward_ios,
                    color: Colors.greenAccent,
                    size: 16,
                  ),
                ],
              ),
            ),
          ),
          
          // Instruções adicionais
          if (_certificadoDigitalNome == null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.blue.withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.help_outline, color: Colors.blue.shade300, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          'Como usar:',
                          style: TextStyle(
                            color: Colors.blue.shade200,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '1. Clique no botão acima para selecionar seu arquivo .pfx ou .p12\n'
                      '2. Informe a senha do certificado no campo abaixo\n'
                      '3. O certificado será usado automaticamente na emissão da NFC-e\n'
                      '4. Não é necessário instalar o certificado no Windows!',
                      style: TextStyle(
                        color: Colors.blue.shade200,
                        fontSize: 11,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Verifica se está rodando no Windows (de forma segura)
  bool _isWindows() {
    try {
      if (kIsWeb) return false;
      return Platform.isWindows;
    } catch (e) {
      return false;
    }
  }
  
  /// Seleciona certificado do Windows Certificate Store
  Future<void> _selecionarCertificadoWindows() async {
    try {
      debugPrint('>>> [AdicionarEmpresa] _selecionarCertificadoWindows chamado');
      
      // Sempre tentar executar, mesmo se não detectar Windows
      // O PowerShell vai falhar se não for Windows, mas vamos tentar
      final isWindows = _isWindows();
      debugPrint('>>> [AdicionarEmpresa] isWindows = $isWindows');
      
      if (!isWindows) {
        debugPrint('>>> [AdicionarEmpresa] Aviso: não detectado como Windows, mas tentando mesmo assim...');
        // Não retornar, continuar tentando
      }

      // Mostrar loading
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const Center(
            child: Card(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Carregando certificados do Windows...'),
                  ],
                ),
              ),
            ),
          ),
        );
      }

      try {
        // Listar certificados disponíveis
        debugPrint('>>> [AdicionarEmpresa] Chamando WindowsCertificateService.listarCertificados()...');
        final certificados = await WindowsCertificateService.listarCertificados();
        debugPrint('>>> [AdicionarEmpresa] Certificados recebidos: ${certificados.length}');

        if (mounted) {
          Navigator.pop(context); // Fechar loading
        }

        if (certificados.isEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Nenhum certificado com chave privada encontrado no Windows.\n\n'
                    'Certifique-se de que o certificado está instalado no repositório "Pessoal".\n\n'
                    'Para instalar: Duplo clique no arquivo .pfx e siga o assistente.'),
                backgroundColor: Colors.orange,
                duration: Duration(seconds: 8),
              ),
            );
          }
          return;
        }
        
        debugPrint('>>> [AdicionarEmpresa] ${certificados.length} certificado(s) encontrado(s), mostrando diálogo...');

        // Mostrar diálogo de seleção
        if (mounted) {
          final certificadoSelecionado = await showDialog<Map<String, dynamic>>(
            context: context,
            builder: (context) => AlertDialog(
              backgroundColor: const Color(0xFF1E1E2E),
              title: const Text(
                'Selecionar Certificado do Windows',
                style: TextStyle(color: Colors.white),
              ),
              content: SizedBox(
                width: MediaQuery.of(context).size.width * 0.8,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: certificados.length,
                  itemBuilder: (context, index) {
                    final cert = certificados[index];
                    final subject = cert['subject'] as String;
                    final issuer = cert['issuer'] as String;
                    final notAfter = cert['notAfter'] as String;
                    
                    // Extrair CNPJ do subject se houver
                    final cnpjMatch = RegExp(r'\d{14}').firstMatch(subject);
                    final cnpj = cnpjMatch?.group(0);
                    
                    return Card(
                      color: Colors.white.withOpacity(0.1),
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        title: Text(
                          cnpj != null ? 'CNPJ: $cnpj' : subject,
                          style: const TextStyle(color: Colors.white),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Emitido por: $issuer',
                              style: TextStyle(color: Colors.white70, fontSize: 12),
                            ),
                            if (notAfter.isNotEmpty)
                              Text(
                                'Válido até: $notAfter',
                                style: TextStyle(color: Colors.white60, fontSize: 11),
                              ),
                          ],
                        ),
                        onTap: () {
                          Navigator.pop(context, cert);
                        },
                      ),
                    );
                  },
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('CANCELAR', style: TextStyle(color: Colors.white70)),
                ),
              ],
            ),
          );

          if (certificadoSelecionado != null) {
            // Solicitar senha do certificado
            final senha = await _solicitarSenhaCertificado();
            if (senha == null) return;

            // Mostrar loading para exportar
            if (mounted) {
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (context) => const Center(
                  child: Card(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 16),
                          Text('Exportando certificado do Windows...'),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }

            try {
              // Exportar certificado
              final thumbprint = certificadoSelecionado['thumbprint'] as String;
              final resultado = await WindowsCertificateService.exportarCertificado(
                thumbprint,
                senha,
              );

              if (mounted) {
                Navigator.pop(context); // Fechar loading
              }

              // Salvar informações
              final subject = certificadoSelecionado['subject'] as String;
              final cnpjMatch = RegExp(r'\d{14}').firstMatch(subject);
              final nomeExibicao = cnpjMatch != null 
                  ? 'CNPJ: ${cnpjMatch.group(0)}'
                  : subject.length > 50 
                      ? '${subject.substring(0, 50)}...'
                      : subject;
              
              String? certificadoBase64;
              if (resultado['tipo'] == 'pem') {
                // Salvar conteúdo PEM
                final pemContent = resultado['conteudo']!;
                certificadoBase64 = base64Encode(utf8.encode(pemContent));
              } else {
                // Se for PFX, ler arquivo e converter para base64
                final arquivoPFX = File(resultado['caminho']!);
                if (await arquivoPFX.exists()) {
                  final bytes = await arquivoPFX.readAsBytes();
                  certificadoBase64 = base64Encode(bytes);
                }
              }
              
              // Validar certificado via backend Python se disponível
              String? cnpj;
              DateTime? validade;
              bool usadoBackend = false;
              
              if (certificadoBase64 != null) {
                try {
                  debugPrint('>>> [Certificado] Validando certificado do Windows via backend Python...');
                  final backendService = CertificadoBackendService();
                  final backendDisponivel = await backendService.verificarDisponibilidade();
                  
                  if (backendDisponivel) {
                    final resultadoValidacao = await backendService.validarCertificado(
                      certificadoBase64: certificadoBase64,
                      senha: senha,
                    );
                    
                    if (resultadoValidacao['success'] == true) {
                      usadoBackend = true;
                      cnpj = resultadoValidacao['cnpj'] as String?;
                      if (resultadoValidacao['validade'] != null) {
                        validade = DateTime.parse(resultadoValidacao['validade'] as String);
                      }
                      debugPrint('>>> [Certificado] ✓✓✓ Certificado do Windows validado via backend Python!');
                    }
                  }
                } catch (e) {
                  debugPrint('>>> [Certificado] ⚠️ Erro ao validar via backend: $e');
                }
              }
              
              setState(() {
                _certificadoWindowsThumbprint = thumbprint;
                _certificadoDigitalNome = nomeExibicao;
                
                if (resultado['tipo'] == 'pem') {
                  _certificadoDigitalBytes = certificadoBase64;
                  _certificadoDigitalUrl = 'windows:pem:$subject';
                } else {
                  _certificadoDigitalBytes = certificadoBase64;
                  _certificadoDigitalUrl = resultado['caminho']!;
                }
              });

              if (mounted) {
                String mensagem = '✓ Certificado do Windows selecionado\n';
                if (usadoBackend) {
                  mensagem += '(Validado via backend Python)\n';
                }
                mensagem += '\n${certificadoSelecionado['subject']}';
                if (cnpj != null) {
                  mensagem += '\nCNPJ: $cnpj';
                }
                if (validade != null) {
                  final diasRestantes = validade.difference(DateTime.now()).inDays;
                  mensagem += '\nValidade: ${validade.day}/${validade.month}/${validade.year}';
                  if (diasRestantes > 0) {
                    mensagem += ' ($diasRestantes dias restantes)';
                  } else {
                    mensagem += ' (EXPIRADO)';
                  }
                }
                
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(mensagem),
                    backgroundColor: Colors.green,
                    duration: const Duration(seconds: 5),
                  ),
                );
              }
            } catch (e) {
              if (mounted) {
                Navigator.pop(context); // Fechar loading
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Erro ao exportar certificado: $e'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            }
          }
        }
      } catch (e) {
        if (mounted) {
          Navigator.pop(context); // Fechar loading
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Erro ao listar certificados: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao selecionar certificado do Windows: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Seleciona o arquivo do certificado digital
  /// Aceita apenas PEM/CRT (recomendado) ou tenta converter PFX automaticamente
  Future<void> _selecionarCertificado() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pem', 'crt', 'pfx', 'p12'], // PEM primeiro (recomendado)
        withData: true,
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.single;
        
        if (file.bytes == null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('⚠️ Erro ao ler o arquivo do certificado'),
                backgroundColor: Colors.orange,
              ),
            );
          }
          return;
        }

        // Mostrar diálogo de processamento
        if (mounted) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => const Center(
              child: Card(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('Processando certificado...'),
                    ],
                  ),
                ),
              ),
            ),
          );
        }

        try {
          // Verificar se é arquivo PEM (já convertido)
          final extensao = file.name.toLowerCase();
          final isPEM = extensao.endsWith('.pem') || extensao.endsWith('.crt');
          
          if (isPEM) {
            // Arquivo PEM - usar diretamente
            await _processarCertificadoPEM(file);
          } else {
            // Arquivo PFX - tentar converter automaticamente ou mostrar instruções
            await _processarCertificadoPFX(file);
          }
        } finally {
          // Fechar diálogo de processamento
          if (mounted) {
            Navigator.pop(context);
          }
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Fechar diálogo se ainda estiver aberto
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao selecionar certificado: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  /// Processa certificado PFX - versão simplificada que SEMPRE salva
  Future<void> _processarCertificadoPFX(PlatformFile file) async {
    try {
      debugPrint('>>> [AdicionarEmpresa] ========================================');
      debugPrint('>>> [AdicionarEmpresa] PROCESSANDO CERTIFICADO PFX');
      debugPrint('>>> [AdicionarEmpresa] ========================================');
      debugPrint('>>> [AdicionarEmpresa] Nome do arquivo: ${file.name}');
      debugPrint('>>> [AdicionarEmpresa] Tamanho: ${file.size} bytes');
      
      // PASSO 1: Ler bytes do arquivo
      Uint8List? bytes;
      if (file.bytes != null) {
        bytes = file.bytes;
        debugPrint('>>> [AdicionarEmpresa] ✅ Bytes do arquivo carregados: ${bytes!.length} bytes');
      } else if (file.path != null && !kIsWeb) {
        try {
        final arquivo = File(file.path!);
        if (await arquivo.exists()) {
          bytes = await arquivo.readAsBytes();
            debugPrint('>>> [AdicionarEmpresa] ✅ Bytes lidos do arquivo: ${bytes.length} bytes');
          } else {
            debugPrint('>>> [AdicionarEmpresa] ⚠️ Arquivo não existe no caminho: ${file.path}');
          }
        } catch (e) {
          debugPrint('>>> [AdicionarEmpresa] ⚠️ Erro ao ler arquivo: $e');
        }
      }
      
      if (bytes == null || bytes.isEmpty) {
        throw Exception('Não foi possível ler o arquivo PFX. Verifique se o arquivo está acessível.');
      }
      
      // PASSO 2: Converter para base64
      final base64Bytes = base64Encode(bytes);
      debugPrint('>>> [AdicionarEmpresa] ✅ Certificado convertido para base64: ${base64Bytes.length} caracteres');
      debugPrint('>>> [AdicionarEmpresa] Primeiros 50 chars: ${base64Bytes.substring(0, base64Bytes.length > 50 ? 50 : base64Bytes.length)}...');
      
      // PASSO 3: SALVAR IMEDIATAMENTE (sem validação - validação será feita na emissão)
      setState(() {
        _certificadoDigitalNome = file.name;
        _certificadoDigitalUrl = 'base64:pfx:${file.name}'; // Prefixo para identificar PFX em base64
        _certificadoDigitalBytes = base64Bytes; // SEMPRE salvar em base64
      });
      debugPrint('>>> [AdicionarEmpresa] ✅✅✅ CERTIFICADO SALVO COM SUCESSO!');
      debugPrint('>>> [AdicionarEmpresa] Nome: $_certificadoDigitalNome');
      debugPrint('>>> [AdicionarEmpresa] URL: $_certificadoDigitalUrl');
      debugPrint('>>> [AdicionarEmpresa] Base64: ${_certificadoDigitalBytes?.length ?? 0} caracteres');
      
      // PASSO 4: Tentar validar (opcional - não bloqueia o salvamento)
      try {
        // Solicitar senha se não tiver
        String? senha = _senhaCertificadoController.text.trim();
        if (senha.isEmpty) {
          senha = await _solicitarSenhaCertificado();
          if (senha != null && senha.isNotEmpty) {
            _senhaCertificadoController.text = senha;
          }
        }
        
        // Tentar validar apenas se tiver senha
        if (senha != null && senha.isNotEmpty) {
          debugPrint('>>> [AdicionarEmpresa] Tentando validar certificado (opcional)...');
          
          try {
            final backendService = CertificadoBackendService();
            final backendDisponivel = await backendService.verificarDisponibilidade();
            
            if (backendDisponivel) {
              final resultado = await backendService.validarCertificado(
                certificadoBase64: base64Bytes,
                senha: senha,
              );
              
              if (resultado['success'] == true) {
                final cnpj = resultado['cnpj'] as String?;
                final validade = resultado['validade'] != null 
                    ? DateTime.parse(resultado['validade'] as String) 
                    : null;
                final diasRestantes = resultado['dias_restantes'] as int? ?? 0;
                final valido = resultado['valido'] as bool? ?? false;
                
                if (mounted) {
                  String mensagem = '✓ Certificado PFX carregado com sucesso!\n\n';
                  if (cnpj != null) {
                    mensagem += 'CNPJ: $cnpj\n';
                  }
                  if (validade != null) {
                    mensagem += 'Validade: ${validade.day}/${validade.month}/${validade.year}';
                    if (diasRestantes > 0) {
                      mensagem += ' ($diasRestantes dias restantes)';
          } else {
                      mensagem += ' (EXPIRADO)';
                    }
                  }
                  
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(mensagem),
                      backgroundColor: valido ? Colors.green : Colors.orange,
                      duration: const Duration(seconds: 5),
                    ),
                  );
                }
                return; // Sucesso na validação
              }
            }
          } catch (eValidacao) {
            debugPrint('>>> [AdicionarEmpresa] ⚠️ Validação falhou (não bloqueia salvamento): $eValidacao');
          }
        }
        
        // Se chegou aqui, certificado foi salvo mas validação não foi feita ou falhou
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✓ Certificado PFX carregado!\n\nO certificado foi salvo. A validação será feita na emissão da NFC-e.'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 4),
            ),
          );
        }
      } catch (e) {
        debugPrint('>>> [AdicionarEmpresa] ⚠️ Erro na validação (não bloqueia salvamento): $e');
        // Mesmo com erro na validação, certificado já foi salvo
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✓ Certificado PFX carregado!\n\nO certificado foi salvo. A validação será feita na emissão da NFC-e.'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 4),
            ),
          );
        }
      }
      } catch (e) {
      debugPrint('>>> [AdicionarEmpresa] ❌ Erro crítico ao processar certificado PFX: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao processar certificado: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  /// Processa certificado PEM (já convertido)
  Future<void> _processarCertificadoPEM(PlatformFile file) async {
    try {
      // SEMPRE salvar em base64 para garantir que será carregado depois
      final pemBase64 = base64Encode(file.bytes!);
      debugPrint('>>> [AdicionarEmpresa] Certificado PEM salvo em base64: ${pemBase64.length} caracteres');
      
      // Solicitar senha se não tiver (PEM pode ter senha)
          String? senha = _senhaCertificadoController.text.trim();
          if (senha.isEmpty) {
            senha = await _solicitarSenhaCertificado();
            if (senha == null || senha.isEmpty) {
          // PEM pode não ter senha, continuar mesmo assim
          senha = '';
        } else {
            _senhaCertificadoController.text = senha;
        }
          }
          
          // TENTAR 1: Validar usando backend Python (PyNFe)
          String? cnpj;
          DateTime? validade;
          bool usadoBackend = false;
          
          try {
        debugPrint('>>> [Certificado] Tentando validar PEM via backend Python...');
            final backendService = CertificadoBackendService();
            final backendDisponivel = await backendService.verificarDisponibilidade();
            
            if (backendDisponivel) {
          debugPrint('>>> [Certificado] Backend disponível, validando PEM...');
              final resultado = await backendService.validarCertificado(
            certificadoBase64: pemBase64,
                senha: senha,
              );
              
              if (resultado['success'] == true) {
                usadoBackend = true;
                cnpj = resultado['cnpj'] as String?;
                if (resultado['validade'] != null) {
                  validade = DateTime.parse(resultado['validade'] as String);
                }
                
                final diasRestantes = resultado['dias_restantes'] as int? ?? 0;
                final valido = resultado['valido'] as bool? ?? false;
                
            debugPrint('>>> [Certificado] ✓✓✓ Certificado PEM validado via backend Python!');
                
                // Atualizar estado com certificado validado
                setState(() {
                  _certificadoDigitalNome = file.name;
              _certificadoDigitalUrl = 'base64:pem:${file.name}';
              _certificadoDigitalBytes = pemBase64;
                });
                
                // Mostrar sucesso com informações do certificado
                if (mounted) {
              String mensagem = '✓ Certificado PEM processado e validado com sucesso!\n';
                  mensagem += '(Validado via backend Python)\n\n';
                  if (cnpj != null) {
                    mensagem += 'CNPJ: $cnpj\n';
                  }
                  if (validade != null) {
                    mensagem += 'Validade: ${validade.day}/${validade.month}/${validade.year}';
                    if (diasRestantes > 0) {
                      mensagem += ' ($diasRestantes dias restantes)';
                    } else {
                      mensagem += ' (EXPIRADO)';
                    }
                  }
                  mensagem += '\n\nCertificado armazenado em memória (base64)';
                  
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(mensagem),
                      backgroundColor: valido ? Colors.green : Colors.orange,
                      duration: const Duration(seconds: 5),
                    ),
                  );
                }
                
            debugPrint('>>> [Certificado] Certificado PEM processado e validado com sucesso via backend');
            return; // Certificado processado
              } else {
                debugPrint('>>> [Certificado] ⚠️ Backend retornou erro: ${resultado['error']}');
              }
            } else {
              debugPrint('>>> [Certificado] Backend não disponível, usando serviço local...');
            }
          } catch (eBackend) {
            debugPrint('>>> [Certificado] ⚠️ Erro ao validar via backend: $eBackend');
            debugPrint('>>> [Certificado] Usando fallback para serviço local...');
          }
          
          // TENTAR 2: Validar usando serviço local (fallback)
          if (!usadoBackend) {
        debugPrint('>>> [Certificado] Validando PEM usando serviço local (fallback)...');
        try {
          Directory tempDir;
          try {
            tempDir = await getTemporaryDirectory();
          } catch (e) {
            if (_isWindows()) {
              final tempPath = Platform.environment['TEMP'] ?? Platform.environment['TMP'] ?? '.';
              tempDir = Directory(tempPath);
            } else {
              tempDir = Directory('/tmp');
            }
            if (!await tempDir.exists()) {
              await tempDir.create(recursive: true);
            }
          }
          
          final tempPemFile = File('${tempDir.path}/certificado_pem_${DateTime.now().millisecondsSinceEpoch}.pem');
          final pemDecodificado = utf8.decode(base64Decode(pemBase64));
          await tempPemFile.writeAsString(pemDecodificado);
          
          final certificadoService = CertificadoService();
            final certificado = await certificadoService.carregarCertificado(
            tempPemFile.path,
              senha,
            );
            
            cnpj = certificado.cnpj;
            validade = certificado.validade;
            
          debugPrint('>>> [Certificado] ✓✓✓ Certificado PEM validado via serviço local!');
        } catch (e) {
          debugPrint('>>> [Certificado] ⚠️ Erro ao validar via serviço local: $e');
          // Continuar mesmo com erro, apenas armazenar
        }
          }
          
          // Atualizar estado com certificado validado
          setState(() {
            _certificadoDigitalNome = file.name;
        _certificadoDigitalUrl = 'base64:pem:${file.name}';
        _certificadoDigitalBytes = pemBase64;
          });
          
          // Mostrar sucesso com informações do certificado
          if (mounted) {
        String mensagem = '✓ Certificado PEM processado com sucesso!\n';
            if (!usadoBackend) {
              mensagem += '(Validado via serviço local)\n';
            }
            mensagem += '\n';
            if (cnpj != null) {
              mensagem += 'CNPJ: $cnpj\n';
            }
            if (validade != null) {
              final diasRestantes = validade.difference(DateTime.now()).inDays;
              mensagem += 'Validade: ${validade.day}/${validade.month}/${validade.year}';
              if (diasRestantes > 0) {
                mensagem += ' (${diasRestantes} dias restantes)';
              } else {
                mensagem += ' (EXPIRADO)';
              }
            }
            mensagem += '\n\nCertificado armazenado em memória (base64)';
            
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(mensagem),
                backgroundColor: Colors.green,
                duration: const Duration(seconds: 5),
              ),
            );
          }
          
      debugPrint('>>> [Certificado] Certificado PEM processado com sucesso');
        } catch (e) {
      debugPrint('>>> [Certificado] ERRO ao processar PEM: $e');
      rethrow;
    }
  }

  /// Solicita senha do certificado ao usuário
  Future<String?> _solicitarSenhaCertificado() async {
    String? senha;
    
    if (!mounted) return null;
    
    await showDialog(
            context: context,
      barrierDismissible: false,
      builder: (context) {
        final controller = TextEditingController();
        return AlertDialog(
          title: const Text('Senha do Certificado'),
          content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
              const Text('Digite a senha do certificado para conversão automática:'),
                    const SizedBox(height: 16),
              TextField(
                controller: controller,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Senha',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (value) {
                  senha = value;
                  Navigator.pop(context);
                },
              ),
            ],
              ),
              actions: [
                TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
                  onPressed: () {
                senha = controller.text;
                    Navigator.pop(context);
              },
              child: const Text('OK'),
            ),
          ],
        );
      },
    );

    return senha;
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

  Future<void> _desconectarWhatsApp() async {
    final url = _whatsappApiUrlController.text.trim();
    final apiKey = _whatsappApiKeyController.text.trim();
    final instanceName = _whatsappInstanceNameController.text.trim();

    setState(() => _whatsappTestando = true);

    try {
      final service = WhatsAppService(
        apiUrl: url,
        apiKey: apiKey,
        instanceName: instanceName,
      );

      final sucesso = await service.desconectar();
      
      if (mounted) {
        setState(() {
          _whatsappTestando = false;
          if (sucesso) _whatsappConnectionState = 'close';
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(sucesso ? 'WhatsApp desconectado!' : 'Erro ao desconectar.'),
            backgroundColor: sucesso ? Colors.orange : Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _whatsappTestando = false);
    }
  }

  Future<void> _deletarInstanciaWhatsApp() async {
    final url = _whatsappApiUrlController.text.trim();
    final apiKey = _whatsappApiKeyController.text.trim();
    final instanceName = _whatsappInstanceNameController.text.trim();

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Limpar Instância?'),
        content: const Text('Isso removerá completamente a instância do servidor. Você precisará criar uma nova para conectar.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(context, true), 
            child: const Text('Limpar', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmar != true) return;

    setState(() => _whatsappTestando = true);

    try {
      final service = WhatsAppService(
        apiUrl: url,
        apiKey: apiKey,
        instanceName: instanceName,
      );

      final sucesso = await service.deletarInstancia();
      
      if (mounted) {
        setState(() {
          _whatsappTestando = false;
          if (sucesso) _whatsappConnectionState = null;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(sucesso ? 'Instância removida!' : 'Erro ao remover instância.'),
            backgroundColor: sucesso ? Colors.blue : Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _whatsappTestando = false);
    }
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
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
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
                  const SizedBox(height: 20),
                  // Botão para cor customizada
                  OutlinedButton.icon(
                    onPressed: () {
                      _mostrarColorPickerCustomizado(context, corSelecionada, (cor) {
                        setState(() {
                          corSelecionada = cor;
                        });
                      });
                    },
                    icon: const Icon(Icons.colorize, size: 18),
                    label: const Text('Cor Personalizada'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white54),
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Grid de cores com scroll
                  SizedBox(
                    height: 300,
                    child: GridView.builder(
                      shrinkWrap: true,
                      physics: const AlwaysScrollableScrollPhysics(),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 6,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                      ),
                      itemCount: _coresDisponiveis.length,
                      itemBuilder: (context, index) {
                        final cor = _coresDisponiveis[index];
                        final isSelecionada = cor == corSelecionada;
                        return GestureDetector(
                          onTap: () {
                            setState(() {
                              corSelecionada = cor;
                            });
                          },
                          child: Container(
                            decoration: BoxDecoration(
                              color: cor,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isSelecionada
                                    ? Colors.white
                                    : Colors.white.withOpacity(0.3),
                                width: isSelecionada ? 3 : 1,
                              ),
                            ),
                            child: isSelecionada
                                ? const Icon(Icons.check, color: Colors.white, size: 20)
                                : null,
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              onPressed: () {
                onColorChanged(corSelecionada);
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
              child: const Text('Confirmar'),
            ),
          ],
        ),
      ),
    );
  }

  /// Mostra seletor de cor customizado (RGB)
  void _mostrarColorPickerCustomizado(
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
            'Cor Personalizada',
            style: TextStyle(color: Colors.white),
          ),
          content: SizedBox(
            width: 300,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                // Preview da cor
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
                      _colorToHex(corSelecionada),
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
                const SizedBox(height: 20),
                // Sliders RGB
                _buildColorSlider(
                  'Vermelho (R)',
                  corSelecionada.red.toDouble(),
                  255,
                  Colors.red,
                  (value) {
                    setState(() {
                      corSelecionada = Color.fromRGBO(
                        value.round(),
                        corSelecionada.green,
                        corSelecionada.blue,
                        1.0,
                      );
                    });
                  },
                ),
                const SizedBox(height: 12),
                _buildColorSlider(
                  'Verde (G)',
                  corSelecionada.green.toDouble(),
                  255,
                  Colors.green,
                  (value) {
                    setState(() {
                      corSelecionada = Color.fromRGBO(
                        corSelecionada.red,
                        value.round(),
                        corSelecionada.blue,
                        1.0,
                      );
                    });
                  },
                ),
                const SizedBox(height: 12),
                _buildColorSlider(
                  'Azul (B)',
                  corSelecionada.blue.toDouble(),
                  255,
                  Colors.blue,
                  (value) {
                    setState(() {
                      corSelecionada = Color.fromRGBO(
                        corSelecionada.red,
                        corSelecionada.green,
                        value.round(),
                        1.0,
                      );
                    });
                  },
                ),
              ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              onPressed: () {
                onColorChanged(corSelecionada);
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
              child: const Text('Confirmar'),
            ),
          ],
        ),
      ),
    );
  }

  /// Widget para slider de cor
  Widget _buildColorSlider(
    String label,
    double value,
    double max,
    Color color,
    ValueChanged<double> onChanged,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
            Text(
              value.round().toString(),
              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 4),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: color,
            inactiveTrackColor: color.withOpacity(0.3),
            thumbColor: color,
            overlayColor: color.withOpacity(0.2),
          ),
          child: Slider(
            value: value,
            min: 0,
            max: max,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  /// Widget para exibir categoria de telas
  Widget _buildCategoriaTelas(String categoria, List<TelaSistema> telas) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _getIconPorCategoria(categoria),
                color: Colors.purple.shade300,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                categoria,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.purple.shade200,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: telas.map((tela) {
              final isSelecionada = _telasPermitidas.contains(tela.codigo);
              return FilterChip(
                label: Text(tela.nome),
                selected: isSelecionada,
                onSelected: (selected) {
                  setState(() {
                    if (selected) {
                      _telasPermitidas.add(tela.codigo);
                    } else {
                      _telasPermitidas.remove(tela.codigo);
                    }
                  });
                },
                selectedColor: Colors.purple.shade700,
                checkmarkColor: Colors.white,
                labelStyle: TextStyle(
                  color: isSelecionada ? Colors.white : Colors.white70,
                  fontSize: 12,
                ),
                backgroundColor: Colors.white.withOpacity(0.1),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  /// Retorna ícone por categoria
  IconData _getIconPorCategoria(String categoria) {
    switch (categoria) {
      case 'Vendas':
        return Icons.point_of_sale;
      case 'Cadastros':
        return Icons.apps;
      case 'Estoque':
        return Icons.inventory;
      case 'Financeiro':
        return Icons.account_balance_wallet;
      case 'Relatórios':
        return Icons.assessment;
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

  /// Confirma e deleta todos os dados operacionais da empresa (produtos, pedidos, vendas e serviços)
  Future<void> _confirmarDeletarTodosDados(BuildContext context) async {
    if (widget.empresa == null) return;

    final dataService = Provider.of<DataService>(context, listen: false);
    final authService = Provider.of<AuthService>(context, listen: false);
    
    // Garantir que a empresa está selecionada antes de contar
    await authService.selecionarEmpresa(widget.empresa!);
    await dataService.definirEmpresaAtual(widget.empresa!.id);
    
    // Contar dados da empresa atual
    final totalProdutos = dataService.produtos.length;
    final totalPedidos = dataService.pedidos.length;
    final totalVendas = dataService.vendasBalcao.length;
    final totalServicos = dataService.tiposServico.length;
    final totalClientes = dataService.clientes.length;
    final totalAgendamentos = dataService.agendamentosServico.length;
    final totalOrdens = dataService.ordensServico.length;
    final totalEntregas = dataService.entregas.length;
    final totalFuncionarios = dataService.funcionarios.length;
    final totalTaxas = dataService.taxasEntrega.length;
    final totalContas = dataService.contasPagar.length;
    final totalNotas = dataService.notasEntrada.length;
    final totalNfces = dataService.nfces.length;
    final totalMesas = dataService.mesasComandas.length;
    final totalGeral = totalProdutos + totalPedidos + totalVendas + totalServicos + 
                      totalClientes + totalAgendamentos + totalOrdens + totalEntregas +
                      totalFuncionarios + totalTaxas + totalContas + totalNotas + 
                      totalNfces + totalMesas;

    if (totalGeral == 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Não há dados para deletar'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Row(
          children: [
            const Icon(Icons.warning, color: Colors.red, size: 28),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Excluir Todos os Dados',
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
              'Tem certeza que deseja excluir TODOS os dados operacionais desta empresa?',
              style: const TextStyle(color: Colors.white70, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.withOpacity(0.5)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Serão deletados TODOS os dados operacionais:',
                    style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  if (totalProdutos > 0)
                    Text('  • $totalProdutos produto(s)', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                  if (totalPedidos > 0)
                    Text('  • $totalPedidos pedido(s)', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                  if (totalVendas > 0)
                    Text('  • $totalVendas venda(s)', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                  if (totalServicos > 0)
                    Text('  • $totalServicos serviço(s)', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                  if (totalClientes > 0)
                    Text('  • $totalClientes cliente(s)', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                  if (totalAgendamentos > 0)
                    Text('  • $totalAgendamentos agendamento(s)', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                  if (totalOrdens > 0)
                    Text('  • $totalOrdens ordem(ns) de serviço', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                  if (totalEntregas > 0)
                    Text('  • $totalEntregas entrega(s)', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                  if (totalFuncionarios > 0)
                    Text('  • $totalFuncionarios funcionário(s)', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                  if (totalTaxas > 0)
                    Text('  • $totalTaxas taxa(s) de entrega', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                  if (totalContas > 0)
                    Text('  • $totalContas conta(s) a pagar', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                  if (totalNotas > 0)
                    Text('  • $totalNotas nota(s) de entrada', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                  if (totalNfces > 0)
                    Text('  • $totalNfces NFC-e(s)', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                  if (totalMesas > 0)
                    Text('  • $totalMesas mesa(s)/comanda(s)', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                  if (totalGeral > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'Total: $totalGeral item(ns)',
                        style: const TextStyle(color: Colors.orange, fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                    ),
                ],
              ),
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
        setState(() => _isLoading = true);
        
        // Garantir que a empresa está selecionada
        final authService = Provider.of<AuthService>(context, listen: false);
        await authService.selecionarEmpresa(widget.empresa!);
        await dataService.definirEmpresaAtual(widget.empresa!.id);
        
        // Deletar todos os dados operacionais
        await dataService.deletarTodosDadosOperacionais(confirmar: true);
        
        // Recarregar os dados para garantir que a interface seja atualizada
        await dataService.recarregarDados();
        
        if (mounted) {
          final mensagem = StringBuffer('✅ Todos os dados foram excluídos com sucesso!\n\n');
          if (totalProdutos > 0) mensagem.writeln('• $totalProdutos produto(s)');
          if (totalPedidos > 0) mensagem.writeln('• $totalPedidos pedido(s)');
          if (totalVendas > 0) mensagem.writeln('• $totalVendas venda(s)');
          if (totalServicos > 0) mensagem.writeln('• $totalServicos serviço(s)');
          if (totalClientes > 0) mensagem.writeln('• $totalClientes cliente(s)');
          if (totalAgendamentos > 0) mensagem.writeln('• $totalAgendamentos agendamento(s)');
          if (totalOrdens > 0) mensagem.writeln('• $totalOrdens ordem(ns) de serviço');
          if (totalEntregas > 0) mensagem.writeln('• $totalEntregas entrega(s)');
          if (totalFuncionarios > 0) mensagem.writeln('• $totalFuncionarios funcionário(s)');
          if (totalTaxas > 0) mensagem.writeln('• $totalTaxas taxa(s) de entrega');
          if (totalContas > 0) mensagem.writeln('• $totalContas conta(s) a pagar');
          if (totalNotas > 0) mensagem.writeln('• $totalNotas nota(s) de entrada');
          if (totalNfces > 0) mensagem.writeln('• $totalNfces NFC-e(s)');
          if (totalMesas > 0) mensagem.writeln('• $totalMesas mesa(s)/comanda(s)');
          mensagem.writeln('\n✅ A empresa está pronta para começar do zero!');
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(mensagem.toString()),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 5),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('❌ Erro ao excluir dados: $e'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 5),
            ),
          );
        }
      } finally {
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    }
  }

  // Lista de cores disponíveis
  final List<Color> _coresDisponiveis = [
    // Azuis modernos
    Colors.blue,
    Colors.blueAccent,
    Colors.lightBlue,
    Colors.lightBlueAccent,
    Colors.cyan,
    Colors.cyanAccent,
    const Color(0xFF2196F3), // Material Blue
    const Color(0xFF03A9F4), // Light Blue
    const Color(0xFF00BCD4), // Cyan
    const Color(0xFF0097A7), // Cyan Dark
    // Verdes modernos
    Colors.green,
    Colors.greenAccent,
    Colors.lightGreen,
    Colors.lightGreenAccent,
    Colors.teal,
    Colors.tealAccent,
    const Color(0xFF4CAF50), // Material Green
    const Color(0xFF8BC34A), // Light Green
    const Color(0xFF00BCD4), // Teal
    // Roxos/Violetas modernos
    Colors.purple,
    Colors.purpleAccent,
    Colors.deepPurple,
    Colors.deepPurpleAccent,
    const Color(0xFF9C27B0), // Material Purple
    const Color(0xFF673AB7), // Deep Purple
    const Color(0xFF3F51B5), // Indigo
    // Laranjas/Vermelhos modernos
    Colors.orange,
    Colors.deepOrange,
    Colors.orangeAccent,
    Colors.red,
    Colors.redAccent,
    const Color(0xFFFF5722), // Deep Orange
    const Color(0xFFE91E63), // Pink
    const Color(0xFFF44336), // Material Red
    // Amarelos/Dourados modernos
    Colors.amber,
    Colors.amberAccent,
    Colors.yellow,
    Colors.yellowAccent,
    const Color(0xFFFFC107), // Amber
    const Color(0xFFFF9800), // Orange
    // Neutros modernos
    Colors.grey,
    Colors.blueGrey,
    Colors.brown,
    const Color(0xFF607D8B), // Blue Grey
    const Color(0xFF795548), // Brown
    const Color(0xFF424242), // Grey Dark
    const Color(0xFF212121), // Black
    // Cores especiais modernas
    const Color(0xFF00E676), // Green Accent
    const Color(0xFF00E5FF), // Cyan Accent
    const Color(0xFF651FFF), // Deep Purple Accent
    const Color(0xFF3D5AFE), // Indigo Accent
    const Color(0xFF1DE9B6), // Teal Accent
    const Color(0xFFFF6D00), // Orange Accent
  ];
}




