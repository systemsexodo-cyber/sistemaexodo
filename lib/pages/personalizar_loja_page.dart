import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import '../services/auth_service.dart';
import '../services/image_storage_service.dart';
import '../models/zona_entrega.dart';
import '../models/opcao_frete.dart';
import 'dart:io';
import '../theme.dart';
import 'package:intl/intl.dart';
import '../models/empresa.dart';
import 'package:flutter/services.dart';
import '../widgets/sync_status_widget.dart';
// Import condicional para Web
import 'html_helper_stub.dart' if (dart.library.html) 'html_helper_web.dart' as html_helper;

class PersonalizarLojaPage extends StatefulWidget {
  const PersonalizarLojaPage({super.key});

  @override
  State<PersonalizarLojaPage> createState() => _PersonalizarLojaPageState();
}

class _PersonalizarLojaPageState extends State<PersonalizarLojaPage> with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  late TabController _tabController;
  
  // Controllers
  final _textoPromocional1Controller = TextEditingController();
  final _textoPromocional2Controller = TextEditingController();
  final _textoPromocional3Controller = TextEditingController();
  final _whatsappController = TextEditingController();
  final _textoBannerController = TextEditingController();
  final _linkBannerController = TextEditingController();
  final _emailContatoController = TextEditingController();
  final _facebookController = TextEditingController();
  final _instagramController = TextEditingController();
  final _horarioFuncionamentoController = TextEditingController();
  final _enderecoLojaController = TextEditingController();
  final _termosUsoController = TextEditingController();
  final _politicaPrivacidadeController = TextEditingController();
  final _politicaTrocaController = TextEditingController();
  final _mensagemBoasVindasController = TextEditingController();
  final _mensagemFinalizacaoController = TextEditingController();
  final _valorFreteGratisController = TextEditingController();
  final _percentualDescontoPixController = TextEditingController();
  
  // Estado
  String? _logoUrl;
  String? _bannerUrl;
  bool _uploadingLogo = false;
  bool _uploadingBanner = false;
  
  // Banners promocionais (imagens)
  String? _bannerPromocional1Url;
  String? _bannerPromocional2Url;
  String? _bannerPromocional3Url;
  bool _uploadingBannerPromocional1 = false;
  bool _uploadingBannerPromocional2 = false;
  bool _uploadingBannerPromocional3 = false;
  bool _bannerAtivo = true;
  DateTime? _bannerDataInicio;
  DateTime? _bannerDataFim;
  String? _corBanner;
  String? _corTextoBanner;
  String? _corFundoLoja;
  String? _corPrimariaLoja;
  String? _corSecundariaLoja;
  bool _descontoPixAtivo = true;
  double _percentualDescontoPix = 5.0;
  double _valorFreteGratis = 399.90;
  String _tamanhoLogo = 'medio'; // pequeno, medio, grande
  String _posicaoLogo = 'esquerda'; // esquerda, centro, direita
  String _estiloCards = 'padrao'; // padrao, moderno, minimalista
  bool _exibirRedesSociais = true;
  bool _exibirHorarioFuncionamento = true;
  bool _exibirEnderecoLoja = true;
  String _modoExibicao = 'ecommerce'; // ecommerce, delivery
  
  // Configurações do banner de frete grátis
  bool _bannerFreteGratisAtivo = true;
  String _textoBannerFreteGratis = 'Frete Grátis acima de R\$ {valor}';
  String _posicaoBannerFreteGratis = 'topo'; // topo, meio, rodape
  
  // Configurações de frete
  bool _habilitarCorreios = true;
  bool _habilitarJadlog = true;
  bool _habilitarTotalExpress = true;
  bool _habilitarAzulCargo = true;
  bool _habilitarLoggi = true;
  bool _habilitarEntregasRapidas = true;
  bool _habilitarEntregaMesmoBairro = true;
  double _taxaEntregaMesmoBairro = 5.0;
  final _taxaEntregaMesmoBairroController = TextEditingController();
  
  // Credenciais para APIs reais (opcional)
  final _jadlogTokenController = TextEditingController();
  final _totalExpressTokenController = TextEditingController();
  final _azulCargoTokenController = TextEditingController();
  final _loggiTokenController = TextEditingController();
  final _correiosCodigoController = TextEditingController();
  final _correiosSenhaController = TextEditingController();
  final _melhorEnvioTokenController = TextEditingController();
  final _melhorEnvioEmailController = TextEditingController();
  final _slugController = TextEditingController();
  final _novoBairroTaxiDogController = TextEditingController();
  
  // Opções de Frete Fixas Personalizadas
  List<OpcaoFrete> _opcoesFreteFixas = [];
  List<ZonaEntrega> _zonasEntrega = [];
  List<String> _bairrosTaxiDog = [];
  bool _habilitarEstimativaDistancia = true;
  
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 8, vsync: this);
    _carregarConfiguracoes();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _textoPromocional1Controller.dispose();
    _textoPromocional2Controller.dispose();
    _textoPromocional3Controller.dispose();
    _whatsappController.dispose();
    _textoBannerController.dispose();
    _linkBannerController.dispose();
    _emailContatoController.dispose();
    _facebookController.dispose();
    _instagramController.dispose();
    _horarioFuncionamentoController.dispose();
    _enderecoLojaController.dispose();
    _termosUsoController.dispose();
    _politicaPrivacidadeController.dispose();
    _politicaTrocaController.dispose();
    _mensagemBoasVindasController.dispose();
    _mensagemFinalizacaoController.dispose();
      _valorFreteGratisController.dispose();
      _percentualDescontoPixController.dispose();
      _taxaEntregaMesmoBairroController.dispose();
      _jadlogTokenController.dispose();
      _totalExpressTokenController.dispose();
      _azulCargoTokenController.dispose();
      _loggiTokenController.dispose();
      _correiosCodigoController.dispose();
      _correiosSenhaController.dispose();
      _melhorEnvioTokenController.dispose();
      _melhorEnvioEmailController.dispose();
      _slugController.dispose();
      _novoBairroTaxiDogController.dispose();
      super.dispose();
  }

  void _carregarConfiguracoes() {
    final authService = Provider.of<AuthService>(context, listen: false);
    final empresa = authService.empresaAtual;
    
    if (empresa == null) return;
    
    final config = empresa.configuracoes ?? {};
    final ecommerceConfig = config['ecommerce'] as Map<String, dynamic>? ?? {};
    
    setState(() {
      _logoUrl = ecommerceConfig['logoUrl'] as String? ?? empresa.logoUrl;
      _bannerUrl = ecommerceConfig['bannerUrl'] as String?;
      _textoPromocional1Controller.text = ecommerceConfig['textoPromocional1'] as String? ?? '';
      _textoPromocional2Controller.text = ecommerceConfig['textoPromocional2'] as String? ?? '';
      _textoPromocional3Controller.text = ecommerceConfig['textoPromocional3'] as String? ?? '';
      _whatsappController.text = ecommerceConfig['whatsapp'] as String? ?? empresa.celular ?? '';
      _textoBannerController.text = ecommerceConfig['textoBanner'] as String? ?? '';
      _linkBannerController.text = ecommerceConfig['linkBanner'] as String? ?? '';
      _bannerAtivo = ecommerceConfig['bannerAtivo'] as bool? ?? true;
      _corBanner = ecommerceConfig['corBanner'] as String? ?? '#2E7D32';
      _corTextoBanner = ecommerceConfig['corTextoBanner'] as String? ?? '#FFFFFF';
      _corFundoLoja = ecommerceConfig['corFundoLoja'] as String? ?? empresa.corPrimaria ?? '#10151B';
      _corPrimariaLoja = ecommerceConfig['corPrimariaLoja'] as String? ?? empresa.corPrimaria ?? '#2196F3';
      _corSecundariaLoja = ecommerceConfig['corSecundariaLoja'] as String? ?? empresa.corSecundaria ?? '#1565C0';
      
      if (ecommerceConfig['bannerDataInicio'] != null) {
        _bannerDataInicio = DateTime.parse(ecommerceConfig['bannerDataInicio']);
      }
      if (ecommerceConfig['bannerDataFim'] != null) {
        _bannerDataFim = DateTime.parse(ecommerceConfig['bannerDataFim']);
      }
      _descontoPixAtivo = ecommerceConfig['descontoPixAtivo'] as bool? ?? true;
      _percentualDescontoPix = (ecommerceConfig['percentualDescontoPix'] as num?)?.toDouble() ?? 5.0;
      _valorFreteGratis = (ecommerceConfig['valorFreteGratis'] as num?)?.toDouble() ?? 399.90;
      _valorFreteGratisController.text = _valorFreteGratis.toStringAsFixed(2);
      _bannerFreteGratisAtivo = ecommerceConfig['bannerFreteGratisAtivo'] as bool? ?? true;
      _textoBannerFreteGratis = ecommerceConfig['textoBannerFreteGratis'] as String? ?? 'Frete Grátis acima de R\$ {valor}';
      _posicaoBannerFreteGratis = ecommerceConfig['posicaoBannerFreteGratis'] as String? ?? 'topo';
      
      // Configurações de frete
      final freteConfig = ecommerceConfig['frete'] as Map<String, dynamic>? ?? {};
      _habilitarCorreios = freteConfig['habilitarCorreios'] as bool? ?? true;
      _habilitarJadlog = freteConfig['habilitarJadlog'] as bool? ?? true;
      _habilitarTotalExpress = freteConfig['habilitarTotalExpress'] as bool? ?? true;
      _habilitarAzulCargo = freteConfig['habilitarAzulCargo'] as bool? ?? true;
      _habilitarLoggi = freteConfig['habilitarLoggi'] as bool? ?? true;
      _habilitarEntregasRapidas = freteConfig['habilitarEntregasRapidas'] as bool? ?? true;
      _habilitarEntregaMesmoBairro = freteConfig['habilitarEntregaMesmoBairro'] as bool? ?? true;
      _taxaEntregaMesmoBairro = (freteConfig['taxaEntregaMesmoBairro'] as num?)?.toDouble() ?? 5.0;
      _taxaEntregaMesmoBairroController.text = _taxaEntregaMesmoBairro.toStringAsFixed(2);
      
      // Credenciais para APIs reais (opcional)
      _jadlogTokenController.text = freteConfig['jadlogToken'] as String? ?? '';
      _totalExpressTokenController.text = freteConfig['totalExpressToken'] as String? ?? '';
      _azulCargoTokenController.text = freteConfig['azulCargoToken'] as String? ?? '';
      _loggiTokenController.text = freteConfig['loggiToken'] as String? ?? '';
      _correiosCodigoController.text = freteConfig['correiosCodigo'] as String? ?? '';
      _correiosSenhaController.text = freteConfig['correiosSenha'] as String? ?? '';
      _melhorEnvioTokenController.text = freteConfig['melhorEnvioToken'] as String? ?? '';
      _melhorEnvioEmailController.text = freteConfig['melhorEnvioEmail'] as String? ?? '';
      
      // Carregar Zonas de Entrega Inteligentes
      final zonasData = freteConfig['zonasEntrega'] as List<dynamic>? ?? [];
      _zonasEntrega = zonasData
          .map((z) => ZonaEntrega.fromMap(z as Map<String, dynamic>))
          .toList();

      // Carregar Opções de Frete Fixas
      final opcoesFixasData = freteConfig['opcoesFreteFixas'] as List<dynamic>? ?? [];
      _opcoesFreteFixas = opcoesFixasData
          .map((o) => OpcaoFrete.fromMap(o as Map<String, dynamic>))
          .toList();
      
      _habilitarEstimativaDistancia = freteConfig['habilitarEstimativaDistancia'] as bool? ?? true;
      
      _tamanhoLogo = ecommerceConfig['tamanhoLogo'] as String? ?? 'medio';
      _posicaoLogo = ecommerceConfig['posicaoLogo'] as String? ?? 'esquerda';
      _estiloCards = ecommerceConfig['estiloCards'] as String? ?? 'padrao';
      _exibirRedesSociais = ecommerceConfig['exibirRedesSociais'] as bool? ?? true;
      _slugController.text = empresa.slug;
      _exibirHorarioFuncionamento = ecommerceConfig['exibirHorarioFuncionamento'] as bool? ?? true;
      _exibirEnderecoLoja = ecommerceConfig['exibirEnderecoLoja'] as bool? ?? true;
      _modoExibicao = ecommerceConfig['modoExibicao'] as String? ?? 'ecommerce';
      
      _emailContatoController.text = ecommerceConfig['emailContato'] as String? ?? empresa.email ?? '';
      _facebookController.text = ecommerceConfig['facebook'] as String? ?? '';
      _instagramController.text = ecommerceConfig['instagram'] as String? ?? '';
      _horarioFuncionamentoController.text = ecommerceConfig['horarioFuncionamento'] as String? ?? 'Segunda a Sexta: 8h às 18h';
      _enderecoLojaController.text = ecommerceConfig['enderecoLoja'] as String? ?? '';
      _termosUsoController.text = ecommerceConfig['termosUso'] as String? ?? '';
      _politicaPrivacidadeController.text = ecommerceConfig['politicaPrivacidade'] as String? ?? '';
      _politicaTrocaController.text = ecommerceConfig['politicaTroca'] as String? ?? '';
      _mensagemBoasVindasController.text = ecommerceConfig['mensagemBoasVindas'] as String? ?? 'Bem-vindo à nossa loja!';
      _mensagemFinalizacaoController.text = ecommerceConfig['mensagemFinalizacao'] as String? ?? 'Obrigado pela sua compra!';
      
      _valorFreteGratisController.text = _valorFreteGratis.toStringAsFixed(2);
      _percentualDescontoPixController.text = _percentualDescontoPix.toStringAsFixed(0);

      // Carregar configurações de agendamento (incluindo bairros Taxi Dog)
      final agendamentoConfig = config['agendamento'] as Map<String, dynamic>? ?? {};
      final bairrosData = agendamentoConfig['bairrosTaxiDog'] as List<dynamic>? ?? [];
      _bairrosTaxiDog = bairrosData.map((e) => e.toString()).toList();
    });
  }

  Future<void> _uploadLogo() async {
    try {
      setState(() => _uploadingLogo = true);
      
      FilePickerResult? result;
      if (kIsWeb) {
        result = await FilePicker.platform.pickFiles(
          type: FileType.image,
          allowMultiple: false,
          withData: true,
        );
      } else {
        result = await FilePicker.platform.pickFiles(
          type: FileType.image,
          allowMultiple: false,
        );
      }
      
      if (result == null || result.files.isEmpty) {
        setState(() => _uploadingLogo = false);
        return;
      }
      
      final authService = Provider.of<AuthService>(context, listen: false);
      final empresa = authService.empresaAtual;
      if (empresa == null) {
        setState(() => _uploadingLogo = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Erro: Empresa não encontrada'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
      
      final file = result.files.first;
      String? url;
      
      if (kIsWeb) {
        if (file.bytes == null || file.bytes!.isEmpty) {
          setState(() => _uploadingLogo = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Erro: Não foi possível ler o arquivo. Tente novamente.'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }
        
        // Usar armazenamento GRATUITO no Firestore
        url = await ImageStorageService.salvarImagemERetornarUrl(
          imageBytes: file.bytes!,
          empresaId: empresa.id,
          categoria: 'logos',
          nome: 'Logo ${empresa.nomeExibicao}',
          metadata: {
            'tipo': 'logo',
            'empresa_id': empresa.id,
          },
        );
      } else {
        if (file.path == null || file.path!.isEmpty) {
          setState(() => _uploadingLogo = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Erro: Caminho do arquivo não encontrado'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }
        
        // Mobile: ler arquivo e usar armazenamento GRATUITO
        try {
          final fileData = await File(file.path!).readAsBytes();
          url = await ImageStorageService.salvarImagemERetornarUrl(
            imageBytes: fileData,
            empresaId: empresa.id,
            categoria: 'logos',
            nome: 'Logo ${empresa.nomeExibicao}',
            metadata: {
              'tipo': 'logo',
              'empresa_id': empresa.id,
            },
          );
        } catch (e) {
          setState(() => _uploadingLogo = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Erro ao ler arquivo: $e'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }
      }
      
      if (url != null && url.isNotEmpty) {
        setState(() {
          _logoUrl = url;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Logo enviada com sucesso!'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Erro: Upload retornou vazio. Tente novamente.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e, stackTrace) {
      debugPrint('>>> Erro ao enviar logo: $e');
      debugPrint('>>> StackTrace: $stackTrace');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao enviar logo: ${e.toString()}'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    } finally {
      setState(() => _uploadingLogo = false);
    }
  }

  Future<void> _uploadBanner() async {
    try {
      setState(() => _uploadingBanner = true);
      
      FilePickerResult? result;
      if (kIsWeb) {
        result = await FilePicker.platform.pickFiles(
          type: FileType.image,
          allowMultiple: false,
          withData: true,
        );
      } else {
        result = await FilePicker.platform.pickFiles(
          type: FileType.image,
          allowMultiple: false,
        );
      }
      
      if (result == null || result.files.isEmpty) {
        setState(() => _uploadingBanner = false);
        return;
      }
      
      final authService = Provider.of<AuthService>(context, listen: false);
      final empresa = authService.empresaAtual;
      if (empresa == null) {
        setState(() => _uploadingBanner = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Erro: Empresa não encontrada'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
      
      final file = result.files.first;
      String? url;
      
      if (kIsWeb) {
        if (file.bytes == null || file.bytes!.isEmpty) {
          setState(() => _uploadingBanner = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Erro: Não foi possível ler o arquivo. Tente novamente.'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }
        
        // Usar armazenamento GRATUITO no Firestore
        url = await ImageStorageService.salvarImagemERetornarUrl(
          imageBytes: file.bytes!,
          empresaId: empresa.id,
          categoria: 'banners',
          nome: 'Banner ${empresa.nomeExibicao}',
          metadata: {
            'tipo': 'banner',
            'empresa_id': empresa.id,
          },
        );
      } else {
        if (file.path == null || file.path!.isEmpty) {
          setState(() => _uploadingBanner = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Erro: Caminho do arquivo não encontrado'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }
        
        // Mobile: ler arquivo e usar armazenamento GRATUITO
        try {
          final fileData = await File(file.path!).readAsBytes();
          url = await ImageStorageService.salvarImagemERetornarUrl(
            imageBytes: fileData,
            empresaId: empresa.id,
            categoria: 'banners',
            nome: 'Banner ${empresa.nomeExibicao}',
            metadata: {
              'tipo': 'banner',
              'empresa_id': empresa.id,
            },
          );
        } catch (e) {
          setState(() => _uploadingBanner = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Erro ao ler arquivo: $e'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }
      }
      
      if (url != null && url.isNotEmpty) {
        setState(() {
          _bannerUrl = url;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Banner enviado com sucesso!'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Erro: Upload retornou vazio. Tente novamente.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e, stackTrace) {
      debugPrint('>>> Erro ao enviar banner: $e');
      debugPrint('>>> StackTrace: $stackTrace');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao enviar banner: ${e.toString()}'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    } finally {
      setState(() => _uploadingBanner = false);
    }
  }

  Color _hexToColor(String? hex) {
    if (hex == null || hex.isEmpty) return Colors.green;
    try {
      return Color(int.parse(hex.replaceFirst('#', ''), radix: 16) + 0xFF000000);
    } catch (e) {
      return Colors.green;
    }
  }

  String _colorToHex(Color color) {
    return '#${color.value.toRadixString(16).substring(2, 8).toUpperCase()}';
  }

  Future<void> _salvar() async {
    if (!_formKey.currentState!.validate()) return;
    
    setState(() => _isLoading = true);
    
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final empresa = authService.empresaAtual;
      if (empresa == null) return;
      
      // Validar e converter valores numéricos
      final valorFreteGratis = double.tryParse(_valorFreteGratisController.text.replaceAll(',', '.')) ?? 399.90;
      final percentualDescontoPix = double.tryParse(_percentualDescontoPixController.text.replaceAll(',', '.')) ?? 5.0;
      
      // Criar uma cópia profunda das configurações existentes
      final config = Map<String, dynamic>.from(empresa.configuracoes ?? {});
      
      // Criar uma cópia profunda da seção ecommerce se existir
      final ecommerceExistente = config['ecommerce'] != null
          ? Map<String, dynamic>.from(config['ecommerce'] as Map)
          : <String, dynamic>{};
      
      // Atualizar apenas os campos de ecommerce
      ecommerceExistente['logoUrl'] = _logoUrl;
      ecommerceExistente['bannerUrl'] = _bannerUrl;
      // Salvar banners promocionais (imagens)
      ecommerceExistente['bannerPromocional1Url'] = _bannerPromocional1Url;
      ecommerceExistente['bannerPromocional2Url'] = _bannerPromocional2Url;
      ecommerceExistente['bannerPromocional3Url'] = _bannerPromocional3Url;
      // Manter textos para compatibilidade
      ecommerceExistente['textoPromocional1'] = _textoPromocional1Controller.text.trim();
      ecommerceExistente['textoPromocional2'] = _textoPromocional2Controller.text.trim();
      ecommerceExistente['textoPromocional3'] = _textoPromocional3Controller.text.trim();
      ecommerceExistente['whatsapp'] = _whatsappController.text.trim();
      ecommerceExistente['textoBanner'] = _textoBannerController.text.trim();
      ecommerceExistente['linkBanner'] = _linkBannerController.text.trim();
      ecommerceExistente['bannerAtivo'] = _bannerAtivo;
      ecommerceExistente['corBanner'] = _corBanner ?? '#2E7D32';
      ecommerceExistente['corTextoBanner'] = _corTextoBanner ?? '#FFFFFF';
      ecommerceExistente['corFundoLoja'] = _corFundoLoja;
      ecommerceExistente['corPrimariaLoja'] = _corPrimariaLoja;
      ecommerceExistente['corSecundariaLoja'] = _corSecundariaLoja;
      ecommerceExistente['bannerDataInicio'] = _bannerDataInicio?.toIso8601String();
      ecommerceExistente['bannerDataFim'] = _bannerDataFim?.toIso8601String();
      ecommerceExistente['descontoPixAtivo'] = _descontoPixAtivo;
      ecommerceExistente['percentualDescontoPix'] = percentualDescontoPix;
      ecommerceExistente['valorFreteGratis'] = valorFreteGratis;
      ecommerceExistente['bannerFreteGratisAtivo'] = _bannerFreteGratisAtivo;
      ecommerceExistente['textoBannerFreteGratis'] = _textoBannerFreteGratis.trim();
      ecommerceExistente['posicaoBannerFreteGratis'] = _posicaoBannerFreteGratis;
      
      // Configurações de frete
      final taxaEntregaMesmoBairro = double.tryParse(_taxaEntregaMesmoBairroController.text.replaceAll(',', '.')) ?? 5.0;
      ecommerceExistente['frete'] = {
        'habilitarCorreios': _habilitarCorreios,
        'habilitarJadlog': _habilitarJadlog,
        'habilitarTotalExpress': _habilitarTotalExpress,
        'habilitarAzulCargo': _habilitarAzulCargo,
        'habilitarLoggi': _habilitarLoggi,
        'habilitarEntregasRapidas': _habilitarEntregasRapidas,
        'habilitarEntregaMesmoBairro': _habilitarEntregaMesmoBairro,
        'taxaEntregaMesmoBairro': taxaEntregaMesmoBairro,
        // Zonas de Entrega Inteligentes
        'zonasEntrega': _zonasEntrega.map((z) => z.toMap()).toList(),
        // Opções de Frete Fixas
        'opcoesFreteFixas': _opcoesFreteFixas.map((o) => o.toMap()).toList(),
        'habilitarEstimativaDistancia': _habilitarEstimativaDistancia,
        // Credenciais para APIs reais (opcional - apenas se preenchidas)
        if (_jadlogTokenController.text.trim().isNotEmpty)
          'jadlogToken': _jadlogTokenController.text.trim(),
        if (_totalExpressTokenController.text.trim().isNotEmpty)
          'totalExpressToken': _totalExpressTokenController.text.trim(),
        if (_azulCargoTokenController.text.trim().isNotEmpty)
          'azulCargoToken': _azulCargoTokenController.text.trim(),
        if (_loggiTokenController.text.trim().isNotEmpty)
          'loggiToken': _loggiTokenController.text.trim(),
        if (_correiosCodigoController.text.trim().isNotEmpty)
          'correiosCodigo': _correiosCodigoController.text.trim(),
        if (_correiosSenhaController.text.trim().isNotEmpty)
          'correiosSenha': _correiosSenhaController.text.trim(),
        if (_melhorEnvioTokenController.text.trim().isNotEmpty)
          'melhorEnvioToken': _melhorEnvioTokenController.text.trim(),
        if (_melhorEnvioEmailController.text.trim().isNotEmpty)
          'melhorEnvioEmail': _melhorEnvioEmailController.text.trim(),
      };
      ecommerceExistente['tamanhoLogo'] = _tamanhoLogo;
      ecommerceExistente['posicaoLogo'] = _posicaoLogo;
      ecommerceExistente['estiloCards'] = _estiloCards;
      ecommerceExistente['exibirRedesSociais'] = _exibirRedesSociais;
      ecommerceExistente['exibirHorarioFuncionamento'] = _exibirHorarioFuncionamento;
      ecommerceExistente['exibirEnderecoLoja'] = _exibirEnderecoLoja;
      ecommerceExistente['modoExibicao'] = _modoExibicao;
      ecommerceExistente['emailContato'] = _emailContatoController.text.trim();
      ecommerceExistente['facebook'] = _facebookController.text.trim();
      ecommerceExistente['instagram'] = _instagramController.text.trim();
      ecommerceExistente['horarioFuncionamento'] = _horarioFuncionamentoController.text.trim();
      ecommerceExistente['enderecoLoja'] = _enderecoLojaController.text.trim();
      ecommerceExistente['termosUso'] = _termosUsoController.text.trim();
      ecommerceExistente['politicaPrivacidade'] = _politicaPrivacidadeController.text.trim();
      ecommerceExistente['politicaTroca'] = _politicaTrocaController.text.trim();
      ecommerceExistente['mensagemBoasVindas'] = _mensagemBoasVindasController.text.trim();
      ecommerceExistente['mensagemFinalizacao'] = _mensagemFinalizacaoController.text.trim();
      
      // Atualizar a seção ecommerce no config
      config['ecommerce'] = ecommerceExistente;

      // Configurações de agendamento
      final agendamentoExistente = config['agendamento'] != null
          ? Map<String, dynamic>.from(config['agendamento'] as Map)
          : <String, dynamic>{};
      agendamentoExistente['bairrosTaxiDog'] = _bairrosTaxiDog;
      config['agendamento'] = agendamentoExistente;
      
      debugPrint('>>> [PersonalizarLoja] Salvando configurações completas');
      
      final empresaAtualizada = empresa.copyWith(
        configuracoes: config,
        updatedAt: DateTime.now(),
        slug: _slugController.text.trim().isNotEmpty 
          ? Empresa.gerarSlug(_slugController.text) 
          : Empresa.gerarSlug(empresa.nomeExibicao),
      );
      
      await authService.atualizarEmpresa(empresaAtualizada);
      
      // Aguardar um pouco para garantir que a atualização foi processada
      await Future.delayed(const Duration(milliseconds: 500));
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Personalização salva com sucesso!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
        Navigator.of(context).pop(true);
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

  Future<void> _selecionarDataBanner(bool isInicio) async {
    final data = await showDatePicker(
      context: context,
      initialDate: isInicio 
          ? (_bannerDataInicio ?? DateTime.now())
          : (_bannerDataFim ?? DateTime.now().add(const Duration(days: 30))),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    
    if (data != null) {
      setState(() {
        if (isInicio) {
          _bannerDataInicio = data;
        } else {
          _bannerDataFim = data;
        }
      });
    }
  }

  Widget _buildSeletorCor(String titulo, String? corAtual, Function(String) onCorSelecionada) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          titulo,
          style: TextStyle(color: Colors.white70, fontSize: 14),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: () async {
            final color = await showDialog<Color>(
              context: context,
              builder: (context) => AlertDialog(
                backgroundColor: Colors.grey[900],
                title: Text('Selecionar Cor', style: TextStyle(color: Colors.white)),
                content: SingleChildScrollView(
                  child: BlockPicker(
                    pickerColor: _hexToColor(corAtual),
                    onColorChanged: (color) {
                      Navigator.pop(context, color);
                    },
                  ),
                ),
              ),
            );
            if (color != null) {
              onCorSelecionada(_colorToHex(color));
            }
          },
          child: Container(
            height: 50,
            decoration: BoxDecoration(
              color: _hexToColor(corAtual),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white30, width: 2),
            ),
            child: Center(
              child: Text(
                corAtual ?? '#000000',
                style: TextStyle(
                  color: _hexToColor(corAtual).computeLuminance() > 0.5 ? Colors.black : Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppTheme.appBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Personalizar Loja'),
          backgroundColor: Colors.transparent,
          elevation: 0,
          actions: [
            const SyncStatusWidget(),
          ],
          bottom: TabBar(
            controller: _tabController,
            isScrollable: true,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.green,
            tabs: const [
              Tab(icon: Icon(Icons.image), text: 'Visual'),
              Tab(icon: Icon(Icons.campaign), text: 'Banner'),
              Tab(icon: Icon(Icons.payment), text: 'Pagamento'),
              Tab(icon: Icon(Icons.local_shipping), text: 'Frete'),
              Tab(icon: Icon(Icons.info), text: 'Informações'),
              Tab(icon: Icon(Icons.gavel), text: 'Legal'),
              Tab(icon: Icon(Icons.settings), text: 'Layout'),
            ],
          ),
        ),
        body: Form(
          key: _formKey,
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildAbaVisual(),
              _buildAbaBanner(),
              _buildAbaPagamento(),
              _buildAbaFrete(),
              _buildAbaInformacoes(),
              _buildAbaLegal(),
              _buildAbaLayout(),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _isLoading ? null : _salvar,
          backgroundColor: Colors.green,
          icon: _isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.save),
          label: Text(_isLoading ? 'Salvando...' : 'Salvar Tudo'),
        ),
      ),
    );
  }

  Widget _buildAbaVisual() {
    final empresa = Provider.of<AuthService>(context).empresaAtual;
    if (empresa == null) return const SizedBox.shrink();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // LINKS DA EMPRESA (URL AMIGÁVEL)
          Card(
            color: Colors.blue[900]?.withOpacity(0.3),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.blue[400]!, width: 1),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.link, color: Colors.blue[200]),
                      const SizedBox(width: 8),
                      Text(
                        'Links de Acesso Público',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blue[100]),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Estes são os endereços que seus clientes usarão para acessar seus serviços.',
                    style: TextStyle(color: Colors.blue[100]?.withOpacity(0.7), fontSize: 13),
                  ),
                  const SizedBox(height: 20),
                  
                  // CONFIGURAÇÃO DO SLUG
                  Text(
                    'Nome identificador (Slug):',
                    style: TextStyle(color: Colors.blue[100], fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue[200]!.withOpacity(0.3)),
                    ),
                    child: TextField(
                      controller: _slugController,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      decoration: const InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        hintText: 'nome-da-sua-empresa',
                        hintStyle: TextStyle(color: Colors.white24),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // LINK DIRETO (MAIS FÁCIL)
                  _buildLinkItem(
                    'Link da sua Loja (E-commerce)',
                    '${html_helper.getWindowHost()}/loja/${Empresa.gerarSlug(_slugController.text.isNotEmpty ? _slugController.text : empresa.nomeExibicao)}',
                    '${html_helper.getWindowOrigin()}/loja/${Empresa.gerarSlug(_slugController.text.isNotEmpty ? _slugController.text : empresa.nomeExibicao)}',
                  ),
                  
                  const SizedBox(height: 12),
                  
                  // LINK DE AGENDAMENTO
                  _buildLinkItem(
                    'Link de Agendamento Online',
                    '${html_helper.getWindowHost()}/agendamento/${Empresa.gerarSlug(_slugController.text.isNotEmpty ? _slugController.text : empresa.nomeExibicao)}',
                    '${html_helper.getWindowOrigin()}/agendamento/${Empresa.gerarSlug(_slugController.text.isNotEmpty ? _slugController.text : empresa.nomeExibicao)}',
                  ),

                ],
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Logo
          Card(
            color: Colors.white.withOpacity(0.1),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.image, color: Colors.white),
                      const SizedBox(width: 8),
                      const Text(
                        'Logo da Loja',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (_logoUrl != null && _logoUrl!.isNotEmpty)
                    Container(
                      height: 150,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white30),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          _logoUrl!,
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) {
                            return const Center(child: Icon(Icons.error, color: Colors.red));
                          },
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _uploadingLogo ? null : _uploadLogo,
                    icon: _uploadingLogo
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.upload),
                    label: Text(_uploadingLogo ? 'Enviando...' : 'Enviar Logo'),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Cores da Loja
          Card(
            color: Colors.white.withOpacity(0.1),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.palette, color: Colors.white),
                      const SizedBox(width: 8),
                      const Text(
                        'Cores da Loja',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildSeletorCor('Cor de Fundo', _corFundoLoja, (cor) {
                    setState(() => _corFundoLoja = cor);
                  }),
                  const SizedBox(height: 16),
                  _buildSeletorCor('Cor Primária', _corPrimariaLoja, (cor) {
                    setState(() => _corPrimariaLoja = cor);
                  }),
                  const SizedBox(height: 16),
                  _buildSeletorCor('Cor Secundária', _corSecundariaLoja, (cor) {
                    setState(() => _corSecundariaLoja = cor);
                  }),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Card informativo sobre tamanhos de banners promocionais
          Card(
            color: Colors.blue.withOpacity(0.2),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.blue[300], size: 24),
                      const SizedBox(width: 8),
                      const Text(
                        'Tamanhos Recomendados para Banners Promocionais',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildInfoTamanhoBannerPromocional(
                    'Desktop (Recomendado)',
                    '1920 x 400 pixels',
                    'Proporção: 4.8:1',
                    Icons.desktop_windows,
                  ),
                  const SizedBox(height: 12),
                  _buildInfoTamanhoBannerPromocional(
                    'Mobile (Alternativo)',
                    '800 x 300 pixels',
                    'Proporção: 2.67:1',
                    Icons.phone_android,
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.green.withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.auto_fix_high, color: Colors.green[300], size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'O sistema ajustará automaticamente o tamanho e melhorará a qualidade da imagem ao fazer o upload.',
                            style: TextStyle(color: Colors.white, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Textos Promocionais
          Card(
            color: Colors.white.withOpacity(0.1),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.campaign, color: Colors.white),
                      const SizedBox(width: 8),
                      const Text(
                        'Banners Promocionais',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Estes banners aparecerão no carrossel junto com o banner principal',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(height: 16),
                  
                  // Banner Promocional 1
                  _buildUploadBannerPromocional(
                    'Banner Promocional 1',
                    _bannerPromocional1Url,
                    _uploadingBannerPromocional1,
                    (url) => setState(() => _bannerPromocional1Url = url),
                    () => setState(() => _uploadingBannerPromocional1 = true),
                    () => setState(() => _uploadingBannerPromocional1 = false),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Banner Promocional 2
                  _buildUploadBannerPromocional(
                    'Banner Promocional 2',
                    _bannerPromocional2Url,
                    _uploadingBannerPromocional2,
                    (url) => setState(() => _bannerPromocional2Url = url),
                    () => setState(() => _uploadingBannerPromocional2 = true),
                    () => setState(() => _uploadingBannerPromocional2 = false),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Banner Promocional 3
                  _buildUploadBannerPromocional(
                    'Banner Promocional 3',
                    _bannerPromocional3Url,
                    _uploadingBannerPromocional3,
                    (url) => setState(() => _bannerPromocional3Url = url),
                    () => setState(() => _uploadingBannerPromocional3 = true),
                    () => setState(() => _uploadingBannerPromocional3 = false),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLinkItem(String label, String displayUrl, String fullUrl) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.2),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.blue[200]!.withOpacity(0.1)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  displayUrl,
                  style: TextStyle(color: Colors.blue[200], fontSize: 13, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Tooltip(
                message: 'Copiar Link',
                child: IconButton(
                  icon: const Icon(Icons.copy, size: 18, color: Colors.white70),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: fullUrl));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('$label copiado!')),
                    );
                  },
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAbaBanner() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Card informativo sobre tamanhos
          Card(
            color: Colors.blue.withOpacity(0.2),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.blue[300], size: 24),
                      const SizedBox(width: 8),
                      const Text(
                        'Tamanhos Recomendados de Banner',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildInfoTamanho(
                    'Banner Principal (Desktop)',
                    '1920 x 400 pixels',
                    'Proporção: 4.8:1',
                    Icons.desktop_windows,
                  ),
                  const SizedBox(height: 12),
                  _buildInfoTamanho(
                    'Banner Principal (Mobile)',
                    '800 x 300 pixels',
                    'Proporção: 2.67:1',
                    Icons.phone_android,
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue.withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.auto_fix_high, color: Colors.blue[300], size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'O sistema ajusta automaticamente a imagem para o tamanho ideal!',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.white.withOpacity(0.9),
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Card de upload e preview
          Card(
            color: Colors.white.withOpacity(0.1),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.photo_library, color: Colors.white),
                      const SizedBox(width: 8),
                      const Text(
                        'Banner Principal',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  // Preview do banner
                  if (_bannerUrl != null && _bannerUrl!.isNotEmpty) ...[
                    Container(
                      width: double.infinity,
                      constraints: const BoxConstraints(maxHeight: 300),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white30, width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Stack(
                          children: [
                            Image.network(
                              _bannerUrl!,
                              fit: BoxFit.cover,
                              width: double.infinity,
                              loadingBuilder: (context, child, loadingProgress) {
                                if (loadingProgress == null) return child;
                                return Container(
                                  height: 200,
                                  color: Colors.grey.shade800,
                                  child: Center(
                                    child: CircularProgressIndicator(
                                      value: loadingProgress.expectedTotalBytes != null
                                          ? loadingProgress.cumulativeBytesLoaded /
                                              loadingProgress.expectedTotalBytes!
                                          : null,
                                    ),
                                  ),
                                );
                              },
                              errorBuilder: (context, error, stackTrace) {
                                return Container(
                                  height: 200,
                                  color: Colors.grey.shade800,
                                  child: const Center(
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.error, color: Colors.red, size: 48),
                                        SizedBox(height: 8),
                                        Text(
                                          'Erro ao carregar imagem',
                                          style: TextStyle(color: Colors.white70),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                            // Overlay com informações
                            Positioned(
                              bottom: 0,
                              left: 0,
                              right: 0,
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Colors.transparent,
                                      Colors.black.withOpacity(0.8),
                                    ],
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.check_circle, color: Colors.green[300], size: 20),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Banner carregado com sucesso!',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                                      onPressed: () {
                                        setState(() {
                                          _bannerUrl = null;
                                        });
                                      },
                                      tooltip: 'Remover banner',
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ] else ...[
                    Container(
                      width: double.infinity,
                      height: 200,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade800,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white30, width: 2, style: BorderStyle.solid),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.image_outlined, size: 64, color: Colors.white.withOpacity(0.5)),
                          const SizedBox(height: 12),
                          Text(
                            'Nenhum banner enviado',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.7),
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Envie uma imagem para visualizar o preview',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.5),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                  // Botão de upload melhorado
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton.icon(
                      onPressed: _uploadingBanner ? null : _uploadBanner,
                      icon: _uploadingBanner
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.cloud_upload, size: 24),
                      label: Text(
                        _uploadingBanner ? 'Enviando Banner...' : (_bannerUrl != null ? 'Trocar Banner' : 'Enviar Banner'),
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        elevation: 4,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Configurações do banner
                  const Divider(color: Colors.white24),
                  const SizedBox(height: 16),
                  const Text(
                    'Configurações do Banner',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildTextField(_textoBannerController, 'Texto do Banner (opcional)'),
                  const SizedBox(height: 16),
                  _buildTextField(_linkBannerController, 'Link do Banner (opcional)', hint: 'https://...'),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _buildSeletorCor('Cor de Fundo', _corBanner, (cor) {
                          setState(() => _corBanner = cor);
                        }),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _buildSeletorCor('Cor do Texto', _corTextoBanner, (cor) {
                          setState(() => _corTextoBanner = cor);
                        }),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: ListTile(
                          title: const Text('Data Início', style: TextStyle(color: Colors.white70)),
                          subtitle: Text(
                            _bannerDataInicio != null
                                ? DateFormat('dd/MM/yyyy').format(_bannerDataInicio!)
                                : 'Não definida',
                            style: const TextStyle(color: Colors.white),
                          ),
                          trailing: const Icon(Icons.calendar_today, color: Colors.white70),
                          onTap: () => _selecionarDataBanner(true),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          tileColor: Colors.white.withOpacity(0.05),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ListTile(
                          title: const Text('Data Fim', style: TextStyle(color: Colors.white70)),
                          subtitle: Text(
                            _bannerDataFim != null
                                ? DateFormat('dd/MM/yyyy').format(_bannerDataFim!)
                                : 'Não definida',
                            style: const TextStyle(color: Colors.white),
                          ),
                          trailing: const Icon(Icons.calendar_today, color: Colors.white70),
                          onTap: () => _selecionarDataBanner(false),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          tileColor: Colors.white.withOpacity(0.05),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    title: const Text('Banner Ativo', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                    subtitle: const Text('Exibir banner na loja', style: TextStyle(color: Colors.white70)),
                    value: _bannerAtivo,
                    onChanged: (value) => setState(() => _bannerAtivo = value),
                    activeColor: Colors.green,
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoTamanho(String titulo, String tamanho, String proporcao, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.blue[300], size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  tamanho,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white.withOpacity(0.8),
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  proporcao,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withOpacity(0.6),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAbaPagamento() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            color: Colors.white.withOpacity(0.1),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.percent, color: Colors.white),
                      const SizedBox(width: 8),
                      const Text(
                        'Desconto PIX',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    title: const Text('Ativar Desconto PIX', style: TextStyle(color: Colors.white)),
                    subtitle: const Text('Oferecer desconto para pagamentos via PIX ou Boleto', style: TextStyle(color: Colors.white70)),
                    value: _descontoPixAtivo,
                    onChanged: (value) => setState(() => _descontoPixAtivo = value),
                    activeColor: Colors.green,
                  ),
                  if (_descontoPixAtivo) ...[
                    const SizedBox(height: 16),
                    _buildTextField(
                      _percentualDescontoPixController,
                      'Percentual de Desconto (%)',
                      keyboardType: TextInputType.number,
                      hint: 'Ex: 5 (para 5%)',
                    ),
                  ],
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          Card(
            color: Colors.white.withOpacity(0.1),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.local_shipping, color: Colors.white),
                      const SizedBox(width: 8),
                      const Text(
                        'Frete Grátis',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildTextField(
                    _valorFreteGratisController,
                    'Valor Mínimo para Frete Grátis (R\$)',
                    keyboardType: TextInputType.numberWithOptions(decimal: true),
                    hint: 'Ex: 399.90',
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Pedidos acima deste valor terão frete grátis',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(height: 16),
                  const Divider(color: Colors.white24),
                  const SizedBox(height: 16),
                  const Text(
                    'Banner de Frete Grátis',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    title: const Text('Exibir Banner de Frete Grátis', style: TextStyle(color: Colors.white)),
                    subtitle: const Text('Mostrar banner promocional na loja quando o valor mínimo for atingido', style: TextStyle(color: Colors.white70)),
                    value: _bannerFreteGratisAtivo,
                    onChanged: (value) => setState(() => _bannerFreteGratisAtivo = value),
                    activeColor: Colors.green,
                  ),
                  if (_bannerFreteGratisAtivo) ...[
                    const SizedBox(height: 16),
                    TextField(
                      controller: TextEditingController(text: _textoBannerFreteGratis),
                      onChanged: (value) => setState(() => _textoBannerFreteGratis = value),
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'Texto do Banner',
                        labelStyle: TextStyle(color: Colors.white70),
                        hintText: 'Use {valor} para substituir pelo valor mínimo',
                        hintStyle: TextStyle(color: Colors.white38),
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
                          borderSide: BorderSide(color: Theme.of(context).colorScheme.primary),
                        ),
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.1),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Posição do Banner',
                      style: TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'topo', label: Text('Topo'), icon: Icon(Icons.arrow_upward)),
                        ButtonSegment(value: 'meio', label: Text('Meio'), icon: Icon(Icons.center_focus_strong)),
                        ButtonSegment(value: 'rodape', label: Text('Rodapé'), icon: Icon(Icons.arrow_downward)),
                      ],
                      selected: {_posicaoBannerFreteGratis},
                      onSelectionChanged: (Set<String> newSelection) {
                        setState(() {
                          _posicaoBannerFreteGratis = newSelection.first;
                        });
                      },
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAbaFrete() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Zonas removidas temporariamente para simplificação
          // Opções Fixas removidas temporariamente para simplificação
          
          const SizedBox(height: 16),
          
          // Entrega Local Inteligente (Substitui Mesmo Bairro e Manual)
          Card(
            color: Colors.white.withOpacity(0.1),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.local_shipping, color: Colors.greenAccent),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Frete Inteligente Local (Motoboy/Carro)',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.green.withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.greenAccent, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Calcula automaticamente o valor da entrega na sua cidade com base na distância exata, preço do combustível e consumo do veículo. Ideal para delivery e entregas expressas.',
                            style: TextStyle(color: Colors.green[100], fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    title: const Text('Habilitar Frete Inteligente Local', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    subtitle: const Text('Calcula o custo real da entrega ponto-a-ponto', style: TextStyle(color: Colors.white70)),
                    value: _habilitarEntregaMesmoBairro, // Reutilizando a variável para simplificar
                    onChanged: (value) => setState(() => _habilitarEntregaMesmoBairro = value),
                    activeColor: Colors.greenAccent,
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Transportadoras Nacionais
          Card(
            color: Colors.white.withOpacity(0.1),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.local_shipping, color: Colors.white),
                      const SizedBox(width: 8),
                      const Text(
                        'Cálculos Automáticos (Carrier)',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    title: const Text('Correios (PAC/SEDEX)', style: TextStyle(color: Colors.white)),
                    subtitle: const Text('Cálculo oficial por peso e distância (API/Estimado)', style: TextStyle(color: Colors.white70)),
                    value: _habilitarCorreios,
                    onChanged: (value) => setState(() => _habilitarCorreios = value),
                    activeColor: Colors.green,
                  ),
                  const Divider(color: Colors.white24),
                  SwitchListTile(
                    title: const Text('Jadlog', style: TextStyle(color: Colors.white)),
                    subtitle: const Text('Transportadora nacional com preços competitivos', style: TextStyle(color: Colors.white70)),
                    value: _habilitarJadlog,
                    onChanged: (value) => setState(() => _habilitarJadlog = value),
                    activeColor: Colors.green,
                  ),
                  const Divider(color: Colors.white24),
                  SwitchListTile(
                    title: const Text('Total Express', style: TextStyle(color: Colors.white)),
                    subtitle: const Text('Transportadora nacional com boa cobertura', style: TextStyle(color: Colors.white70)),
                    value: _habilitarTotalExpress,
                    onChanged: (value) => setState(() => _habilitarTotalExpress = value),
                    activeColor: Colors.green,
                  ),
                  const Divider(color: Colors.white24),
                  SwitchListTile(
                    title: const Text('Azul Cargo', style: TextStyle(color: Colors.white)),
                    subtitle: const Text('Transportadora aérea para entregas rápidas', style: TextStyle(color: Colors.white70)),
                    value: _habilitarAzulCargo,
                    onChanged: (value) => setState(() => _habilitarAzulCargo = value),
                    activeColor: Colors.green,
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Credenciais para APIs Reais (Opcional)
          Card(
            color: Colors.blue.withOpacity(0.2),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.api, color: Colors.blue[300]),
                      const SizedBox(width: 8),
                      const Text(
                        'Integração com APIs Reais (Opcional)',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue.withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.blue[300], size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Configure credenciais para usar APIs reais das transportadoras. Se não configurar, o sistema usará cálculos estimados baseados em distância.',
                            style: TextStyle(color: Colors.blue[200], fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildTextField(
                    _correiosCodigoController,
                    'Código Correios (opcional)',
                    keyboardType: TextInputType.text,
                    hint: 'Código da empresa dos Correios',
                    obscureText: false,
                  ),
                  const SizedBox(height: 12),
                  _buildTextField(
                    _correiosSenhaController,
                    'Senha Correios (opcional)',
                    keyboardType: TextInputType.text,
                    hint: 'Senha dos Correios',
                    obscureText: true,
                  ),
                  const SizedBox(height: 12),
                  _buildTextField(
                    _jadlogTokenController,
                    'Token Jadlog (opcional)',
                    keyboardType: TextInputType.text,
                    hint: 'Token de API da Jadlog',
                    obscureText: true,
                  ),
                  const SizedBox(height: 12),
                  _buildTextField(
                    _totalExpressTokenController,
                    'Token Total Express (opcional)',
                    keyboardType: TextInputType.text,
                    hint: 'Token de API da Total Express',
                    obscureText: true,
                  ),
                  const SizedBox(height: 12),
                  _buildTextField(
                    _azulCargoTokenController,
                    'Token Azul Cargo (opcional)',
                    keyboardType: TextInputType.text,
                    hint: 'Token de API da Azul Cargo',
                    obscureText: true,
                  ),
                  const SizedBox(height: 12),
                  _buildTextField(
                    _loggiTokenController,
                    'Token Loggi (opcional)',
                    keyboardType: TextInputType.text,
                    hint: 'Token de API da Loggi',
                    obscureText: true,
                  ),
                  const SizedBox(height: 16),
                  const Divider(color: Colors.white24),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue.withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.star, color: Colors.blue[300], size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Melhor Envio: Plataforma unificada que calcula frete de múltiplas transportadoras de uma vez (recomendado)',
                            style: TextStyle(color: Colors.blue[200], fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildTextField(
                    _melhorEnvioTokenController,
                    'Token Melhor Envio (opcional)',
                    keyboardType: TextInputType.text,
                    hint: 'Token de API do Melhor Envio',
                    obscureText: true,
                  ),
                  const SizedBox(height: 12),
                  _buildTextField(
                    _melhorEnvioEmailController,
                    'E-mail Melhor Envio (opcional)',
                    keyboardType: TextInputType.emailAddress,
                    hint: 'E-mail cadastrado no Melhor Envio',
                    obscureText: false,
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Entregas Rápidas Urbanas
          Card(
            color: Colors.white.withOpacity(0.1),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.flash_on, color: Colors.white),
                      const SizedBox(width: 8),
                      const Text(
                        'Entregas Rápidas Urbanas',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    title: const Text('Loggi Express', style: TextStyle(color: Colors.white)),
                    subtitle: const Text('Entregas rápidas urbanas (até 50km, 1-2 dias úteis)', style: TextStyle(color: Colors.white70)),
                    value: _habilitarLoggi,
                    onChanged: (value) => setState(() => _habilitarLoggi = value),
                    activeColor: Colors.green,
                  ),
                  const Divider(color: Colors.white24),
                  SwitchListTile(
                    title: const Text('Entrega Rápida (iFood/Rappi)', style: TextStyle(color: Colors.white)),
                    subtitle: const Text('Mesmo dia (até 2 horas) - Apenas para produtos leves (até 5kg, até 15km)', style: TextStyle(color: Colors.white70)),
                    value: _habilitarEntregasRapidas,
                    onChanged: (value) => setState(() => _habilitarEntregasRapidas = value),
                    activeColor: Colors.green,
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Configurações Gerais de Cálculo
          Card(
            color: Colors.white.withOpacity(0.1),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                   Row(
                    children: [
                      Icon(Icons.settings, color: Colors.white),
                      const SizedBox(width: 8),
                      const Text(
                        'Configurações de Cálculo Automático',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    title: const Text('Habilitar Estimativa por Distância', style: TextStyle(color: Colors.white)),
                    subtitle: const Text('Usa a distância entre seu CEP e do cliente para estimar valores (pode ser impreciso)', style: TextStyle(color: Colors.white70)),
                    value: _habilitarEstimativaDistancia,
                    onChanged: (value) => setState(() => _habilitarEstimativaDistancia = value),
                    activeColor: Colors.green,
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Informações
          Card(
            color: Colors.blue.withOpacity(0.2),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.blue[300]),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'As opções de frete são calculadas automaticamente com base no CEP de origem e destino. As opções fixas e por zona têm prioridade sobre as transportadoras.',
                      style: TextStyle(color: Colors.blue[100], fontSize: 13),
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

  Widget _buildAbaInformacoes() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            color: Colors.white.withOpacity(0.1),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.contact_mail, color: Colors.white),
                      const SizedBox(width: 8),
                      const Text(
                        'Contato',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildTextField(_whatsappController, 'WhatsApp', hint: 'Ex: 44 99137-1193'),
                  const SizedBox(height: 16),
                  _buildTextField(_emailContatoController, 'E-mail de Contato', keyboardType: TextInputType.emailAddress),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          Card(
            color: Colors.white.withOpacity(0.1),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.share, color: Colors.white),
                      const SizedBox(width: 8),
                      const Text(
                        'Redes Sociais',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    title: const Text('Exibir Redes Sociais', style: TextStyle(color: Colors.white)),
                    value: _exibirRedesSociais,
                    onChanged: (value) => setState(() => _exibirRedesSociais = value),
                    activeColor: Colors.green,
                  ),
                  if (_exibirRedesSociais) ...[
                    const SizedBox(height: 16),
                    _buildTextField(_facebookController, 'Facebook (URL)', hint: 'https://facebook.com/...'),
                    const SizedBox(height: 16),
                    _buildTextField(_instagramController, 'Instagram (URL)', hint: 'https://instagram.com/...'),
                  ],
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          Card(
            color: Colors.white.withOpacity(0.1),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.access_time, color: Colors.white),
                      const SizedBox(width: 8),
                      const Text(
                        'Horário de Funcionamento',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    title: const Text('Exibir Horário', style: TextStyle(color: Colors.white)),
                    value: _exibirHorarioFuncionamento,
                    onChanged: (value) => setState(() => _exibirHorarioFuncionamento = value),
                    activeColor: Colors.green,
                  ),
                  if (_exibirHorarioFuncionamento) ...[
                    const SizedBox(height: 16),
                    _buildTextField(
                      _horarioFuncionamentoController,
                      'Horário',
                      hint: 'Ex: Segunda a Sexta: 8h às 18h',
                    ),
                  ],
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          Card(
            color: Colors.white.withOpacity(0.1),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.location_on, color: Colors.white),
                      const SizedBox(width: 8),
                      const Text(
                        'Endereço da Loja',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    title: const Text('Exibir Endereço', style: TextStyle(color: Colors.white)),
                    value: _exibirEnderecoLoja,
                    onChanged: (value) => setState(() => _exibirEnderecoLoja = value),
                    activeColor: Colors.green,
                  ),
                  if (_exibirEnderecoLoja) ...[
                    const SizedBox(height: 16),
                    _buildTextField(
                      _enderecoLojaController,
                      'Endereço Completo',
                      maxLines: 3,
                      hint: 'Rua, número, bairro, cidade - Estado',
                    ),
                  ],
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          Card(
            color: Colors.white.withOpacity(0.1),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.message, color: Colors.white),
                      const SizedBox(width: 8),
                      const Text(
                        'Mensagens',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildTextField(
                    _mensagemBoasVindasController,
                    'Mensagem de Boas-Vindas',
                    hint: 'Ex: Bem-vindo à nossa loja!',
                  ),
                  const SizedBox(height: 16),
                  _buildTextField(
                    _mensagemFinalizacaoController,
                    'Mensagem de Finalização',
                    hint: 'Ex: Obrigado pela sua compra!',
                    maxLines: 2,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAbaLegal() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            color: Colors.white.withOpacity(0.1),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.description, color: Colors.white),
                      const SizedBox(width: 8),
                      const Text(
                        'Termos de Uso',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildTextField(
                    _termosUsoController,
                    'Termos de Uso',
                    maxLines: 10,
                    hint: 'Digite os termos de uso da loja...',
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          Card(
            color: Colors.white.withOpacity(0.1),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.privacy_tip, color: Colors.white),
                      const SizedBox(width: 8),
                      const Text(
                        'Política de Privacidade',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildTextField(
                    _politicaPrivacidadeController,
                    'Política de Privacidade',
                    maxLines: 10,
                    hint: 'Digite a política de privacidade...',
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          Card(
            color: Colors.white.withOpacity(0.1),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.swap_horiz, color: Colors.white),
                      const SizedBox(width: 8),
                      const Text(
                        'Política de Troca e Devolução',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildTextField(
                    _politicaTrocaController,
                    'Política de Troca/Devolução',
                    maxLines: 10,
                    hint: 'Digite a política de troca e devolução...',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAbaLayout() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // NOVO: Seleção de Modo de Exibição (E-commerce ou Delivery)
          Card(
            color: Colors.blue.withOpacity(0.15),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: Colors.blueAccent.withOpacity(0.3)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.storefront_rounded, color: Colors.blueAccent),
                      const SizedBox(width: 8),
                      const Text(
                        'Modo de Exibição da Loja',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Defina o estilo principal de navegação para seus clientes.',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(
                          value: 'ecommerce', 
                          label: Text('E-commerce'), 
                          icon: Icon(Icons.grid_view_rounded, size: 20)
                        ),
                        ButtonSegment(
                          value: 'delivery', 
                          label: Text('Delivery / Cardápio'), 
                          icon: Icon(Icons.list_alt_rounded, size: 20)
                        ),
                      ],
                      selected: {_modoExibicao},
                      onSelectionChanged: (Set<String> newSelection) {
                        setState(() => _modoExibicao = newSelection.first);
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _modoExibicao == 'ecommerce' 
                      ? '💡 Ideal para lojas de roupas, eletrônicos e produtos com foco em fotos grandes.'
                      : '💡 Ideal para restaurantes, petshops e vendas rápidas com foco em lista.',
                    style: TextStyle(color: Colors.blue[100], fontSize: 11, fontStyle: FontStyle.italic),
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 24),
          Card(
            color: Colors.white.withOpacity(0.1),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.aspect_ratio, color: Colors.white),
                      const SizedBox(width: 8),
                      const Text(
                        'Tamanho do Logo',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'pequeno', label: Text('Pequeno')),
                      ButtonSegment(value: 'medio', label: Text('Médio')),
                      ButtonSegment(value: 'grande', label: Text('Grande')),
                    ],
                    selected: {_tamanhoLogo},
                    onSelectionChanged: (Set<String> newSelection) {
                      setState(() => _tamanhoLogo = newSelection.first);
                    },
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          Card(
            color: Colors.white.withOpacity(0.1),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.format_align_center, color: Colors.white),
                      const SizedBox(width: 8),
                      const Text(
                        'Posição do Logo',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'esquerda', label: Text('Esquerda')),
                      ButtonSegment(value: 'centro', label: Text('Centro')),
                      ButtonSegment(value: 'direita', label: Text('Direita')),
                    ],
                    selected: {_posicaoLogo},
                    onSelectionChanged: (Set<String> newSelection) {
                      setState(() => _posicaoLogo = newSelection.first);
                    },
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          Card(
            color: Colors.white.withOpacity(0.1),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.dashboard, color: Colors.white),
                      const SizedBox(width: 8),
                      const Text(
                        'Estilo dos Cards',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'padrao', label: Text('Padrão')),
                      ButtonSegment(value: 'moderno', label: Text('Moderno')),
                      ButtonSegment(value: 'minimalista', label: Text('Minimalista')),
                    ],
                    selected: {_estiloCards},
                    onSelectionChanged: (Set<String> newSelection) {
                      setState(() => _estiloCards = newSelection.first);
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // O método _buildAbaAgendamento foi removido e movido para ConfiguracoesAgendaPage

  Widget _buildUploadBannerPromocional(
    String titulo,
    String? urlAtual,
    bool uploading,
    Function(String) onUrlRecebida,
    Function() onUploadIniciado,
    Function() onUploadFinalizado,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          titulo,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 8),
        if (urlAtual != null && urlAtual.isNotEmpty)
          Container(
            height: 120,
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white30),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Stack(
                children: [
                  Image.network(
                    urlAtual,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    height: double.infinity,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        color: Colors.grey[800],
                        child: const Center(
                          child: Icon(Icons.error, color: Colors.red),
                        ),
                      );
                    },
                  ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: IconButton(
                      icon: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.6),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.close,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                      onPressed: () {
                        onUrlRecebida('');
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ElevatedButton.icon(
          onPressed: uploading ? null : () => _uploadBannerPromocional(
            titulo,
            onUrlRecebida,
            onUploadIniciado,
            onUploadFinalizado,
          ),
          icon: uploading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.upload),
          label: Text(uploading ? 'Enviando...' : (urlAtual != null && urlAtual.isNotEmpty ? 'Trocar Banner' : 'Enviar Banner')),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }

  Future<void> _uploadBannerPromocional(
    String titulo,
    Function(String) onUrlRecebida,
    Function() onUploadIniciado,
    Function() onUploadFinalizado,
  ) async {
    try {
      onUploadIniciado();
      
      FilePickerResult? result;
      if (kIsWeb) {
        result = await FilePicker.platform.pickFiles(
          type: FileType.image,
          allowMultiple: false,
          withData: true,
        );
      } else {
        result = await FilePicker.platform.pickFiles(
          type: FileType.image,
          allowMultiple: false,
        );
      }

      if (result == null || result.files.isEmpty) {
        onUploadFinalizado();
        return;
      }

      final authService = Provider.of<AuthService>(context, listen: false);
      final empresa = authService.empresaAtual;
      
      if (empresa == null) {
        onUploadFinalizado();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Erro: Empresa não encontrada'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
      
      final file = result.files.first;
      String? url;
      
      if (kIsWeb) {
        if (file.bytes == null || file.bytes!.isEmpty) {
          onUploadFinalizado();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Erro: Não foi possível ler o arquivo. Tente novamente.'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }
        
        url = await ImageStorageService.salvarImagemERetornarUrl(
          imageBytes: file.bytes!,
          empresaId: empresa.id,
          categoria: 'banners_promocionais',
          nome: titulo,
          metadata: {
            'tipo': 'banner_promocional',
            'empresa_id': empresa.id,
            'titulo': titulo,
          },
        );
      } else {
        if (file.path == null || file.path!.isEmpty) {
          onUploadFinalizado();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Erro: Caminho do arquivo não encontrado'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }
        
        try {
          final fileData = await File(file.path!).readAsBytes();
          url = await ImageStorageService.salvarImagemERetornarUrl(
            imageBytes: fileData,
            empresaId: empresa.id,
            categoria: 'banners_promocionais',
            nome: titulo,
            metadata: {
              'tipo': 'banner_promocional',
              'empresa_id': empresa.id,
              'titulo': titulo,
            },
          );
        } catch (e) {
          onUploadFinalizado();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Erro ao ler arquivo: $e'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }
      }
      
      if (url != null && url.isNotEmpty) {
        onUrlRecebida(url);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$titulo enviado com sucesso!'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Erro: Upload retornou vazio. Tente novamente.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e, stackTrace) {
      debugPrint('>>> Erro ao enviar banner promocional: $e');
      debugPrint('>>> StackTrace: $stackTrace');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao enviar banner: ${e.toString()}'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    } finally {
      onUploadFinalizado();
    }
  }

  Widget _buildInfoTamanhoBannerPromocional(
    String titulo,
    String tamanho,
    String proporcao,
    IconData icone,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(icone, color: Colors.blue[300], size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  tamanho,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white.withOpacity(0.9),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  proporcao,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withOpacity(0.7),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField(
    TextEditingController controller,
    String label, {
    String? hint,
    TextInputType? keyboardType,
    int maxLines = 1,
    bool obscureText = false,
  }) {
    return TextFormField(
      controller: controller,
      style: const TextStyle(color: Colors.white),
      keyboardType: keyboardType,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.white70),
        hintText: hint,
        hintStyle: TextStyle(color: Colors.white38),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.white30),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.white30),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.green),
        ),
        filled: true,
        fillColor: Colors.white.withOpacity(0.1),
      ),
    );
  }

  // ============================================
  // GERENCIAMENTO DE ZONAS DE ENTREGA
  // ============================================

  Widget _buildCardZonaEntrega(ZonaEntrega zona) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: Colors.white.withOpacity(0.05),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _obterIconeTipoZona(zona.tipo),
                  color: Colors.green[300],
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    zona.nome,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                Switch(
                  value: zona.ativo,
                  onChanged: (value) {
                    setState(() {
                      final index = _zonasEntrega.indexWhere((z) => z.id == zona.id);
                      if (index != -1) {
                        _zonasEntrega[index] = zona.copyWith(ativo: value);
                      }
                    });
                  },
                  activeColor: Colors.green,
                ),
                IconButton(
                  icon: const Icon(Icons.edit, color: Colors.blue),
                  onPressed: () => _editarZonaEntrega(zona),
                ),
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () => _removerZonaEntrega(zona),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _buildChipInfo('Tipo', _obterNomeTipoZona(zona.tipo)),
                const SizedBox(width: 8),
                _buildChipInfo('Taxa', 'R\$ ${zona.taxaFixa.toStringAsFixed(2)}'),
                if (zona.taxaPorKm != null && zona.taxaPorKm! > 0)
                  _buildChipInfo('+ Km', 'R\$ ${zona.taxaPorKm!.toStringAsFixed(2)}'),
              ],
            ),
            if (zona.bairro != null || zona.cidade != null || zona.raioKm != null) ...[
              const SizedBox(height: 8),
              Text(
                _obterDescricaoZona(zona),
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
            Text(
              'Prazo: ${zona.prazoMinimo}-${zona.prazoMaximo} dias | Prioridade: ${zona.prioridade}',
              style: TextStyle(color: Colors.white60, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChipInfo(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(color: Colors.white70, fontSize: 11),
      ),
    );
  }

  IconData _obterIconeTipoZona(String tipo) {
    switch (tipo) {
      case 'bairro':
        return Icons.location_on;
      case 'cidade':
        return Icons.location_city;
      case 'raio':
        return Icons.radio_button_checked;
      case 'regiao':
        return Icons.map;
      default:
        return Icons.place;
    }
  }

  String _obterNomeTipoZona(String tipo) {
    switch (tipo) {
      case 'bairro':
        return 'Bairro';
      case 'cidade':
        return 'Cidade';
      case 'raio':
        return 'Raio';
      case 'regiao':
        return 'Região';
      default:
        return tipo;
    }
  }

  String _obterDescricaoZona(ZonaEntrega zona) {
    if (zona.tipo == 'bairro' && zona.bairro != null) {
      return 'Bairro: ${zona.bairro}${zona.cidade != null ? ' - ${zona.cidade}' : ''}';
    } else if (zona.tipo == 'cidade' && zona.cidade != null) {
      return 'Cidade: ${zona.cidade}${zona.estado != null ? ' - ${zona.estado}' : ''}';
    } else if (zona.tipo == 'raio' && zona.raioKm != null) {
      return 'Raio: ${zona.raioKm!.toStringAsFixed(1)} km';
    } else if (zona.tipo == 'regiao' && zona.estado != null) {
      return 'Região: ${zona.estado}';
    }
    return '';
  }

  void _adicionarZonaEntrega() {
    _mostrarDialogoZonaEntrega();
  }

  void _editarZonaEntrega(ZonaEntrega zona) {
    _mostrarDialogoZonaEntrega(zona: zona);
  }

  void _removerZonaEntrega(ZonaEntrega zona) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remover Zona'),
        content: Text('Deseja realmente remover a zona "${zona.nome}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                _zonasEntrega.removeWhere((z) => z.id == zona.id);
              });
              Navigator.pop(context);
            },
            child: const Text('Remover', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _mostrarDialogoZonaEntrega({ZonaEntrega? zona}) {
    final nomeController = TextEditingController(text: zona?.nome ?? '');
    final bairroController = TextEditingController(text: zona?.bairro ?? '');
    final cidadeController = TextEditingController(text: zona?.cidade ?? '');
    final estadoController = TextEditingController(text: zona?.estado ?? '');
    final raioController = TextEditingController(text: zona?.raioKm?.toString() ?? '');
    final taxaFixaController = TextEditingController(text: zona?.taxaFixa.toStringAsFixed(2) ?? '5.00');
    final taxaPorKmController = TextEditingController(text: zona?.taxaPorKm?.toStringAsFixed(2) ?? '');
    final prazoMinController = TextEditingController(text: zona?.prazoMinimo.toString() ?? '1');
    final prazoMaxController = TextEditingController(text: zona?.prazoMaximo.toString() ?? '3');
    final prioridadeController = TextEditingController(text: zona?.prioridade.toString() ?? '0');
    
    String tipoSelecionado = zona?.tipo ?? 'bairro';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(zona == null ? 'Adicionar Zona' : 'Editar Zona'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nomeController,
                  decoration: const InputDecoration(
                    labelText: 'Nome da Zona *',
                    hintText: 'Ex: Centro, Zona Norte, etc.',
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: tipoSelecionado,
                  decoration: const InputDecoration(labelText: 'Tipo de Zona *'),
                  items: const [
                    DropdownMenuItem(value: 'bairro', child: Text('Bairro')),
                    DropdownMenuItem(value: 'cidade', child: Text('Cidade')),
                    DropdownMenuItem(value: 'raio', child: Text('Raio (por distância)')),
                    DropdownMenuItem(value: 'regiao', child: Text('Região (Estado)')),
                  ],
                  onChanged: (value) {
                    setDialogState(() {
                      tipoSelecionado = value!;
                    });
                  },
                ),
                const SizedBox(height: 16),
                if (tipoSelecionado == 'bairro') ...[
                  TextFormField(
                    controller: bairroController,
                    decoration: const InputDecoration(
                      labelText: 'Nome do Bairro *',
                      hintText: 'Ex: Centro',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: cidadeController,
                    decoration: const InputDecoration(
                      labelText: 'Cidade (opcional)',
                      hintText: 'Ex: Maringá',
                    ),
                  ),
                ] else if (tipoSelecionado == 'cidade') ...[
                  TextFormField(
                    controller: cidadeController,
                    decoration: const InputDecoration(
                      labelText: 'Nome da Cidade *',
                      hintText: 'Ex: Maringá',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: estadoController,
                    decoration: const InputDecoration(
                      labelText: 'Estado (opcional)',
                      hintText: 'Ex: PR',
                    ),
                    maxLength: 2,
                    textCapitalization: TextCapitalization.characters,
                  ),
                ] else if (tipoSelecionado == 'raio') ...[
                  TextFormField(
                    controller: raioController,
                    decoration: const InputDecoration(
                      labelText: 'Raio em km *',
                      hintText: 'Ex: 15',
                    ),
                    keyboardType: TextInputType.numberWithOptions(decimal: true),
                  ),
                ] else if (tipoSelecionado == 'regiao') ...[
                  TextFormField(
                    controller: estadoController,
                    decoration: const InputDecoration(
                      labelText: 'Estado *',
                      hintText: 'Ex: PR',
                    ),
                    maxLength: 2,
                    textCapitalization: TextCapitalization.characters,
                  ),
                ],
                const SizedBox(height: 16),
                TextFormField(
                  controller: taxaFixaController,
                  decoration: const InputDecoration(
                    labelText: 'Taxa Fixa (R\$) *',
                    hintText: 'Ex: 5.00',
                  ),
                  keyboardType: TextInputType.numberWithOptions(decimal: true),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: taxaPorKmController,
                  decoration: const InputDecoration(
                    labelText: 'Taxa por km (R\$) - Opcional',
                    hintText: 'Ex: 0.50 (para cálculo por distância)',
                  ),
                  keyboardType: TextInputType.numberWithOptions(decimal: true),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: prazoMinController,
                        decoration: const InputDecoration(
                          labelText: 'Prazo Mín (dias)',
                        ),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        controller: prazoMaxController,
                        decoration: const InputDecoration(
                          labelText: 'Prazo Máx (dias)',
                        ),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: prioridadeController,
                  decoration: const InputDecoration(
                    labelText: 'Prioridade',
                    hintText: 'Menor número = maior prioridade',
                  ),
                  keyboardType: TextInputType.number,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () {
                final novaZona = ZonaEntrega(
                  id: zona?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
                  nome: nomeController.text.trim(),
                  tipo: tipoSelecionado,
                  bairro: tipoSelecionado == 'bairro' ? bairroController.text.trim() : null,
                  cidade: tipoSelecionado == 'cidade' || tipoSelecionado == 'bairro'
                      ? (cidadeController.text.trim().isNotEmpty ? cidadeController.text.trim() : null)
                      : null,
                  estado: tipoSelecionado == 'regiao' || tipoSelecionado == 'cidade'
                      ? (estadoController.text.trim().isNotEmpty ? estadoController.text.trim().toUpperCase() : null)
                      : null,
                  raioKm: tipoSelecionado == 'raio'
                      ? double.tryParse(raioController.text.replaceAll(',', '.'))
                      : null,
                  taxaFixa: double.tryParse(taxaFixaController.text.replaceAll(',', '.')) ?? 5.0,
                  taxaPorKm: taxaPorKmController.text.trim().isNotEmpty
                      ? double.tryParse(taxaPorKmController.text.replaceAll(',', '.'))
                      : null,
                  prazoMinimo: int.tryParse(prazoMinController.text) ?? 1,
                  prazoMaximo: int.tryParse(prazoMaxController.text) ?? 3,
                  prioridade: int.tryParse(prioridadeController.text) ?? 0,
                  ativo: zona?.ativo ?? true,
                );

                setState(() {
                  if (zona == null) {
                    _zonasEntrega.add(novaZona);
                  } else {
                    final index = _zonasEntrega.indexWhere((z) => z.id == zona.id);
                    if (index != -1) {
                      _zonasEntrega[index] = novaZona;
                    }
                  }
                });

                Navigator.pop(context);
              },
              child: Text(zona == null ? 'Adicionar' : 'Salvar'),
            ),
          ],
        ),
      ),
    );
  }
  void _adicionarOpcaoFreteFixa() {
    _mostrarDialogoOpcaoFreteFixa();
  }

  void _editarOpcaoFreteFixa(int index) {
    _mostrarDialogoOpcaoFreteFixa(opcao: _opcoesFreteFixas[index], index: index);
  }

  Future<void> _mostrarDialogoOpcaoFreteFixa({OpcaoFrete? opcao, int? index}) async {
    final nomeController = TextEditingController(text: opcao?.nome ?? '');
    final valorController = TextEditingController(text: opcao?.valor.toStringAsFixed(2) ?? '');
    final prazoController = TextEditingController(text: opcao?.prazo.toString() ?? '');
    final descricaoController = TextEditingController(text: opcao?.descricao ?? '');

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E2228),
        title: Text(
          opcao == null ? 'Nova Opção de Frete Fixa' : 'Editar Opção de Frete Fixa',
          style: const TextStyle(color: Colors.white),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildTextField(nomeController, 'Nome da Opção', hint: 'Ex: Motoboy Local'),
              const SizedBox(height: 12),
              _buildTextField(valorController, 'Valor do Frete (R\$) ', keyboardType: const TextInputType.numberWithOptions(decimal: true)),
              const SizedBox(height: 12),
              _buildTextField(prazoController, 'Prazo (dias úteis)', keyboardType: TextInputType.number),
              const SizedBox(height: 12),
              _buildTextField(descricaoController, 'Descrição (opcional)', hint: 'Ex: Entrega rápida para todo Brasil'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            onPressed: () {
              if (nomeController.text.isEmpty || valorController.text.isEmpty || prazoController.text.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Por favor, preencha todos os campos obrigatórios')),
                );
                return;
              }

              final novaOpcao = OpcaoFrete(
                id: opcao?.id ?? 'fixa_${DateTime.now().millisecondsSinceEpoch}',
                nome: nomeController.text.trim(),
                tipo: 'manual',
                valor: double.tryParse(valorController.text.replaceAll(',', '.')) ?? 0.0,
                prazo: int.tryParse(prazoController.text) ?? 5,
                descricao: descricaoController.text.trim().isNotEmpty ? descricaoController.text.trim() : null,
              );

              setState(() {
                if (index != null) {
                  _opcoesFreteFixas[index] = novaOpcao;
                } else {
                  _opcoesFreteFixas.add(novaOpcao);
                }
              });
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.primary),
            child: Text(opcao == null ? 'Adicionar' : 'Salvar'),
          ),
        ],
      ),
    );
  }
}

// Widget simples de seletor de cores
class BlockPicker extends StatelessWidget {
  final Color pickerColor;
  final Function(Color) onColorChanged;

  const BlockPicker({
    super.key,
    required this.pickerColor,
    required this.onColorChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cores = [
      Colors.red,
      Colors.pink,
      Colors.purple,
      Colors.deepPurple,
      Colors.indigo,
      Colors.blue,
      Colors.lightBlue,
      Colors.cyan,
      Colors.teal,
      Colors.green,
      Colors.lightGreen,
      Colors.lime,
      Colors.yellow,
      Colors.amber,
      Colors.orange,
      Colors.deepOrange,
      Colors.brown,
      Colors.grey,
      Colors.blueGrey,
      Colors.black,
      Colors.white,
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: cores.map((cor) {
        return GestureDetector(
          onTap: () => onColorChanged(cor),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: cor,
              shape: BoxShape.circle,
              border: Border.all(
                color: pickerColor == cor ? Colors.black : Colors.grey,
                width: pickerColor == cor ? 3 : 1,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
