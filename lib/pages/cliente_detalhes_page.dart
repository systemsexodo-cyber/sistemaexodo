import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/cliente.dart';
import '../models/pet.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../models/pedido.dart';
import '../models/forma_pagamento.dart';
import '../models/agendamento_servico.dart';
import '../models/venda_balcao.dart';
import '../models/item_material.dart';
import '../services/data_service.dart';
import '../theme.dart';
import 'venda_direta_page.dart';
import 'lancar_pedido_page.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import '../services/image_storage_service.dart';
import 'dart:typed_data';

/// Widget simplificado para carregar imagem - SEM verificação prévia que pode bloquear
/// PROTEÇÃO CONTRA CRASH: Todos os erros são capturados
class _ImageNetworkWithTimeout extends StatelessWidget {
  final String imageUrl;
  final double width;
  final double height;
  final BoxFit fit;

  const _ImageNetworkWithTimeout({
    required this.imageUrl,
    required this.width,
    required this.height,
    required this.fit,
  });

  @override
  Widget build(BuildContext context) {
    // PROTEÇÃO CRÍTICA: Envolver tudo em try-catch para evitar crash
    try {
      debugPrint('>>> [ImageNetwork] Tentando carregar: $imageUrl');
      
      // Validar URL antes de tentar carregar
      if (imageUrl.isEmpty) {
        debugPrint('>>> [ImageNetwork] ⚠️ URL vazia');
        return _buildErrorWidget('URL vazia');
      }
      
      return Image.network(
        imageUrl,
        width: width,
        height: height,
        fit: fit,
        cacheWidth: width.toInt(),
        cacheHeight: height.toInt(),
        // PROTEÇÃO: Timeout para evitar travamento
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          if (wasSynchronouslyLoaded || frame != null) {
            return child;
          }
          // Mostrar loading enquanto carrega
          return Container(
            width: width,
            height: height,
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.3),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Center(
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        },
        loadingBuilder: (context, child, loadingProgress) {
          try {
            if (loadingProgress == null) {
              debugPrint('>>> [ImageNetwork] ✅ Imagem carregada com sucesso!');
              return child;
            }
            final progress = loadingProgress.expectedTotalBytes != null
                ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                : 0.0;
            debugPrint('>>> [ImageNetwork] Carregando... ${(progress * 100).toStringAsFixed(1)}%');
            return Container(
              width: width,
              height: height,
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.3),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  value: progress > 0 ? progress : null,
                ),
              ),
            );
          } catch (e) {
            debugPrint('>>> [ImageNetwork] Erro no loadingBuilder: $e');
            return _buildErrorWidget('Erro ao carregar');
          }
        },
        errorBuilder: (context, error, stackTrace) {
          try {
            debugPrint('>>> [ImageNetwork] ❌ ERRO ao carregar imagem!');
            debugPrint('>>> [ImageNetwork] URL: $imageUrl');
            debugPrint('>>> [ImageNetwork] Erro: $error');
            debugPrint('>>> [ImageNetwork] StackTrace: $stackTrace');
            return _buildErrorWidget('Erro ao carregar');
          } catch (e) {
            // PROTEÇÃO CRÍTICA: Se até o errorBuilder falhar, retornar widget seguro
            debugPrint('>>> [ImageNetwork] ❌❌❌ ERRO CRÍTICO no errorBuilder: $e');
            return _buildErrorWidget('Erro crítico');
          }
        },
        // Tentar carregar mesmo com erros de CORS
        gaplessPlayback: true,
      );
    } catch (e, stackTrace) {
      // PROTEÇÃO CRÍTICA: Se qualquer coisa falhar no build, retornar widget seguro
      debugPrint('>>> [ImageNetwork] ❌❌❌ ERRO CRÍTICO no build: $e');
      debugPrint('>>> [ImageNetwork] StackTrace: $stackTrace');
      return _buildErrorWidget('Erro crítico');
    }
  }

  /// Widget seguro para exibir erro - NUNCA pode falhar
  Widget _buildErrorWidget(String mensagem) {
    try {
      return Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: Colors.red.withOpacity(0.3),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 20),
            const SizedBox(height: 4),
            Text(
              mensagem,
              style: const TextStyle(
                color: Colors.red,
                fontSize: 10,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      );
    } catch (e) {
      // Se até isso falhar, retornar container vazio mínimo
      debugPrint('>>> [ImageNetwork] ❌❌❌ ERRO MUITO CRÍTICO: $e');
      return Container(
        width: width,
        height: height,
        color: Colors.red.withOpacity(0.1),
      );
    }
  }
}

class ClienteDetalhesPage extends StatefulWidget {
  final Cliente? cliente;
  final int? abaInicial; // Índice da aba inicial (0=Dados, 1=Endereço, 2=Adicional, 3=Pet, 4=Financeiro)
  final String? petIdParaEditar; // ID do pet para editar (opcional)

  const ClienteDetalhesPage({
    super.key,
    this.cliente,
    this.abaInicial,
    this.petIdParaEditar,
  });

  @override
  State<ClienteDetalhesPage> createState() => _ClienteDetalhesPageState();
}

class _ClienteDetalhesPageState extends State<ClienteDetalhesPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;

  // Controladores
  final _nomeController = TextEditingController();
  final _nomeFantasiaController = TextEditingController();
  final _cpfCnpjController = TextEditingController();
  final _rgIeController = TextEditingController();
  final _emailController = TextEditingController();
  final _telefoneController = TextEditingController();
  final _telefone2Controller = TextEditingController();
  final _whatsappController = TextEditingController();
  final _enderecoController = TextEditingController();
  String _tipoLogradouro = 'Rua'; // 'Rua' ou 'Avenida'
  final _numeroController = TextEditingController();
  final _complementoController = TextEditingController();
  final _bairroController = TextEditingController();
  final _cidadeController = TextEditingController();
  final _estadoController = TextEditingController();
  final _cepController = TextEditingController();
  final _pontoReferenciaController = TextEditingController();
  final _profissaoController = TextEditingController();
  final _observacoesController = TextEditingController();
  final _limiteCreditoController = TextEditingController();

  TipoPessoa _tipoPessoa = TipoPessoa.fisica;
  DateTime? _dataNascimento;
  bool _ativo = true;
  bool _bloqueado = false;
  
  // Pets
  List<Pet> _pets = [];
  final ImagePicker _imagePicker = ImagePicker();
  bool _uploadingFoto = false; // Flag para controlar upload de foto

  bool get _isEditing => widget.cliente != null && widget.cliente!.id.isNotEmpty;
  

  /// Retorna a URL permanente do Firebase ou null se falhar
  /// [onProgress] callback opcional para atualizar progresso (recebe progresso de 0.0 a 1.0)
  Future<String?> _uploadFotoPet(String localPath, String petId, String clienteId, {Function(double)? onProgress}) async {
    try {
      debugPrint('>>> [Upload Foto Pet] ========================================');
      debugPrint('>>> [Upload Foto Pet] INICIANDO UPLOAD');
      debugPrint('>>> [Upload Foto Pet] Pet ID: $petId');
      debugPrint('>>> [Upload Foto Pet] Cliente ID: $clienteId');
      debugPrint('>>> [Upload Foto Pet] Caminho local: $localPath');
      
      final dataService = Provider.of<DataService>(context, listen: false);
      final empresaId = dataService.empresaIdAtual;
      
      if (empresaId == null) {
        debugPrint('>>> [Upload Foto Pet] ❌ ERRO: Empresa ID não encontrado');
        throw Exception('Empresa ID não encontrado. Certifique-se de que uma empresa está selecionada.');
      }
      
      debugPrint('>>> [Upload Foto Pet] Empresa ID: $empresaId');
      
      _uploadingFoto = true;
      
      final nomeArquivo = 'pet_${petId}_${DateTime.now().millisecondsSinceEpoch}';
      final caminhoStorage = 'pets/$empresaId/$clienteId/$nomeArquivo';
      
      debugPrint('>>> [Upload Foto Pet] Caminho no storage: $caminhoStorage');
      
      // Ler bytes do arquivo
      Uint8List imageBytes;
      if (kIsWeb && localPath.startsWith('blob:')) {
        // Web: converter blob URL para bytes
        final response = await http.get(Uri.parse(localPath)).timeout(
          const Duration(seconds: 10),
        );
        imageBytes = response.bodyBytes;
      } else if (!kIsWeb) {
        // Mobile: ler arquivo local
        final file = File(localPath);
        imageBytes = await file.readAsBytes();
      } else {
        throw Exception('Caminho de arquivo não suportado: $localPath');
      }
      
      if (imageBytes.isEmpty) {
        throw Exception('Arquivo de imagem vazio');
      }
      
      // Obter nome do pet para salvar
      final pet = widget.cliente?.pets.firstWhere(
        (p) => p.id == petId,
        orElse: () => Pet(
          id: petId,
          nome: 'Pet',
          especie: '',
          raca: '',
          dataNascimento: DateTime.now(),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );
      
      // Usar armazenamento GRATUITO no Firestore
      debugPrint('>>> [Upload Foto Pet] Chamando ImageStorageService (GRATUITO)...');
      if (onProgress != null) onProgress(0.3);
      
      final url = await ImageStorageService.salvarImagemERetornarUrl(
        imageBytes: imageBytes,
        empresaId: empresaId,
        categoria: 'pets',
        nome: '${pet?.nome ?? "Pet"} - ${widget.cliente?.nome ?? "Cliente"}',
        metadata: {
          'pet_id': petId,
          'cliente_id': clienteId,
          'empresa_id': empresaId,
        },
      );
      
      if (onProgress != null) onProgress(1.0);
      
      if (url != null) {
        debugPrint('>>> [Upload Foto Pet] ✅ Upload concluído com sucesso!');
        debugPrint('>>> [Upload Foto Pet] URL: $url');
      } else {
        debugPrint('>>> [Upload Foto Pet] ❌ Upload retornou null (falhou)');
        throw Exception('Upload falhou - retornou null');
      }
      
      debugPrint('>>> [Upload Foto Pet] ========================================');
      return url;
    } catch (e, stackTrace) {
      debugPrint('>>> [Upload Foto Pet] ❌❌❌ ERRO AO FAZER UPLOAD ❌❌❌');
      debugPrint('>>> [Upload Foto Pet] Erro: $e');
      debugPrint('>>> [Upload Foto Pet] StackTrace: $stackTrace');
      debugPrint('>>> [Upload Foto Pet] ========================================');
      
      // Mostrar erro ao usuário
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao enviar foto: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
      
      // Em caso de erro, retornar null para que não seja salvo um caminho inválido
      return null;
    } finally {
      _uploadingFoto = false;
    }
  }

  @override
  void initState() {
    super.initState();
    // Se está editando, mostrar 5 abas (incluindo Financeiro e Pet)
    // Mas a aba Pet só deve aparecer se o módulo Pet estiver ativo
    final dataService = Provider.of<DataService>(context, listen: false);
    final isModuloPet = dataService.empresaAtual?.moduloPet ?? false;
    
    int numTabs = 3; // Dados, Endereço, Adicional
    if (isModuloPet) numTabs++; // + Pet
    if (widget.cliente != null) numTabs++; // + Financeiro

    _tabController = TabController(
      length: numTabs,
      vsync: this,
      initialIndex: widget.abaInicial ?? 0, // Usar aba inicial se fornecida
    );
    _carregarDados();
    
    // Se tem petIdParaEditar, abrir diálogo de edição após carregar dados
    if (widget.petIdParaEditar != null && widget.cliente != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _abrirEdicaoPetPorId(widget.petIdParaEditar!);
      });
    }
  }
  
  void _abrirEdicaoPetPorId(String petId) {
    final index = _pets.indexWhere((p) => p.id == petId);
    if (index != -1) {
      _mostrarDialogEditarPet(index);
    }
  }

  void _carregarDados() {
    if (widget.cliente != null) {
      final c = widget.cliente!;
      _nomeController.text = c.nome;
      _nomeFantasiaController.text = c.nomeFantasia ?? '';
      _tipoPessoa = c.tipoPessoa;
      _cpfCnpjController.text = c.cpfCnpj ?? '';
      _rgIeController.text = c.rgIe ?? '';
      _emailController.text = c.email ?? '';
      _telefoneController.text = c.telefone;
      _telefone2Controller.text = c.telefone2 ?? '';
      _whatsappController.text = c.whatsapp ?? '';
      // Separar tipo de logradouro e nome do logradouro
      final enderecoCompleto = c.endereco ?? '';
      if (enderecoCompleto.startsWith('Rua ') || enderecoCompleto.startsWith('rua ')) {
        _tipoLogradouro = 'Rua';
        _enderecoController.text = enderecoCompleto.replaceFirst(RegExp(r'^[Rr]ua\s+'), '');
      } else if (enderecoCompleto.startsWith('Avenida ') || enderecoCompleto.startsWith('avenida ') || 
                 enderecoCompleto.startsWith('Av. ') || enderecoCompleto.startsWith('av. ')) {
        _tipoLogradouro = 'Avenida';
        _enderecoController.text = enderecoCompleto.replaceFirst(RegExp(r'^[Aa]venida\s+|^[Aa]v\.\s+'), '');
      } else {
        _tipoLogradouro = 'Rua';
        _enderecoController.text = enderecoCompleto;
      }
      _numeroController.text = c.numero ?? '';
      _complementoController.text = c.complemento ?? '';
      _bairroController.text = c.bairro ?? '';
      _cidadeController.text = c.cidade ?? '';
      _estadoController.text = c.estado ?? '';
      _cepController.text = c.cep ?? '';
      _pontoReferenciaController.text = c.pontoReferencia ?? '';
      _dataNascimento = c.dataNascimento;
      _profissaoController.text = c.profissao ?? '';
      _observacoesController.text = c.observacoes ?? '';
      _limiteCreditoController.text = c.limiteCredito?.toStringAsFixed(2) ?? '';
      _ativo = c.ativo;
      _bloqueado = c.bloqueado;
      _pets = List.from(c.pets);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _nomeController.dispose();
    _nomeFantasiaController.dispose();
    _cpfCnpjController.dispose();
    _rgIeController.dispose();
    _emailController.dispose();
    _telefoneController.dispose();
    _telefone2Controller.dispose();
    _whatsappController.dispose();
    _enderecoController.dispose();
    _numeroController.dispose();
    _complementoController.dispose();
    _bairroController.dispose();
    _cidadeController.dispose();
    _estadoController.dispose();
    _cepController.dispose();
    _pontoReferenciaController.dispose();
    _profissaoController.dispose();
    _observacoesController.dispose();
    _limiteCreditoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppTheme.appBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(_isEditing ? 'Editar Cliente' : 'Novo Cliente'),
          centerTitle: true,
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context),
          ),
          actions: [
            if (_isEditing)
              IconButton(
                icon: const Icon(Icons.delete, color: Colors.redAccent),
                tooltip: 'Excluir cliente',
                onPressed: _confirmarExclusao,
              ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(50),
            child: Consumer<DataService>(
              builder: (context, dataService, _) {
                final isModuloPet = dataService.empresaAtual?.moduloPet ?? false;
                return TabBar(
                  controller: _tabController,
                  indicatorColor: Colors.greenAccent,
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.white54,
                  isScrollable: true,
                  tabs: [
                    const Tab(icon: Icon(Icons.person), text: 'Dados'),
                    const Tab(icon: Icon(Icons.location_on), text: 'Endereço'),
                    const Tab(icon: Icon(Icons.info), text: 'Adicional'),
                    if (isModuloPet) const Tab(icon: Icon(Icons.pets), text: 'Pet'),
                    if (_isEditing)
                      const Tab(
                        icon: Icon(Icons.account_balance_wallet),
                        text: 'Financeiro',
                      ),
                  ],
                );
              },
            ),
          ),
        ),
        body: Form(
          key: _formKey,
          child: Consumer<DataService>(
            builder: (context, dataService, _) {
              final isModuloPet = dataService.empresaAtual?.moduloPet ?? false;
              return TabBarView(
                controller: _tabController,
                children: [
                  _buildTabDados(),
                  _buildTabEndereco(),
                  _buildTabAdicional(),
                  if (isModuloPet) _buildTabPet(),
                  if (_isEditing) _buildTabFinanceiro(),
                ],
              );
            },
          ),
        ),
        bottomNavigationBar: _buildBotaoSalvar(),
      ),
    );
  }

  Widget _buildTabDados() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Tipo de Pessoa
          _buildSecaoTitulo('Tipo de Pessoa', Icons.badge),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildOpcaoTipo(
                  TipoPessoa.fisica,
                  'Pessoa Física',
                  Icons.person,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildOpcaoTipo(
                  TipoPessoa.juridica,
                  'Pessoa Jurídica',
                  Icons.business,
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Dados Principais
          _buildSecaoTitulo('Dados Principais', Icons.account_circle),
          const SizedBox(height: 12),
          _buildCampoTexto(
            controller: _nomeController,
            label: _tipoPessoa == TipoPessoa.fisica
                ? 'Nome Completo *'
                : 'Razão Social *',
            icon: Icons.person,
            required: true,
          ),
          if (_tipoPessoa == TipoPessoa.juridica) ...[
            const SizedBox(height: 12),
            _buildCampoTexto(
              controller: _nomeFantasiaController,
              label: 'Nome Fantasia',
              icon: Icons.store,
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildCampoTexto(
                  controller: _cpfCnpjController,
                  label: _tipoPessoa == TipoPessoa.fisica ? 'CPF' : 'CNPJ',
                  icon: Icons.credit_card,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(
                      _tipoPessoa == TipoPessoa.fisica ? 11 : 14,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildCampoTexto(
                  controller: _rgIeController,
                  label: _tipoPessoa == TipoPessoa.fisica
                      ? 'RG'
                      : 'Inscrição Estadual',
                  icon: Icons.badge,
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Contato
          _buildSecaoTitulo('Contato', Icons.phone),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildCampoTexto(
                  controller: _telefoneController,
                  label: 'Telefone Principal *',
                  icon: Icons.phone,
                  keyboardType: TextInputType.phone,
                  required: true,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildCampoTexto(
                  controller: _telefone2Controller,
                  label: 'Telefone Secundário',
                  icon: Icons.phone_android,
                  keyboardType: TextInputType.phone,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildCampoTexto(
                  controller: _whatsappController,
                  label: 'WhatsApp',
                  icon: Icons.chat,
                  keyboardType: TextInputType.phone,
                  prefixText: '+55 ',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildCampoTexto(
                  controller: _emailController,
                  label: 'E-mail',
                  icon: Icons.email,
                  keyboardType: TextInputType.emailAddress,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTabEndereco() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSecaoTitulo('Endereço', Icons.home),
          const SizedBox(height: 12),

          // CEP com busca
          Row(
            children: [
              Expanded(
                flex: 2,
                child: _buildCampoTexto(
                  controller: _cepController,
                  label: 'CEP',
                  icon: Icons.pin_drop,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(8),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 1,
                child: DropdownButtonFormField<String>(
                  value: _tipoLogradouro,
                  decoration: InputDecoration(
                    labelText: 'Tipo',
                    labelStyle: const TextStyle(color: Colors.white70),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.white, width: 2),
                    ),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.1),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  ),
                  dropdownColor: const Color(0xFF1E1E2E),
                  style: const TextStyle(color: Colors.white),
                  icon: const Icon(Icons.arrow_drop_down, color: Colors.white70),
                  items: const [
                    DropdownMenuItem(
                      value: 'Rua',
                      child: Text('Rua', style: TextStyle(color: Colors.white)),
                    ),
                    DropdownMenuItem(
                      value: 'Avenida',
                      child: Text('Avenida', style: TextStyle(color: Colors.white)),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        _tipoLogradouro = value;
                      });
                    }
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: _buildCampoTexto(
                  controller: _enderecoController,
                  label: 'Nome do Logradouro',
                  icon: Icons.location_on,
                  hintText: 'Ex: das Flores, Brasil...',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildCampoTexto(
                  controller: _numeroController,
                  label: 'Número',
                  icon: Icons.numbers,
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),
          _buildCampoTexto(
            controller: _complementoController,
            label: 'Complemento',
            icon: Icons.apartment,
            hintText: 'Apto, Bloco, Sala...',
          ),

          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildCampoTexto(
                  controller: _bairroController,
                  label: 'Bairro',
                  icon: Icons.location_city,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: _buildCampoTexto(
                  controller: _cidadeController,
                  label: 'Cidade',
                  icon: Icons.location_city,
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 100,
                child: _buildCampoTexto(
                  controller: _estadoController,
                  label: 'UF',
                  icon: Icons.map,
                  inputFormatters: [
                    LengthLimitingTextInputFormatter(2),
                    UpperCaseTextFormatter(),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),
          _buildCampoTexto(
            controller: _pontoReferenciaController,
            label: 'Ponto de Referência',
            icon: Icons.place,
            hintText: 'Próximo a...',
            maxLines: 2,
          ),
        ],
      ),
    );
  }

  Widget _buildTabAdicional() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Informações Pessoais
          if (_tipoPessoa == TipoPessoa.fisica) ...[
            _buildSecaoTitulo('Informações Pessoais', Icons.person_outline),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildCampoData(
                    label: 'Data de Nascimento',
                    value: _dataNascimento,
                    onChanged: (data) {
                      setState(() => _dataNascimento = data);
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildCampoTexto(
                    controller: _profissaoController,
                    label: 'Profissão',
                    icon: Icons.work,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
          ],

          // Crédito
          _buildSecaoTitulo('Crédito', Icons.account_balance_wallet),
          const SizedBox(height: 12),
          _buildCampoTexto(
            controller: _limiteCreditoController,
            label: 'Limite de Crédito (R\$)',
            icon: Icons.attach_money,
            keyboardType: TextInputType.numberWithOptions(decimal: true),
            prefixText: 'R\$ ',
          ),

          const SizedBox(height: 24),

          // Status
          _buildSecaoTitulo('Status', Icons.toggle_on),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text(
                    'Cliente Ativo',
                    style: TextStyle(color: Colors.white),
                  ),
                  subtitle: Text(
                    _ativo
                        ? 'Cliente disponível para vendas'
                        : 'Cliente inativo',
                    style: TextStyle(color: Colors.white.withOpacity(0.5)),
                  ),
                  value: _ativo,
                  activeThumbColor: Colors.greenAccent,
                  onChanged: (value) => setState(() => _ativo = value),
                ),
                const Divider(color: Colors.white12),
                SwitchListTile(
                  title: const Text(
                    'Bloqueado',
                    style: TextStyle(color: Colors.white),
                  ),
                  subtitle: Text(
                    _bloqueado
                        ? 'Cliente bloqueado para novas vendas'
                        : 'Sem bloqueio',
                    style: TextStyle(color: Colors.white.withOpacity(0.5)),
                  ),
                  value: _bloqueado,
                  activeThumbColor: Colors.redAccent,
                  onChanged: (value) => setState(() => _bloqueado = value),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Observações
          _buildSecaoTitulo('Observações', Icons.notes),
          const SizedBox(height: 12),
          _buildCampoTexto(
            controller: _observacoesController,
            label: 'Observações',
            icon: Icons.notes,
            maxLines: 4,
            hintText: 'Anotações sobre o cliente...',
          ),
        ],
      ),
    );
  }

  // ============ ABA PET ============
  Widget _buildTabPet() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Pets',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              ElevatedButton.icon(
                onPressed: () => _mostrarDialogAdicionarPet(),
                icon: const Icon(Icons.add),
                label: const Text('Adicionar Pet'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (_pets.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(40.0),
                child: Column(
                  children: [
                    Icon(Icons.pets, size: 64, color: Colors.white.withOpacity(0.5)),
                    const SizedBox(height: 16),
                    Text(
                      'Nenhum pet cadastrado',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.7),
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _pets.length,
              itemBuilder: (context, index) {
                final pet = _pets[index];
                return _buildCardPet(pet, index);
              },
            ),
        ],
      ),
    );
  }

  /// Widget seguro para erro no preview - NUNCA pode falhar
  Widget _buildPreviewErrorWidget([String? mensagem]) {
    try {
      return Container(
        width: 150,
        height: 150,
        decoration: BoxDecoration(
          color: Colors.orange.withOpacity(0.2),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.broken_image, size: 48, color: Colors.orange),
            const SizedBox(height: 8),
            Text(
              mensagem ?? 'Erro ao carregar foto',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      );
    } catch (e) {
      // Se até isso falhar, retornar container mínimo
      debugPrint('>>> [Preview] ❌❌❌ ERRO MUITO CRÍTICO no error widget: $e');
      return Container(
        width: 150,
        height: 150,
        color: Colors.red.withOpacity(0.1),
      );
    }
  }

  Widget _buildCardPet(Pet pet, int index) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: const Color(0xFF2C2C3E),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: pet.fotoPath != null
            ? (() {
                try {
                  final fotoPath = pet.fotoPath!;
                  
                  // Verificar se é URL (HTTP, HTTPS, blob ou data URL)
                  if (fotoPath.startsWith('http://') || 
                      fotoPath.startsWith('https://') || 
                      fotoPath.startsWith('blob:') ||
                      fotoPath.startsWith('data:image')) {
                    // URL do Firebase, blob URL ou data URL (web)
                    String imageUrl = fotoPath;
                    if (imageUrl.startsWith('https://') && !imageUrl.contains('?')) {
                      // Adicionar timestamp para forçar reload (cache busting)
                      imageUrl = '$imageUrl?t=${pet.updatedAt.millisecondsSinceEpoch}';
                    }
                    debugPrint('>>> [Exibir Imagem Pet] Carregando URL: ${fotoPath.startsWith('data:') ? 'data:image...' : imageUrl}');
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: _ImageNetworkWithTimeout(
                        imageUrl: imageUrl,
                        width: 60,
                        height: 60,
                        fit: BoxFit.cover,
                      ),
                    );
                  } else if (!kIsWeb) {
                    // Caminho local apenas para mobile/desktop (não web)
                    final file = File(fotoPath);
                    // Verificar se arquivo existe antes de tentar carregar
                    if (file.existsSync()) {
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(
                          file,
                          width: 60,
                          height: 60,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            debugPrint('>>> Erro ao carregar foto do pet: $error');
                            return Container(
                              width: 60,
                              height: 60,
                              decoration: BoxDecoration(
                                color: Colors.blue.withOpacity(0.3),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.pets, color: Colors.white70, size: 32),
                            );
                          },
                        ),
                      );
                    } else {
                      debugPrint('>>> Arquivo de foto não existe: $fotoPath');
                      return Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.pets, color: Colors.white70, size: 32),
                      );
                    }
                  } else {
                    // Web com caminho local (não suportado)
                    debugPrint('>>> [Web] Caminho local não suportado: $fotoPath');
                    return Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.pets, color: Colors.white70, size: 32),
                    );
                  }
                } catch (e) {
                  debugPrint('>>> Erro ao carregar foto do pet: $e');
                }
                return Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.pets, color: Colors.white70, size: 32),
                );
              })()
            : Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.pets, color: Colors.white70, size: 32),
              ),
        title: Text(
          pet.nome,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (pet.especie != null) Text('${pet.especie}${pet.raca != null ? ' - ${pet.raca}' : ''}', style: const TextStyle(color: Colors.white70)),
            if (pet.tamanho != null || pet.peso != null)
              Text(
                [
                  if (pet.tamanho != null) pet.tamanho!,
                  if (pet.peso != null) '${pet.peso}kg',
                ].join(' • '),
                style: const TextStyle(color: Colors.white70),
              ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit, color: Colors.blue),
              onPressed: () => _mostrarDialogEditarPet(index),
            ),
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              onPressed: () => _confirmarExclusaoPet(index),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _mostrarDialogAdicionarPet() async {
    await _mostrarDialogPet();
  }

  Future<void> _mostrarDialogEditarPet(int index) async {
    await _mostrarDialogPet(petExistente: _pets[index], index: index);
  }

  Future<void> _mostrarDialogPet({Pet? petExistente, int? index}) async {
    final nomeController = TextEditingController(text: petExistente?.nome ?? '');
    final especieController = TextEditingController(text: petExistente?.especie ?? '');
    final racaController = TextEditingController(text: petExistente?.raca ?? '');
    final tamanhoController = TextEditingController(text: petExistente?.tamanho ?? '');
    final pesoController = TextEditingController(text: petExistente?.peso?.toString() ?? '');
    final corController = TextEditingController(text: petExistente?.cor ?? '');
    final observacoesController = TextEditingController(text: petExistente?.observacoes ?? '');
    
    String? fotoPath = petExistente?.fotoPath;
    DateTime? dataNascimento = petExistente?.dataNascimento;
    String? sexo = petExistente?.sexo;

    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => Dialog(
          backgroundColor: const Color(0xFF1E1E2E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Container(
            width: MediaQuery.of(context).size.width * 0.95,
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.9,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Cabeçalho
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.2),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.pets, color: Colors.orange, size: 28),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          petExistente != null ? 'Editar Pet' : 'Novo Pet',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white70),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
                // Conteúdo
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Foto do pet
                        Center(
                          child: GestureDetector(
                            onTap: () async {
                              // No desktop/PC, usar file_picker que funciona melhor
                              // No web, também usar file_picker mas com withData para obter bytes diretamente
                              if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
                                try {
                                  FilePickerResult? result = await FilePicker.platform.pickFiles(
                                    type: FileType.image,
                                    allowMultiple: false,
                                  );
                                  
                                  if (result != null && result.files.isNotEmpty) {
                                    final selectedFile = result.files.single;
                                    debugPrint('>>> [FilePicker] Arquivo selecionado:');
                                    debugPrint('>>> [FilePicker] Nome: ${selectedFile.name}');
                                    debugPrint('>>> [FilePicker] Tamanho: ${selectedFile.size} bytes');
                                    debugPrint('>>> [FilePicker] Path: ${selectedFile.path}');
                                    debugPrint('>>> [FilePicker] Bytes disponíveis: ${selectedFile.bytes != null}');
                                    
                                    try {
                                      String? caminhoFinal;
                                      
                                      // Tentar usar bytes diretamente se disponível (mais confiável)
                                      if (selectedFile.bytes != null && selectedFile.bytes!.isNotEmpty) {
                                        final bytes = selectedFile.bytes!;
                                        debugPrint('>>> [FilePicker] Usando bytes diretamente: ${bytes.length} bytes');
                                        
                                        // Salvar bytes em arquivo permanente
                                        final appDir = await getApplicationDocumentsDirectory();
                                        final fotosDir = Directory('${appDir.path}/fotos_pets');
                                        if (!await fotosDir.exists()) {
                                          await fotosDir.create(recursive: true);
                                        }
                                        
                                        // Detectar extensão pelo nome ou usar .jpg como padrão
                                        String extension = path.extension(selectedFile.name).toLowerCase();
                                        if (extension.isEmpty || extension == '.') {
                                          // Tentar detectar pelo conteúdo (primeiros bytes)
                                          if (bytes.length >= 4) {
                                            // PNG: 89 50 4E 47
                                            if (bytes[0] == 0x89 && bytes[1] == 0x50 && 
                                                bytes[2] == 0x4E && bytes[3] == 0x47) {
                                              extension = '.png';
                                            }
                                            // JPEG: FF D8 FF
                                            else if (bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
                                              extension = '.jpg';
                                            }
                                            // GIF: 47 49 46 38
                                            else if (bytes[0] == 0x47 && bytes[1] == 0x49 && 
                                                     bytes[2] == 0x46 && bytes[3] == 0x38) {
                                              extension = '.gif';
                                            }
                                            // WebP: RIFF...WEBP
                                            else if (bytes.length >= 12 && 
                                                     String.fromCharCodes(bytes.sublist(0, 4)) == 'RIFF' &&
                                                     String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP') {
                                              extension = '.webp';
                                            } else {
                                              extension = '.jpg'; // Padrão
                                            }
                                          } else {
                                            extension = '.jpg';
                                          }
                                        }
                                        
                                        final nomeArquivo = 'pet_${DateTime.now().millisecondsSinceEpoch}$extension';
                                        final destinoFile = File('${fotosDir.path}/$nomeArquivo');
                                        
                                        // Salvar bytes no arquivo
                                        await destinoFile.writeAsBytes(bytes);
                                        caminhoFinal = destinoFile.path;
                                        debugPrint('>>> [FilePicker] Foto salva em: $caminhoFinal');
                                      } 
                                      // Se não tiver bytes, usar path
                                      else if (selectedFile.path != null && selectedFile.path!.isNotEmpty) {
                                        final sourceFile = File(selectedFile.path!);
                                        if (await sourceFile.exists()) {
                                          debugPrint('>>> [FilePicker] Usando path: ${selectedFile.path}');
                                          
                                          // Copiar arquivo para diretório permanente
                                          final appDir = await getApplicationDocumentsDirectory();
                                          final fotosDir = Directory('${appDir.path}/fotos_pets');
                                          if (!await fotosDir.exists()) {
                                            await fotosDir.create(recursive: true);
                                          }
                                          
                                          final extension = path.extension(selectedFile.path!).toLowerCase();
                                          final nomeArquivo = 'pet_${DateTime.now().millisecondsSinceEpoch}${extension.isEmpty ? '.jpg' : extension}';
                                          final destinoFile = File('${fotosDir.path}/$nomeArquivo');
                                          
                                          // Copiar arquivo
                                          await sourceFile.copy(destinoFile.path);
                                          caminhoFinal = destinoFile.path;
                                          debugPrint('>>> [FilePicker] Foto copiada para: $caminhoFinal');
                                        } else {
                                          throw Exception('Arquivo não existe: ${selectedFile.path}');
                                        }
                                      } else {
                                        throw Exception('Nenhum caminho ou bytes disponíveis no arquivo selecionado');
                                      }
                                      
                                      // Verificar se arquivo foi salvo corretamente
                                      final fileVerificacao = File(caminhoFinal);
                                      if (await fileVerificacao.exists()) {
                                        final tamanho = await fileVerificacao.length();
                                        debugPrint('>>> [FilePicker] Arquivo verificado: $caminhoFinal (${tamanho} bytes)');
                                        
                                        setStateDialog(() {
                                          fotoPath = caminhoFinal;
                                        });
                                        
                                        if (mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(
                                              content: Text('Foto selecionada e salva com sucesso! (${(tamanho / 1024).toStringAsFixed(1)} KB)'),
                                              backgroundColor: Colors.green,
                                              duration: const Duration(seconds: 2),
                                            ),
                                          );
                                        }
                                      } else {
                                        throw Exception('Arquivo não foi salvo corretamente em: $caminhoFinal');
                                      }
                                    } catch (e, stackTrace) {
                                      debugPrint('>>> [FilePicker] Erro ao processar foto: $e');
                                      debugPrint('>>> [FilePicker] StackTrace: $stackTrace');
                                      if (mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text('Erro ao processar foto: $e'),
                                            backgroundColor: Colors.red,
                                            duration: const Duration(seconds: 4),
                                          ),
                                        );
                                      }
                                    }
                                  }
                                } catch (e) {
                                  debugPrint('>>> Erro ao selecionar foto: $e');
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('Erro ao selecionar foto: $e'),
                                        backgroundColor: Colors.red,
                                      ),
                                    );
                                  }
                                }
                              } else if (kIsWeb) {
                                // No web/Chrome, usar FilePicker com withData para obter bytes diretamente
                                // Isso evita problemas com blob URLs que expiram rapidamente
                                try {
                                  debugPrint('>>> [Web/Chrome] Usando FilePicker com withData');
                                  FilePickerResult? result = await FilePicker.platform.pickFiles(
                                    type: FileType.image,
                                    withData: true, // IMPORTANTE: Obter bytes diretamente
                                    allowMultiple: false,
                                  );
                                  
                                  if (result != null && result.files.isNotEmpty) {
                                    final selectedFile = result.files.first;
                                    
                                    if (selectedFile.bytes != null && selectedFile.bytes!.isNotEmpty) {
                                      debugPrint('>>> [Web/Chrome] ✅ Bytes obtidos: ${selectedFile.bytes!.length} bytes');
                                      
                                      // Usar ImageUploadService.uploadImageFromBytes para fazer upload direto
                                      // Isso evita problemas com blob URLs que expiram
                                      if (widget.cliente != null) {
                                        final petId = petExistente?.id ?? DateTime.now().millisecondsSinceEpoch.toString();
                                        final empresaId = Provider.of<DataService>(context, listen: false).empresaIdAtual;
                                        
                                        if (empresaId != null) {
                                          // Fazer upload IMEDIATAMENTE usando bytes
                                          debugPrint('>>> [Web/Chrome] Fazendo upload IMEDIATO dos bytes...');
                                          final progressNotifier = ValueNotifier<double>(0.0);
                                          
                                          // Mostrar progresso
                                          showDialog(
                                            context: context,
                                            barrierDismissible: false,
                                            builder: (context) => AlertDialog(
                                              backgroundColor: const Color(0xFF1E1E2E),
                                              content: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  const CircularProgressIndicator(),
                                                  const SizedBox(height: 16),
                                                  ValueListenableBuilder<double>(
                                                    valueListenable: progressNotifier,
                                                    builder: (context, progress, _) {
                                                      return Text(
                                                        'Fazendo upload... ${(progress * 100).toStringAsFixed(0)}%',
                                                        style: const TextStyle(color: Colors.white),
                                                      );
                                                    },
                                                  ),
                                                ],
                                              ),
                                            ),
                                          );
                                          
                                          String? url;
                                          try {
                                            // Usar armazenamento GRATUITO no Firestore
                                            progressNotifier.value = 0.3;
                                            final pet = widget.cliente!.pets.firstWhere(
                                              (p) => p.id == petId,
                                              orElse: () => Pet(
                                                id: petId,
                                                nome: 'Pet',
                                                especie: '',
                                                raca: '',
                                                dataNascimento: DateTime.now(),
                                                createdAt: DateTime.now(),
                                                updatedAt: DateTime.now(),
                                              ),
                                            );
                                            
                                            url = await ImageStorageService.salvarImagemERetornarUrl(
                                              imageBytes: selectedFile.bytes!,
                                              empresaId: empresaId,
                                              categoria: 'pets',
                                              nome: '${pet.nome} - ${widget.cliente!.nome}',
                                              metadata: {
                                                'pet_id': petId,
                                                'cliente_id': widget.cliente!.id,
                                                'empresa_id': empresaId,
                                              },
                                            ).timeout(
                                              const Duration(seconds: 30),
                                              onTimeout: () {
                                                debugPrint('>>> [Web/Chrome] ⚠️ Timeout no upload após 30 segundos');
                                                if (mounted) Navigator.pop(context);
                                                return null;
                                              },
                                            );
                                            
                                            progressNotifier.value = 1.0;
                                          } catch (e, stackTrace) {
                                            debugPrint('>>> [Web/Chrome] ❌ Erro durante upload: $e');
                                            debugPrint('>>> [Web/Chrome] StackTrace: $stackTrace');
                                            url = null;
                                          } finally {
                                            // GARANTIR que o diálogo seja fechado sempre
                                            if (mounted) {
                                              try {
                                                Navigator.pop(context);
                                              } catch (e) {
                                                debugPrint('>>> [Web/Chrome] Erro ao fechar diálogo: $e');
                                              }
                                            }
                                          }
                                          
                                          if (url != null && url.isNotEmpty) {
                                            debugPrint('>>> [Web/Chrome] ✅ Upload concluído: $url');
                                            setStateDialog(() {
                                              fotoPath = url;
                                            });
                                            if (mounted) {
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                const SnackBar(
                                                  content: Text('Foto enviada com sucesso!'),
                                                  backgroundColor: Colors.green,
                                                ),
                                              );
                                            }
                                          } else {
                                            debugPrint('>>> [Web/Chrome] ❌ Upload falhou - URL é null ou vazia');
                                            if (mounted) {
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                const SnackBar(
                                                  content: Text('Erro ao enviar foto. Verifique se o Firebase Storage está configurado corretamente.'),
                                                  backgroundColor: Colors.red,
                                                  duration: Duration(seconds: 5),
                                                ),
                                              );
                                            }
                                          }
                                        }
                                      }
                                    } else {
                                      throw Exception('Não foi possível obter bytes do arquivo');
                                    }
                                  }
                                } catch (e) {
                                  debugPrint('>>> [Web/Chrome] Erro ao selecionar foto: $e');
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('Erro ao selecionar foto: $e'),
                                        backgroundColor: Colors.red,
                                      ),
                                    );
                                  }
                                }
                              } else {
                                // No mobile, usar image_picker
                                final action = await showDialog<String>(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    backgroundColor: const Color(0xFF1E1E2E),
                                    title: const Text('Selecionar foto', style: TextStyle(color: Colors.white)),
                                    content: const Text('Escolha a origem da foto', style: TextStyle(color: Colors.white70)),
                                    actions: [
                                      TextButton.icon(
                                        onPressed: () => Navigator.pop(context, 'galeria'),
                                        icon: const Icon(Icons.photo_library),
                                        label: const Text('Galeria'),
                                      ),
                                      TextButton.icon(
                                        onPressed: () => Navigator.pop(context, 'camera'),
                                        icon: const Icon(Icons.camera_alt),
                                        label: const Text('Câmera'),
                                      ),
                                      TextButton(
                                        onPressed: () => Navigator.pop(context),
                                        child: const Text('Cancelar'),
                                      ),
                                    ],
                                  ),
                                );
                                
                                if (action != null) {
                                  try {
                                    final XFile? image = await _imagePicker.pickImage(
                                      source: action == 'camera' ? ImageSource.camera : ImageSource.gallery,
                                      maxWidth: 800,
                                      maxHeight: 800,
                                      imageQuality: 85,
                                    );
                                    if (image != null) {
                                      setStateDialog(() {
                                        fotoPath = image.path;
                                      });
                                    }
                                  } catch (e) {
                                    if (mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text('Erro ao selecionar foto: $e'),
                                          backgroundColor: Colors.red,
                                        ),
                                      );
                                    }
                                  }
                                }
                              }
                            },
                            child: Container(
                              width: 150,
                              height: 150,
                              decoration: BoxDecoration(
                                color: Colors.orange.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: Colors.orange.withOpacity(0.5), width: 2),
                              ),
                              child: fotoPath != null && fotoPath!.isNotEmpty
                                  ? Builder(
                                      key: ValueKey(fotoPath), // Key única para forçar rebuild quando foto mudar
                                      builder: (context) {
                                        try {
                                          debugPrint('>>> [Preview] Tentando exibir foto: $fotoPath');
                                          
                                          // Verificar se é URL (HTTP, HTTPS ou blob)
                                          if (fotoPath!.startsWith('http://') || 
                                              fotoPath!.startsWith('https://') || 
                                              fotoPath!.startsWith('blob:')) {
                                            // URL do Firebase ou blob URL (web)
                                            try {
                                              debugPrint('>>> [Preview] É URL (${fotoPath!.startsWith('blob:') ? 'blob' : 'http/https'}), usando Image.network');
                                              // Adicionar cache busting para forçar reload quando a URL mudar
                                              String imageUrl = fotoPath!;
                                              if (imageUrl.startsWith('https://') && !imageUrl.contains('?')) {
                                                // Adicionar timestamp para forçar reload (cache busting)
                                                imageUrl = '$imageUrl?t=${DateTime.now().millisecondsSinceEpoch}';
                                              }
                                              return ClipRRect(
                                                borderRadius: BorderRadius.circular(14),
                                                child: Stack(
                                                  fit: StackFit.expand,
                                                  children: [
                                                    Image.network(
                                                      imageUrl,
                                                      fit: BoxFit.cover,
                                                      width: 150,
                                                      height: 150,
                                                      cacheWidth: 150,
                                                      cacheHeight: 150,
                                                      loadingBuilder: (context, child, loadingProgress) {
                                                        try {
                                                          if (loadingProgress == null) return child;
                                                          return Container(
                                                            color: Colors.orange.withOpacity(0.2),
                                                            child: Center(
                                                              child: CircularProgressIndicator(
                                                                value: loadingProgress.expectedTotalBytes != null
                                                                    ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                                                                    : null,
                                                                color: Colors.orange,
                                                              ),
                                                            ),
                                                          );
                                                        } catch (e) {
                                                          debugPrint('>>> [Preview] Erro no loadingBuilder: $e');
                                                          return Container(color: Colors.orange.withOpacity(0.2));
                                                        }
                                                      },
                                                      errorBuilder: (context, error, stackTrace) {
                                                        try {
                                                          debugPrint('>>> [Preview] Erro ao carregar foto da URL: $error');
                                                          return _buildPreviewErrorWidget();
                                                        } catch (e) {
                                                          debugPrint('>>> [Preview] ❌ Erro no errorBuilder: $e');
                                                          return Container(color: Colors.red.withOpacity(0.2));
                                                        }
                                                      },
                                                    ),
                                                    Positioned(
                                                      bottom: 8,
                                                      right: 8,
                                                      child: Container(
                                                        padding: const EdgeInsets.all(6),
                                                        decoration: BoxDecoration(
                                                          color: Colors.black.withOpacity(0.6),
                                                          borderRadius: BorderRadius.circular(20),
                                                        ),
                                                        child: const Icon(Icons.edit, color: Colors.white, size: 18),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              );
                                            } catch (e, stackTrace) {
                                              debugPrint('>>> [Preview] ❌ Erro ao processar URL: $e');
                                              debugPrint('>>> [Preview] StackTrace: $stackTrace');
                                              return _buildPreviewErrorWidget();
                                            }
                                          } else if (fotoPath != null && fotoPath!.startsWith('data:image')) {
                                            // Data URL (usado pelo ImageStorageService)
                                            try {
                                              final dataUrl = fotoPath!;
                                              debugPrint('>>> [Preview] É data URL, usando Image.network');
                                              return ClipRRect(
                                                borderRadius: BorderRadius.circular(14),
                                                child: Stack(
                                                  fit: StackFit.expand,
                                                  children: [
                                                    Image.network(
                                                      dataUrl,
                                                      fit: BoxFit.cover,
                                                      width: 150,
                                                      height: 150,
                                                      errorBuilder: (context, error, stackTrace) {
                                                        try {
                                                          debugPrint('>>> [Preview] Erro ao carregar data URL: $error');
                                                          return _buildPreviewErrorWidget();
                                                        } catch (e) {
                                                          debugPrint('>>> [Preview] ❌ Erro no errorBuilder: $e');
                                                          return Container(color: Colors.red.withOpacity(0.2));
                                                        }
                                                      },
                                                    ),
                                                    Positioned(
                                                      bottom: 8,
                                                      right: 8,
                                                      child: Container(
                                                        padding: const EdgeInsets.all(6),
                                                        decoration: BoxDecoration(
                                                          color: Colors.black.withOpacity(0.6),
                                                          borderRadius: BorderRadius.circular(20),
                                                        ),
                                                        child: const Icon(Icons.edit, color: Colors.white, size: 18),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              );
                                            } catch (e, stackTrace) {
                                              debugPrint('>>> [Preview] ❌ Erro ao processar data URL: $e');
                                              debugPrint('>>> [Preview] StackTrace: $stackTrace');
                                              return _buildPreviewErrorWidget();
                                            }
                                          } else if (!kIsWeb && fotoPath != null) {
                                            // Caminho local apenas para mobile/desktop (não web)
                                            try {
                                              debugPrint('>>> [Preview] É caminho local, usando Image.file: $fotoPath');
                                              final file = File(fotoPath!);
                                              // Verificar se arquivo existe
                                              if (file.existsSync()) {
                                                return ClipRRect(
                                                  borderRadius: BorderRadius.circular(14),
                                                  child: Stack(
                                                    fit: StackFit.expand,
                                                    children: [
                                                      Image.file(
                                                        file,
                                                        key: ValueKey('${fotoPath}_${DateTime.now().millisecondsSinceEpoch}'),
                                                        fit: BoxFit.cover,
                                                        width: 150,
                                                        height: 150,
                                                        errorBuilder: (context, error, stackTrace) {
                                                          try {
                                                            debugPrint('>>> [Preview] Erro ao carregar arquivo local: $error');
                                                            return _buildPreviewErrorWidget();
                                                          } catch (e) {
                                                            debugPrint('>>> [Preview] ❌ Erro no errorBuilder: $e');
                                                            return Container(color: Colors.red.withOpacity(0.2));
                                                          }
                                                        },
                                                      ),
                                                      Positioned(
                                                        bottom: 8,
                                                        right: 8,
                                                        child: Container(
                                                          padding: const EdgeInsets.all(6),
                                                          decoration: BoxDecoration(
                                                            color: Colors.black.withOpacity(0.6),
                                                            borderRadius: BorderRadius.circular(20),
                                                          ),
                                                          child: const Icon(Icons.edit, color: Colors.white, size: 18),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                );
                                              } else {
                                                debugPrint('>>> [Preview] Arquivo não existe: $fotoPath');
                                                return _buildPreviewErrorWidget('Arquivo não encontrado');
                                              }
                                            } catch (e, stackTrace) {
                                              debugPrint('>>> [Preview] ❌ Erro ao processar arquivo: $e');
                                              debugPrint('>>> [Preview] StackTrace: $stackTrace');
                                              return _buildPreviewErrorWidget();
                                            }
                                          } else {
                                            // Web com caminho local (não suportado)
                                            debugPrint('>>> [Preview] Web não suporta arquivo local: $fotoPath');
                                            return Column(
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: [
                                                const Icon(Icons.add_a_photo, size: 48, color: Colors.orange),
                                                const SizedBox(height: 8),
                                                Text(
                                                  'Adicionar foto',
                                                  style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12),
                                                ),
                                              ],
                                            );
                                          }
                                        } catch (e, stackTrace) {
                                          debugPrint('>>> [Preview] Erro ao carregar foto do pet: $e');
                                          debugPrint('>>> [Preview] StackTrace: $stackTrace');
                                          return Column(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              const Icon(Icons.add_a_photo, size: 48, color: Colors.orange),
                                              const SizedBox(height: 8),
                                              Text(
                                                'Adicionar foto',
                                                style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12),
                                              ),
                                            ],
                                          );
                                        }
                                      },
                                    )
                                  : Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        const Icon(Icons.add_a_photo, size: 48, color: Colors.orange),
                                        const SizedBox(height: 8),
                                        Text(
                                          'Adicionar foto',
                                          style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12),
                                        ),
                                      ],
                                    ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        
                        // Dados básicos
                        _buildSecaoTitulo('Dados Básicos', Icons.info),
                        const SizedBox(height: 12),
                        _buildCampoTexto(
                          controller: nomeController,
                          label: 'Nome do Pet *',
                          icon: Icons.pets,
                          required: true,
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: _buildCampoTexto(
                                controller: especieController,
                                label: 'Espécie',
                                icon: Icons.category,
                                hintText: 'Ex: Cachorro, Gato',
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildCampoTexto(
                                controller: racaController,
                                label: 'Raça',
                                icon: Icons.pets,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        
                        // Características físicas
                        _buildSecaoTitulo('Características', Icons.straighten),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _buildCampoTexto(
                                controller: tamanhoController,
                                label: 'Tamanho',
                                icon: Icons.height,
                                hintText: 'Ex: Pequeno, Médio, Grande',
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildCampoTexto(
                                controller: pesoController,
                                label: 'Peso (kg)',
                                icon: Icons.monitor_weight,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: _buildCampoTexto(
                                controller: corController,
                                label: 'Cor',
                                icon: Icons.palette,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildCampoData(
                                label: 'Data de Nascimento',
                                value: dataNascimento,
                                onChanged: (date) => setStateDialog(() => dataNascimento = date),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<String>(
                          value: sexo,
                          decoration: InputDecoration(
                            labelText: 'Sexo',
                            labelStyle: const TextStyle(color: Colors.white70),
                            prefixIcon: const Icon(Icons.wc, color: Colors.white54),
                            filled: true,
                            fillColor: const Color(0xFF181A1B),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: Colors.orange, width: 2),
                            ),
                          ),
                          dropdownColor: const Color(0xFF23272A),
                          style: const TextStyle(color: Colors.white),
                          items: const [
                            DropdownMenuItem(value: null, child: Text('Não informado', style: TextStyle(color: Colors.white70))),
                            DropdownMenuItem(value: 'M', child: Text('Macho', style: TextStyle(color: Colors.white))),
                            DropdownMenuItem(value: 'F', child: Text('Fêmea', style: TextStyle(color: Colors.white))),
                          ],
                          onChanged: (value) => setStateDialog(() => sexo = value),
                        ),
                        const SizedBox(height: 24),
                        
                        // Observações
                        _buildSecaoTitulo('Observações', Icons.notes),
                        const SizedBox(height: 12),
                        _buildCampoTexto(
                          controller: observacoesController,
                          label: 'Observações',
                          icon: Icons.notes,
                          maxLines: 4,
                          hintText: 'Informações adicionais sobre o pet...',
                        ),
                      ],
                    ),
                  ),
                ),
                // Botões
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.3),
                    borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            nomeController.dispose();
                            especieController.dispose();
                            racaController.dispose();
                            tamanhoController.dispose();
                            pesoController.dispose();
                            corController.dispose();
                            observacoesController.dispose();
                            Navigator.pop(context);
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white70,
                            side: const BorderSide(color: Colors.white24),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text('Cancelar'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton.icon(
                          onPressed: _uploadingFoto ? null : () async {
                            if (nomeController.text.trim().isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Nome do pet é obrigatório'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                              return;
                            }
                            
                            // Mostrar loading com feedback de progresso
                            final progressNotifier = ValueNotifier<double>(0.0);
                            
                            showDialog(
                              context: context,
                              barrierDismissible: false,
                              builder: (ctx) {
                                return ValueListenableBuilder<double>(
                                  valueListenable: progressNotifier,
                                  builder: (context, progress, _) {
                                    return AlertDialog(
                                      backgroundColor: const Color(0xFF1E1E2E),
                                      title: const Text(
                                        'Salvando pet...',
                                        style: TextStyle(color: Colors.white),
                                      ),
                                      content: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (fotoPath != null && fotoPath!.isNotEmpty) ...[
                                            const Text(
                                              'Enviando foto para o servidor...',
                                              style: TextStyle(color: Colors.white70, fontSize: 12),
                                              textAlign: TextAlign.center,
                                            ),
                                            const SizedBox(height: 16),
                                            if (progress > 0 && progress < 1) ...[
                                              LinearProgressIndicator(
                                                value: progress,
                                                backgroundColor: Colors.white24,
                                                valueColor: const AlwaysStoppedAnimation<Color>(Colors.orange),
                                              ),
                                              const SizedBox(height: 8),
                                              Text(
                                                '${(progress * 100).toStringAsFixed(0)}%',
                                                style: const TextStyle(color: Colors.white70, fontSize: 11),
                                              ),
                                            ] else ...[
                                              const CircularProgressIndicator(color: Colors.orange),
                                            ],
                                            const SizedBox(height: 8),
                                            const Text(
                                              'Aguarde, isso pode levar alguns segundos...',
                                              style: TextStyle(color: Colors.white54, fontSize: 11),
                                              textAlign: TextAlign.center,
                                            ),
                                          ] else ...[
                                            const CircularProgressIndicator(color: Colors.orange),
                                          ],
                                        ],
                                      ),
                                    );
                                  },
                                );
                              },
                            );
                            
                            try {
                              String? fotoPathFinal = fotoPath;
                              
                              // Fazer upload da foto se houver (sempre para blob URLs e caminhos locais)
                              if (fotoPath != null && fotoPath!.isNotEmpty && widget.cliente != null) {
                                try {
                                  final petId = petExistente?.id ?? DateTime.now().millisecondsSinceEpoch.toString();
                                  debugPrint('>>> [Salvar Pet] Iniciando upload da foto do pet: $petId');
                                  debugPrint('>>> [Salvar Pet] Caminho/URL: $fotoPath');
                                  
                                  // Se já é uma URL HTTPS do Firebase, verificar se está acessível
                                  if (fotoPath!.startsWith('https://')) {
                                    debugPrint('>>> [Salvar Pet] Verificando URL do Firebase: $fotoPath');
                                    try {
                                      final testResponse = await http.head(Uri.parse(fotoPath!)).timeout(
                                        const Duration(seconds: 5),
                                      );
                                      if (testResponse.statusCode == 200) {
                                        debugPrint('>>> [Salvar Pet] ✅ URL verificada e acessível');
                                        fotoPathFinal = fotoPath;
                                      } else {
                                        debugPrint('>>> [Salvar Pet] ⚠️ URL retornou status ${testResponse.statusCode}, tentando upload novamente');
                                        fotoPathFinal = await _uploadFotoPet(
                                          fotoPath!,
                                          petId,
                                          widget.cliente!.id,
                                          onProgress: (progress) {
                                            progressNotifier.value = progress;
                                          },
                                        ).timeout(
                                          const Duration(seconds: 150),
                                          onTimeout: () {
                                            debugPrint('>>> [Salvar Pet] Timeout no upload');
                                            return null;
                                          },
                                        );
                                      }
                                    } catch (e) {
                                      debugPrint('>>> [Salvar Pet] ⚠️ Erro ao verificar URL: $e, tentando upload');
                                      fotoPathFinal = await _uploadFotoPet(
                                        fotoPath!,
                                        petId,
                                        widget.cliente!.id,
                                        onProgress: (progress) {
                                          progressNotifier.value = progress;
                                        },
                                      ).timeout(
                                        const Duration(seconds: 150),
                                        onTimeout: () {
                                          debugPrint('>>> [Salvar Pet] Timeout no upload');
                                          return null;
                                        },
                                      );
                                    }
                                  } else {
                                    // Fazer upload (converte blob URLs e arquivos locais para Firebase Storage)
                                    fotoPathFinal = await _uploadFotoPet(
                                      fotoPath!,
                                      petId,
                                      widget.cliente!.id,
                                      onProgress: (progress) {
                                        progressNotifier.value = progress;
                                      },
                                    ).timeout(
                                      const Duration(seconds: 150), // Timeout total aumentado para 2.5 minutos
                                      onTimeout: () {
                                        debugPrint('>>> [Salvar Pet] Timeout total no upload');
                                        return null;
                                      },
                                    );
                                    debugPrint('>>> [Salvar Pet] Resultado do upload: $fotoPathFinal');
                                    
                                    if (fotoPathFinal == null) {
                                      debugPrint('>>> [Salvar Pet] ⚠️ Upload falhou ou foi cancelado');
                                      // Se for arquivo local (não web), manter o caminho local
                                      if (!kIsWeb && fotoPath != null && !fotoPath!.startsWith('http') && !fotoPath!.startsWith('blob:')) {
                                        final file = File(fotoPath!);
                                        if (await file.exists()) {
                                          debugPrint('>>> [Salvar Pet] ✅ Mantendo caminho local: $fotoPath');
                                          fotoPathFinal = fotoPath; // Manter caminho local
                                        } else {
                                          debugPrint('>>> [Salvar Pet] ❌ Arquivo local não existe mais: $fotoPath');
                                          fotoPathFinal = null;
                                        }
                                      } else {
                                        debugPrint('>>> [Salvar Pet] Não é possível manter caminho local (web/blob) - continuando sem foto');
                                        fotoPathFinal = null; // Não salvar caminho inválido
                                      }
                                    }
                                  }
                                } catch (e, stackTrace) {
                                  debugPrint('>>> [Salvar Pet] Erro no upload da foto: $e');
                                  debugPrint('>>> [Salvar Pet] StackTrace: $stackTrace');
                                  // Se upload falhar, não salvar foto (melhor do que salvar caminho inválido)
                                  fotoPathFinal = null;
                                }
                              }
                              
                              // VALIDAÇÃO: Verificar se fotoPathFinal foi definido corretamente
                              if (fotoPathFinal == null && fotoPath != null && fotoPath!.isNotEmpty) {
                                debugPrint('>>> [Salvar Pet] ⚠️ ATENÇÃO: fotoPathFinal é null mas fotoPath não é vazio');
                                debugPrint('>>> [Salvar Pet] fotoPath original: $fotoPath');
                                debugPrint('>>> [Salvar Pet] Isso pode indicar que o upload falhou silenciosamente');
                              }
                              
                              debugPrint('>>> [Salvar Pet] Criando objeto Pet com fotoPathFinal: $fotoPathFinal');
                              
                              final pet = Pet(
                                id: petExistente?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
                                nome: nomeController.text.trim(),
                                especie: especieController.text.trim().isEmpty ? null : especieController.text.trim(),
                                raca: racaController.text.trim().isEmpty ? null : racaController.text.trim(),
                                tamanho: tamanhoController.text.trim().isEmpty ? null : tamanhoController.text.trim(),
                                peso: pesoController.text.trim().isEmpty ? null : double.tryParse(pesoController.text.replaceAll(',', '.')),
                                cor: corController.text.trim().isEmpty ? null : corController.text.trim(),
                                sexo: sexo,
                                dataNascimento: dataNascimento,
                                observacoes: observacoesController.text.trim().isEmpty ? null : observacoesController.text.trim(),
                                fotoPath: fotoPathFinal,
                                createdAt: petExistente?.createdAt ?? DateTime.now(),
                                updatedAt: DateTime.now(),
                              );
                              
                              debugPrint('>>> [Salvar Pet] Pet criado com fotoPath: ${pet.fotoPath}');
                              
                              setState(() {
                                if (index != null) {
                                  _pets[index] = pet;
                                } else {
                                  _pets.add(pet);
                                }
                              });
                              
                              // Salvar o cliente no Firebase após atualizar o pet
                              if (widget.cliente != null) {
                                try {
                                  final dataService = Provider.of<DataService>(context, listen: false);
                                  final clienteAtualizado = Cliente(
                                    id: widget.cliente!.id,
                                    nome: widget.cliente!.nome,
                                    nomeFantasia: widget.cliente!.nomeFantasia,
                                    tipoPessoa: widget.cliente!.tipoPessoa,
                                    cpfCnpj: widget.cliente!.cpfCnpj,
                                    rgIe: widget.cliente!.rgIe,
                                    email: widget.cliente!.email,
                                    telefone: widget.cliente!.telefone,
                                    telefone2: widget.cliente!.telefone2,
                                    whatsapp: widget.cliente!.whatsapp,
                                    endereco: widget.cliente!.endereco,
                                    numero: widget.cliente!.numero,
                                    complemento: widget.cliente!.complemento,
                                    bairro: widget.cliente!.bairro,
                                    cidade: widget.cliente!.cidade,
                                    estado: widget.cliente!.estado,
                                    cep: widget.cliente!.cep,
                                    pontoReferencia: widget.cliente!.pontoReferencia,
                                    dataNascimento: widget.cliente!.dataNascimento,
                                    profissao: widget.cliente!.profissao,
                                    observacoes: widget.cliente!.observacoes,
                                    pets: _pets,
                                    limiteCredito: widget.cliente!.limiteCredito,
                                    bloqueado: widget.cliente!.bloqueado,
                                    ativo: widget.cliente!.ativo,
                                    createdAt: widget.cliente!.createdAt,
                                    updatedAt: DateTime.now(),
                                  );
                                  dataService.updateCliente(clienteAtualizado);
                                  debugPrint('>>> [Salvar Pet] Cliente atualizado no Firebase com a nova foto do pet');
                                } catch (e) {
                                  debugPrint('>>> [Salvar Pet] Erro ao salvar cliente no Firebase: $e');
                                }
                              }
                              
                              nomeController.dispose();
                              especieController.dispose();
                              racaController.dispose();
                              tamanhoController.dispose();
                              pesoController.dispose();
                              corController.dispose();
                              observacoesController.dispose();
                              
                              // Fechar diálogo de loading primeiro
                              if (mounted) Navigator.pop(context);
                              
                              // Fechar diálogo do pet
                              if (mounted) Navigator.pop(context);
                              
                              if (mounted) {
                                // Mostrar mensagem de sucesso
                                final mensagem = petExistente != null ? 'Pet atualizado com sucesso!' : 'Pet adicionado com sucesso!';
                                if (fotoPathFinal == null && fotoPath != null && fotoPath!.isNotEmpty) {
                                  // Upload falhou mas pet foi salvo
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('$mensagem\nAviso: A foto não foi enviada (timeout ou erro de conexão).'),
                                      backgroundColor: Colors.orange,
                                      duration: const Duration(seconds: 4),
                                    ),
                                  );
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(mensagem),
                                      backgroundColor: Colors.green,
                                    ),
                                  );
                                }
                              }
                            } catch (e) {
                              // Fechar loading em caso de erro
                              if (mounted) Navigator.pop(context);
                              
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Erro ao salvar pet: $e'),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                              }
                            }
                          },
                          icon: Icon(petExistente != null ? Icons.save : Icons.add),
                          label: Text(petExistente != null ? 'Salvar' : 'Adicionar'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
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
      ),
    );
  }

  Widget _buildSecaoTitulo(String titulo, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: Colors.orange, size: 20),
        const SizedBox(width: 8),
        Text(
          titulo,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildCampoTexto({
    required TextEditingController controller,
    required String label,
    IconData? icon,
    String? hintText,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    String? prefixText,
    int maxLines = 1,
    bool required = false,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      maxLines: maxLines,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label + (required ? ' *' : ''),
        hintText: hintText,
        labelStyle: const TextStyle(color: Colors.white70),
        hintStyle: TextStyle(color: Colors.white.withOpacity(0.4)),
        prefixIcon: icon != null ? Icon(icon, color: Colors.white54) : null,
        prefixText: prefixText,
        prefixStyle: const TextStyle(color: Colors.white),
        filled: true,
        fillColor: const Color(0xFF181A1B),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.orange, width: 2),
        ),
      ),
    );
  }

  Widget _buildCampoData({
    required String label,
    required DateTime? value,
    required Function(DateTime?) onChanged,
  }) {
    return InkWell(
      onTap: () async {
        final date = await showDatePicker(
          context: context,
          initialDate: value ?? DateTime.now(),
          firstDate: DateTime(2000),
          lastDate: DateTime.now(),
        );
        if (date != null) {
          onChanged(date);
        }
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.white70),
          prefixIcon: const Icon(Icons.calendar_today, color: Colors.white54),
          filled: true,
          fillColor: const Color(0xFF181A1B),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.orange, width: 2),
          ),
        ),
        child: Text(
          value != null ? DateFormat('dd/MM/yyyy').format(value) : 'Selecionar data',
          style: TextStyle(
            color: value != null ? Colors.white : Colors.white.withOpacity(0.5),
          ),
        ),
      ),
    );
  }

  void _confirmarExclusaoPet(int index) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: const Text('Excluir Pet', style: TextStyle(color: Colors.white)),
        content: Text('Deseja excluir ${_pets[index].nome}?', style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _pets.removeAt(index);
              });
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
  }

  Widget _buildOpcaoTipo(TipoPessoa tipo, String label, IconData icone) {
    final isSelected = _tipoPessoa == tipo;
    return GestureDetector(
      onTap: () => setState(() => _tipoPessoa = tipo),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? Colors.blue.withOpacity(0.2)
              : Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? Colors.blue : Colors.white.withOpacity(0.1),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icone,
              color: isSelected ? Colors.blue : Colors.white54,
              size: 24,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.white70,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            if (isSelected) ...[
              const SizedBox(width: 8),
              const Icon(Icons.check_circle, color: Colors.blue, size: 18),
            ],
          ],
        ),
      ),
    );
  }


  Widget _buildBotaoSalvar() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2E),
        border: Border(top: BorderSide(color: Colors.white.withOpacity(0.1))),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Botão Nova Venda (apenas para cliente existente)
            if (_isEditing) ...[
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _mostrarDialogNovaVenda,
                  icon: const Icon(Icons.shopping_cart),
                  label: const Text('Nova Venda'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                    label: const Text('Cancelar'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white70,
                      side: const BorderSide(color: Colors.white24),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _salvar,
                    icon: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.save),
                    label: Text(_isEditing ? 'Atualizar' : 'Cadastrar'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _mostrarDialogNovaVenda() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.shopping_cart, color: Colors.blue),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Nova Venda',
                style: TextStyle(color: Colors.white, fontSize: 18),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Selecione o tipo de venda para ${widget.cliente?.nome}:',
              style: TextStyle(color: Colors.white.withOpacity(0.7)),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _buildOpcaoVenda(
                    ctx,
                    'Venda Direta',
                    'PDV rápido',
                    Icons.point_of_sale,
                    Colors.green,
                    () {
                      Navigator.pop(ctx);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              VendaDiretaPage(clienteInicial: widget.cliente),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildOpcaoVenda(
                    ctx,
                    'Pedido',
                    'Venda completa',
                    Icons.receipt_long,
                    Colors.orange,
                    () {
                      Navigator.pop(ctx);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              LancarPedidoPage(clienteInicial: widget.cliente),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );
  }

  Widget _buildOpcaoVenda(
    BuildContext ctx,
    String titulo,
    String subtitulo,
    IconData icone,
    Color cor,
    VoidCallback onTap,
  ) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: cor.withOpacity(0.3)),
          ),
          child: Column(
            children: [
              Icon(icone, color: cor, size: 36),
              const SizedBox(height: 8),
              Text(
                titulo,
                style: TextStyle(
                  color: cor,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
              Text(
                subtitulo,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.5),
                  fontSize: 11,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _salvar() async {
    if (!_formKey.currentState!.validate()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Preencha os campos obrigatórios'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final dataService = Provider.of<DataService>(context, listen: false);

      final cliente = Cliente(
        id: (_isEditing)
          ? widget.cliente!.id
          : DateTime.now().millisecondsSinceEpoch.toString(),
        nome: _nomeController.text.trim(),
        nomeFantasia: _nomeFantasiaController.text.trim().isEmpty
            ? null
            : _nomeFantasiaController.text.trim(),
        tipoPessoa: _tipoPessoa,
        cpfCnpj: _cpfCnpjController.text.trim().isEmpty
            ? null
            : _cpfCnpjController.text.trim(),
        rgIe: _rgIeController.text.trim().isEmpty
            ? null
            : _rgIeController.text.trim(),
        email: _emailController.text.trim().isEmpty
            ? null
            : _emailController.text.trim(),
        telefone: _telefoneController.text.trim(),
        telefone2: _telefone2Controller.text.trim().isEmpty
            ? null
            : _telefone2Controller.text.trim(),
        whatsapp: _whatsappController.text.trim().isEmpty
            ? null
            : _whatsappController.text.trim(),
        endereco: _enderecoController.text.trim().isEmpty
            ? null
            : '$_tipoLogradouro ${_enderecoController.text.trim()}',
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
        pontoReferencia: _pontoReferenciaController.text.trim().isEmpty
            ? null
            : _pontoReferenciaController.text.trim(),
        dataNascimento: _dataNascimento,
        profissao: _profissaoController.text.trim().isEmpty
            ? null
            : _profissaoController.text.trim(),
        observacoes: _observacoesController.text.trim().isEmpty
            ? null
            : _observacoesController.text.trim(),
        pets: _pets,
        limiteCredito: double.tryParse(
          _limiteCreditoController.text.replaceAll(',', '.'),
        ),
        bloqueado: _bloqueado,
        ativo: _ativo,
        createdAt: widget.cliente?.createdAt ?? DateTime.now(),
        updatedAt: DateTime.now(),
      );

      if (_isEditing) {
        dataService.updateCliente(cliente);
      } else {
        await dataService.addCliente(cliente);
      }

      if (mounted) {
        Navigator.pop(context, cliente);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 10),
                Text(
                  _isEditing
                      ? 'Cliente atualizado com sucesso!'
                      : 'Cliente cadastrado com sucesso!',
                ),
              ],
            ),
            backgroundColor: Colors.green,
          ),
        );
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

  void _confirmarExclusao() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning, color: Colors.red),
            SizedBox(width: 12),
            Text('Excluir Cliente', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: Text(
          'Tem certeza que deseja excluir o cliente "${widget.cliente?.nome}"?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              final dataService = Provider.of<DataService>(
                context,
                listen: false,
              );
              dataService.deleteCliente(widget.cliente!.id);
              Navigator.pop(context); // Fecha o dialog
              Navigator.pop(context); // Volta para a lista
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Cliente excluído'),
                  backgroundColor: Colors.orange,
                ),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
  }

  // ============ ABA FINANCEIRO ============
  Widget _buildTabFinanceiro() {
    final dataService = Provider.of<DataService>(context);
    final formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final formatoData = DateFormat('dd/MM/yyyy');

    // Buscar todos os pedidos do cliente
    final pedidosCliente =
        dataService.pedidos
            .where((p) => p.clienteId == widget.cliente?.id)
            .toList()
          ..sort((a, b) => b.dataPedido.compareTo(a.dataPedido));

    // Buscar todas as vendas balcão do cliente
    final vendasBalcaoCliente =
        dataService.vendasBalcao
            .where((v) => v.clienteId == widget.cliente?.id)
            .toList()
          ..sort((a, b) => b.dataVenda.compareTo(a.dataVenda));

    // Calcular estatísticas financeiras
    final estatisticas = _calcularEstatisticasFinanceiras(pedidosCliente, vendasBalcaoCliente);

    // Separar pagamentos pendentes (a prazo)
    final pagamentosPendentes = <_PagamentoPendenteInfo>[];
    final pagamentosRecebidos = <_PagamentoPendenteInfo>[];

    for (final pedido in pedidosCliente) {
      for (final pag in pedido.pagamentos) {
        final info = _PagamentoPendenteInfo(pedido: pedido, pagamento: pag);
        if (pag.recebido) {
          pagamentosRecebidos.add(info);
        } else {
          pagamentosPendentes.add(info);
        }
      }
    }

    // Ordenar pendentes por vencimento
    pagamentosPendentes.sort((a, b) {
      final dataA = a.pagamento.dataVencimento ?? DateTime.now();
      final dataB = b.pagamento.dataVencimento ?? DateTime.now();
      return dataA.compareTo(dataB);
    });

    // Ordenar recebidos por data de recebimento (mais recentes primeiro)
    pagamentosRecebidos.sort((a, b) {
      final dataA = a.pagamento.dataRecebimento ?? a.pedido.dataPedido;
      final dataB = b.pagamento.dataRecebimento ?? b.pedido.dataPedido;
      return dataB.compareTo(dataA);
    });

    // Buscar agendamentos de vacina do cliente
    final agendamentosVacina = dataService.agendamentosServico
        .where((a) => a.clienteId == widget.cliente?.id && 
                      ((a.servicoId?.startsWith('vacina_') ?? false) || 
                       (a.observacoes != null && a.observacoes!.toLowerCase().contains('vacina'))))
        .toList()
      ..sort((a, b) => b.dataAgendamento.compareTo(a.dataAgendamento));

    // Buscar materiais consumidos dos pedidos do cliente
    final materiaisConsumidos = <Map<String, dynamic>>[];
    for (final pedido in pedidosCliente) {
      for (final material in pedido.materiaisConsumidos) {
        materiaisConsumidos.add({
          'material': material,
          'pedido': pedido,
          'data': pedido.dataPedido,
        });
      }
    }
    materiaisConsumidos.sort((a, b) => (b['data'] as DateTime).compareTo(a['data'] as DateTime));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Dashboard Financeiro
          _buildDashboardFinanceiro(estatisticas, formatoMoeda),

          const SizedBox(height: 24),

          // Análise de Crédito
          _buildAnaliseCredito(estatisticas, formatoMoeda),

          const SizedBox(height: 24),

          // Pagamentos Pendentes (A Receber)
          if (pagamentosPendentes.isNotEmpty) ...[
            _buildSecaoTitulo('Pagamentos Pendentes', Icons.pending_actions),
            const SizedBox(height: 12),
            ...pagamentosPendentes.map(
              (info) => _buildCardPagamentoPendente(
                info,
                formatoMoeda,
                formatoData,
                dataService,
              ),
            ),
            const SizedBox(height: 24),
          ],

          // Histórico de Pagamentos Recebidos
          _buildSecaoTitulo('Histórico de Pagamentos', Icons.history),
          const SizedBox(height: 12),
          if (pagamentosRecebidos.isEmpty)
            _buildSemHistorico()
          else
            ...pagamentosRecebidos
                .take(20)
                .map(
                  (info) => _buildCardPagamentoRecebido(
                    info,
                    formatoMoeda,
                    formatoData,
                  ),
                ),

          const SizedBox(height: 24),

          // Histórico de Pedidos
          _buildSecaoTitulo('Histórico de Pedidos', Icons.receipt_long),
          const SizedBox(height: 12),
          if (pedidosCliente.isEmpty)
            _buildSemHistorico()
          else
            ...pedidosCliente
                .take(10)
                .map(
                  (pedido) => _buildCardPedidoHistorico(
                    pedido,
                    formatoMoeda,
                    formatoData,
                  ),
                ),

          const SizedBox(height: 24),

          // Histórico de Vendas (Balcão)
          _buildSecaoTitulo('Histórico de Vendas (Balcão)', Icons.shopping_bag),
          const SizedBox(height: 12),
          if (vendasBalcaoCliente.isEmpty)
            _buildSemHistorico()
          else
            ...vendasBalcaoCliente
                .take(10)
                .map(
                  (venda) => _buildCardVendaBalcaoHistorico(
                    venda,
                    formatoMoeda,
                    formatoData,
                  ),
                ),

          const SizedBox(height: 24),

          // Histórico de Vacinas
          _buildSecaoTitulo('Histórico de Vacinas', Icons.vaccines),
          const SizedBox(height: 12),
          if (agendamentosVacina.isEmpty)
            _buildSemHistorico()
          else
            ...agendamentosVacina
                .take(10)
                .map(
                  (agendamento) => _buildCardVacinaHistorico(
                    agendamento,
                    formatoData,
                  ),
                ),

          const SizedBox(height: 24),

          // Histórico de Materiais Consumidos
          _buildSecaoTitulo('Histórico de Materiais Consumidos', Icons.inventory),
          const SizedBox(height: 12),
          if (materiaisConsumidos.isEmpty)
            _buildSemHistorico()
          else
            ...materiaisConsumidos
                .take(10)
                .map(
                  (item) => _buildCardMaterialHistorico(
                    item['material'] as ItemMaterial,
                    item['pedido'] as Pedido,
                    formatoData,
                  ),
                ),

          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Map<String, dynamic> _calcularEstatisticasFinanceiras(List<Pedido> pedidos, List<VendaBalcao> vendas) {
    double totalCompras = 0;
    double totalPago = 0;
    double totalPendente = 0;
    double totalVencido = 0;
    int qtdPedidos = pedidos.length;
    int qtdPagamentosPendentes = 0;
    int qtdPagamentosVencidos = 0;
    int diasMaiorAtraso = 0;
    DateTime? ultimaCompra;

    for (final pedido in pedidos) {
      totalCompras += pedido.totalGeral;
      if (ultimaCompra == null || pedido.dataPedido.isAfter(ultimaCompra)) {
        ultimaCompra = pedido.dataPedido;
      }

      for (final pag in pedido.pagamentos) {
        if (pag.recebido) {
          totalPago += pag.valor;
        } else {
          totalPendente += pag.valor;
          qtdPagamentosPendentes++;

          if (pag.dataVencimento != null &&
              pag.dataVencimento!.isBefore(DateTime.now())) {
            totalVencido += pag.valor;
            qtdPagamentosVencidos++;
            final diasAtraso = DateTime.now()
                .difference(pag.dataVencimento!)
                .inDays;
            if (diasAtraso > diasMaiorAtraso) {
              diasMaiorAtraso = diasAtraso;
            }
          }
        }
      }
    }

    // Incluir vendas balcão (geralmente são pagas na hora, exceto canceladas)
    for (final venda in vendas) {
      if (venda.cancelado) continue;
      
      totalCompras += venda.valorTotal;
      totalPago += venda.valorTotal; // Vendas balcão no sistema geralmente são recebidas no ato
      
      if (ultimaCompra == null || venda.dataVenda.isAfter(ultimaCompra)) {
        ultimaCompra = venda.dataVenda;
      }
    }

    int qtdTotalTransacoes = qtdPedidos + vendas.where((v) => !v.cancelado).length;

    // Score de crédito baseado no histórico
    int scoreCredito = 100;
    if (qtdPagamentosVencidos > 0) {
      scoreCredito -= (qtdPagamentosVencidos * 10).clamp(0, 40);
    }
    if (diasMaiorAtraso > 30) scoreCredito -= 20;
    if (diasMaiorAtraso > 60) scoreCredito -= 20;
    if (totalVencido > 500) scoreCredito -= 10;
    scoreCredito = scoreCredito.clamp(0, 100);

    return {
      'totalCompras': totalCompras,
      'totalPago': totalPago,
      'totalPendente': totalPendente,
      'totalVencido': totalVencido,
      'qtdPedidos': qtdPedidos,
      'qtdVendas': vendas.length,
      'qtdPagamentosPendentes': qtdPagamentosPendentes,
      'qtdPagamentosVencidos': qtdPagamentosVencidos,
      'diasMaiorAtraso': diasMaiorAtraso,
      'ultimaCompra': ultimaCompra,
      'scoreCredito': scoreCredito,
      'ticketMedio': qtdTotalTransacoes > 0 ? totalCompras / qtdTotalTransacoes : 0.0,
    };
  }

  Widget _buildDashboardFinanceiro(
    Map<String, dynamic> stats,
    NumberFormat formatoMoeda,
  ) {
    final totalCompras = stats['totalCompras'] as double;
    final totalPago = stats['totalPago'] as double;
    final totalPendente = stats['totalPendente'] as double;
    final totalVencido = stats['totalVencido'] as double;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF1a237e).withOpacity(0.8),
            const Color(0xFF283593).withOpacity(0.8),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _buildStatFinanceiro(
                  'Total Compras',
                  formatoMoeda.format(totalCompras),
                  Icons.shopping_cart,
                  Colors.blue,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatFinanceiro(
                  'Total Pago',
                  formatoMoeda.format(totalPago),
                  Icons.check_circle,
                  Colors.green,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildStatFinanceiro(
                  'Pendente',
                  formatoMoeda.format(totalPendente),
                  Icons.schedule,
                  Colors.orange,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatFinanceiro(
                  'Vencido',
                  formatoMoeda.format(totalVencido),
                  Icons.warning,
                  totalVencido > 0 ? Colors.red : Colors.grey,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatFinanceiro(
    String label,
    String valor,
    IconData icon,
    Color cor,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cor.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(icon, color: cor, size: 24),
          const SizedBox(height: 6),
          Text(
            valor,
            style: TextStyle(
              color: cor,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnaliseCredito(
    Map<String, dynamic> stats,
    NumberFormat formatoMoeda,
  ) {
    final scoreCredito = stats['scoreCredito'] as int;
    final qtdPedidos = stats['qtdPedidos'] as int;
    final ticketMedio = stats['ticketMedio'] as double;
    final diasMaiorAtraso = stats['diasMaiorAtraso'] as int;
    final qtdVencidos = stats['qtdPagamentosVencidos'] as int;
    final ultimaCompra = stats['ultimaCompra'] as DateTime?;

    Color corScore;
    String statusCredito;
    IconData iconeStatus;

    if (scoreCredito >= 80) {
      corScore = Colors.green;
      statusCredito = 'Excelente';
      iconeStatus = Icons.verified;
    } else if (scoreCredito >= 60) {
      corScore = Colors.lightGreen;
      statusCredito = 'Bom';
      iconeStatus = Icons.thumb_up;
    } else if (scoreCredito >= 40) {
      corScore = Colors.orange;
      statusCredito = 'Regular';
      iconeStatus = Icons.warning;
    } else {
      corScore = Colors.red;
      statusCredito = 'Atenção';
      iconeStatus = Icons.error;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: corScore.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: corScore.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(iconeStatus, color: corScore, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Análise de Crédito',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                    Row(
                      children: [
                        Text(
                          statusCredito,
                          style: TextStyle(
                            color: corScore,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: corScore.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '$scoreCredito pts',
                            style: TextStyle(
                              color: corScore,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Barra de progresso do score
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: scoreCredito / 100,
              backgroundColor: Colors.white.withOpacity(0.1),
              valueColor: AlwaysStoppedAnimation<Color>(corScore),
              minHeight: 8,
            ),
          ),
          const SizedBox(height: 16),
          // Detalhes
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              _buildDetalheCredito(
                Icons.receipt,
                '$qtdPedidos pedidos',
                Colors.blue,
              ),
              _buildDetalheCredito(
                Icons.trending_up,
                'Ticket: ${formatoMoeda.format(ticketMedio)}',
                Colors.green,
              ),
              if (qtdVencidos > 0)
                _buildDetalheCredito(
                  Icons.warning,
                  '$qtdVencidos vencidos',
                  Colors.red,
                ),
              if (diasMaiorAtraso > 0)
                _buildDetalheCredito(
                  Icons.timer_off,
                  'Maior atraso: $diasMaiorAtraso dias',
                  Colors.orange,
                ),
              if (ultimaCompra != null)
                _buildDetalheCredito(
                  Icons.calendar_today,
                  'Última: ${DateFormat('dd/MM/yy').format(ultimaCompra)}',
                  Colors.purple,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDetalheCredito(IconData icon, String texto, Color cor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: cor),
          const SizedBox(width: 6),
          Text(texto, style: TextStyle(color: cor, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildCardPagamentoPendente(
    _PagamentoPendenteInfo info,
    NumberFormat formatoMoeda,
    DateFormat formatoData,
    DataService dataService,
  ) {
    final pag = info.pagamento;
    final pedido = info.pedido;
    final isVencido =
        pag.dataVencimento != null &&
        pag.dataVencimento!.isBefore(DateTime.now());
    final diasAtraso = isVencido
        ? DateTime.now().difference(pag.dataVencimento!).inDays
        : 0;

    Color corTipo;
    IconData iconeTipo;

    switch (pag.tipo) {
      case TipoPagamento.crediario:
        corTipo = Colors.purple;
        iconeTipo = Icons.credit_score;
        break;
      case TipoPagamento.boleto:
        corTipo = Colors.orange;
        iconeTipo = Icons.receipt_long;
        break;
      default:
        corTipo = Colors.blue;
        iconeTipo = Icons.payment;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isVencido
              ? Colors.red.withOpacity(0.5)
              : corTipo.withOpacity(0.3),
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: corTipo.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(iconeTipo, color: corTipo, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            pag.tipo.nome,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (pag.isParcela) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: corTipo.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '${pag.numeroParcela}/${pag.parcelas}',
                                style: TextStyle(
                                  color: corTipo,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      Text(
                        'Pedido ${pedido.numero}',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.5),
                          fontSize: 12,
                        ),
                      ),
                      Row(
                        children: [
                          Icon(
                            isVencido ? Icons.warning : Icons.event,
                            size: 12,
                            color: isVencido ? Colors.red : Colors.white54,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            pag.dataVencimento != null
                                ? 'Venc: ${formatoData.format(pag.dataVencimento!)}'
                                : 'Sem vencimento',
                            style: TextStyle(
                              color: isVencido ? Colors.red : Colors.white54,
                              fontSize: 11,
                            ),
                          ),
                          if (isVencido) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.red.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '$diasAtraso dias',
                                style: const TextStyle(
                                  color: Colors.red,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      formatoMoeda.format(pag.valor),
                      style: TextStyle(
                        color: isVencido ? Colors.red : Colors.greenAccent,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Botão para marcar como recebido
          Container(
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.1),
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(12),
                bottomRight: Radius.circular(12),
              ),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => _marcarComoRecebido(dataService, pedido, pag),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(12),
                  bottomRight: Radius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.check_circle,
                        color: Colors.green.withOpacity(0.8),
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Marcar como Recebido',
                        style: TextStyle(
                          color: Colors.green.withOpacity(0.8),
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _marcarComoRecebido(
    DataService dataService,
    Pedido pedido,
    PagamentoPedido pagamento,
  ) {
    // Formas de recebimento disponíveis (sem fiado, pois fiado é só para lançamento)
    final formasRecebimento = TipoPagamento.values
        .where((t) => t != TipoPagamento.fiado)
        .toList();

    TipoPagamento? formaSelecionada;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1E1E2E),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Row(
              children: [
                Icon(Icons.payments, color: Colors.green),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Receber Pagamento',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Valor a receber
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.green.withOpacity(0.3)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Valor:',
                          style: TextStyle(color: Colors.white70, fontSize: 16),
                        ),
                        Text(
                          'R\$ ${pagamento.valor.toStringAsFixed(2)}',
                          style: const TextStyle(
                            color: Colors.greenAccent,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Tipo original
                  Text(
                    'Forma original: ${pagamento.tipo.nome}',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.5),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Label
                  const Text(
                    'Como o cliente está pagando?',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Botões de forma de recebimento
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: formasRecebimento.map((tipo) {
                      final isSelected = formaSelecionada == tipo;
                      final cor = _getCorTipoRecebimento(tipo);

                      return Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () {
                            setDialogState(() {
                              formaSelecionada = tipo;
                            });
                          },
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? cor.withOpacity(0.3)
                                  : Colors.white.withOpacity(0.05),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isSelected
                                    ? cor
                                    : Colors.white.withOpacity(0.2),
                                width: isSelected ? 2 : 1,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _getIconeTipoRecebimento(tipo),
                                  color: isSelected ? cor : Colors.white54,
                                  size: 18,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  tipo.nome,
                                  style: TextStyle(
                                    color: isSelected ? cor : Colors.white70,
                                    fontWeight: isSelected
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: formaSelecionada == null
                    ? null
                    : () {
                        // Atualizar o pagamento com a nova forma de recebimento
                        final novosPagamentos = pedido.pagamentos.map((p) {
                          if (p.id == pagamento.id) {
                            return PagamentoPedido(
                              id: p.id,
                              tipo: formaSelecionada!,
                              tipoOriginal: p.tipo, // Guardar tipo original
                              valor: p.valor,
                              recebido: true,
                              dataRecebimento: DateTime.now(),
                              dataVencimento: p.dataVencimento,
                              parcelas: p.parcelas,
                              numeroParcela: p.numeroParcela,
                              parcelamentoId: p.parcelamentoId,
                              observacao: p.observacao,
                            );
                          }
                          return p;
                        }).toList();

                        // Atualizar status do pedido
                        final todosRecebidos = novosPagamentos.every(
                          (p) => p.recebido,
                        );

                        final pedidoAtualizado = Pedido(
                          id: pedido.id,
                          numero: pedido.numero,
                          clienteId: pedido.clienteId,
                          clienteNome: pedido.clienteNome,
                          clienteTelefone: pedido.clienteTelefone,
                          clienteEndereco: pedido.clienteEndereco,
                          dataPedido: pedido.dataPedido,
                          status: todosRecebidos ? 'Pago' : pedido.status,
                          produtos: pedido.produtos,
                          servicos: pedido.servicos,
                          pagamentos: novosPagamentos,
                        );

                        dataService.updatePedido(pedidoAtualizado);

                        // Se era fiado, atualizar saldo devedor do cliente
                        if (pagamento.tipo == TipoPagamento.fiado &&
                            widget.cliente != null) {
                          final novoSaldo =
                              (widget.cliente!.saldoDevedor - pagamento.valor)
                                  .clamp(0.0, double.infinity);
                          final clienteAtualizado = widget.cliente!.copyWith(
                            saldoDevedor: novoSaldo,
                            updatedAt: DateTime.now(),
                          );
                          dataService.updateCliente(clienteAtualizado);
                        }

                        Navigator.pop(ctx);
                        setState(() {}); // Refresh

                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              '✓ Recebido via ${formaSelecionada!.nome}!',
                            ),
                            backgroundColor: Colors.green,
                          ),
                        );
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: formaSelecionada != null
                      ? Colors.green
                      : Colors.grey,
                ),
                child: const Text('Confirmar Recebimento'),
              ),
            ],
          );
        },
      ),
    );
  }

  IconData _getIconeTipoRecebimento(TipoPagamento tipo) {
    switch (tipo) {
      case TipoPagamento.dinheiro:
        return Icons.money;
      case TipoPagamento.pix:
        return Icons.qr_code;
      case TipoPagamento.cartaoCredito:
        return Icons.credit_card;
      case TipoPagamento.cartaoDebito:
        return Icons.credit_card;
      case TipoPagamento.boleto:
        return Icons.receipt;
      case TipoPagamento.crediario:
        return Icons.calendar_today;
      case TipoPagamento.fiado:
        return Icons.handshake;
      case TipoPagamento.outro:
        return Icons.more_horiz;
    }
  }

  Color _getCorTipoRecebimento(TipoPagamento tipo) {
    switch (tipo) {
      case TipoPagamento.dinheiro:
        return Colors.green;
      case TipoPagamento.pix:
        return Colors.teal;
      case TipoPagamento.cartaoCredito:
        return Colors.purple;
      case TipoPagamento.cartaoDebito:
        return Colors.blue;
      case TipoPagamento.boleto:
        return Colors.orange;
      case TipoPagamento.crediario:
        return Colors.pink;
      case TipoPagamento.fiado:
        return Colors.red;
      case TipoPagamento.outro:
        return Colors.grey;
    }
  }

  Widget _buildCardPagamentoRecebido(
    _PagamentoPendenteInfo info,
    NumberFormat formatoMoeda,
    DateFormat formatoData,
  ) {
    final pag = info.pagamento;
    final pedido = info.pedido;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2E),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.check, color: Colors.green, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  pag.tipo.nome,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  'Pedido ${pedido.numero} • ${formatoData.format(pag.dataRecebimento ?? pedido.dataPedido)}',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.5),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          Text(
            formatoMoeda.format(pag.valor),
            style: const TextStyle(
              color: Colors.greenAccent,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardPedidoHistorico(
    Pedido pedido,
    NumberFormat formatoMoeda,
    DateFormat formatoData,
  ) {
    final isPago = pedido.totalmenteRecebido;

    return _PedidoHistoricoExpandivel(
      pedido: pedido,
      formatoMoeda: formatoMoeda,
      formatoData: formatoData,
      isPago: isPago,
      onRepetirVenda: () => _repetirVenda(pedido),
    );
  }

  Widget _buildCardVendaBalcaoHistorico(
    VendaBalcao venda,
    NumberFormat formatoMoeda,
    DateFormat formatoData,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: venda.cancelado ? Colors.red.withOpacity(0.3) : Colors.white.withOpacity(0.1),
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: (venda.cancelado ? Colors.red : Colors.orange).withOpacity(0.2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            venda.cancelado ? Icons.close : Icons.shopping_bag,
            color: venda.cancelado ? Colors.redAccent : Colors.orangeAccent,
          ),
        ),
        title: Row(
          children: [
            Text(
              'Venda ${venda.numero}',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (venda.cancelado) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'CANCELADA',
                  style: TextStyle(
                    color: Colors.redAccent,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              'Data: ${formatoData.format(venda.dataVenda)}',
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
            Text(
              '${venda.itens.length} itens • ${venda.tipoPagamento.toString().split('.').last}',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
        ),
        trailing: Text(
          formatoMoeda.format(venda.valorTotal),
          style: TextStyle(
            color: venda.cancelado ? Colors.white38 : Colors.greenAccent,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
      ),
    );
  }

  void _repetirVenda(Pedido pedido) {
    // Navegar para venda direta com os mesmos itens
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => VendaDiretaPage(
          clienteInicial: widget.cliente,
          itensParaRepetir: pedido.produtos,
          servicosParaRepetir: pedido.servicos,
        ),
      ),
    );
  }

  Widget _buildSemHistorico() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2E),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: Column(
          children: [
            Icon(Icons.inbox, size: 40, color: Colors.white.withOpacity(0.3)),
            const SizedBox(height: 12),
            Text(
              'Nenhum registro encontrado',
              style: TextStyle(color: Colors.white.withOpacity(0.5)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCardVacinaHistorico(
    AgendamentoServico agendamento,
    DateFormat formatoData,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2E),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.orange.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.vaccines, color: Colors.orange, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  agendamento.observacoes ?? 'Vacina',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${formatoData.format(agendamento.dataAgendamento)} • ${agendamento.numero}',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.6),
                    fontSize: 11,
                  ),
                ),
                if (agendamento.status.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: _getCorStatusVacina(agendamento.status).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      agendamento.status,
                      style: TextStyle(
                        color: _getCorStatusVacina(agendamento.status),
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _getCorStatusVacina(String status) {
    switch (status) {
      case 'Concluído':
        return Colors.green;
      case 'Em Andamento':
        return Colors.blue;
      case 'Cancelado':
        return Colors.red;
      default:
        return Colors.orange;
    }
  }

  Widget _buildCardMaterialHistorico(
    ItemMaterial material,
    Pedido pedido,
    DateFormat formatoData,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2E),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.blue.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.inventory, color: Colors.blue, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  material.produtoNome,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Quantidade: ${material.quantidade}${material.unidade != null ? ' ${material.unidade}' : ''} • Pedido: ${pedido.numero}',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.6),
                    fontSize: 11,
                  ),
                ),
                Text(
                  'Data: ${formatoData.format(pedido.dataPedido)}',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.6),
                    fontSize: 11,
                  ),
                ),
                if (material.observacao != null && material.observacao!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    material.observacao!,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.5),
                      fontSize: 10,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Classe auxiliar para informações de pagamento pendente
class _PagamentoPendenteInfo {
  final Pedido pedido;
  final PagamentoPedido pagamento;

  _PagamentoPendenteInfo({required this.pedido, required this.pagamento});
}

/// Formatter para transformar texto em maiúsculas
class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return TextEditingValue(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
    );
  }
}

/// Widget expandível para mostrar detalhes do pedido no histórico
class _PedidoHistoricoExpandivel extends StatefulWidget {
  final Pedido pedido;
  final NumberFormat formatoMoeda;
  final DateFormat formatoData;
  final bool isPago;
  final VoidCallback onRepetirVenda;

  const _PedidoHistoricoExpandivel({
    required this.pedido,
    required this.formatoMoeda,
    required this.formatoData,
    required this.isPago,
    required this.onRepetirVenda,
  });

  @override
  State<_PedidoHistoricoExpandivel> createState() =>
      _PedidoHistoricoExpandivelState();
}

class _PedidoHistoricoExpandivelState
    extends State<_PedidoHistoricoExpandivel> {
  bool _expandido = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2E),
        borderRadius: BorderRadius.circular(10),
        border: _expandido
            ? Border.all(color: Colors.blue.withOpacity(0.3))
            : null,
      ),
      child: Column(
        children: [
          // Header clicável
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => setState(() => _expandido = !_expandido),
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: (widget.isPago ? Colors.green : Colors.orange)
                            .withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        widget.isPago ? Icons.check_circle : Icons.schedule,
                        color: widget.isPago ? Colors.green : Colors.orange,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.pedido.numero,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '${widget.formatoData.format(widget.pedido.dataPedido)} • ${widget.pedido.produtos.length + widget.pedido.servicos.length} itens',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.5),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          widget.formatoMoeda.format(widget.pedido.totalGeral),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color:
                                (widget.isPago ? Colors.green : Colors.orange)
                                    .withOpacity(0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            widget.isPago ? 'Pago' : 'Pendente',
                            style: TextStyle(
                              color: widget.isPago
                                  ? Colors.green
                                  : Colors.orange,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      _expandido
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      color: Colors.white54,
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Conteúdo expandível
          if (_expandido) ...[
            Divider(color: Colors.white.withOpacity(0.1), height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Lista de produtos
                  if (widget.pedido.produtos.isNotEmpty) ...[
                    Text(
                      'Produtos',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.7),
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...widget.pedido.produtos.map(
                      (item) => _buildItemPedido(
                        item.nome,
                        item.quantidade,
                        item.preco,
                        widget.formatoMoeda,
                        Icons.inventory_2,
                      ),
                    ),
                  ],

                  // Lista de serviços
                  if (widget.pedido.servicos.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Serviços',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.7),
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...widget.pedido.servicos.map(
                      (item) => _buildItemPedido(
                        item.descricao,
                        1,
                        item.valor,
                        widget.formatoMoeda,
                        Icons.build,
                      ),
                    ),
                  ],

                  // Lista de materiais consumidos
                  if (widget.pedido.materiaisConsumidos.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Materiais Consumidos',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.7),
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...widget.pedido.materiaisConsumidos.map(
                      (material) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          children: [
                            Icon(Icons.inventory, size: 16, color: Colors.blue.withOpacity(0.7)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${material.produtoNome} - ${material.quantidade}${material.unidade != null ? ' ${material.unidade}' : ''}',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.8),
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],

                  // Total
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Total da Venda',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          widget.formatoMoeda.format(widget.pedido.totalGeral),
                          style: const TextStyle(
                            color: Colors.greenAccent,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Botão Repetir Venda
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: widget.onRepetirVenda,
                      icon: const Icon(Icons.replay, size: 18),
                      label: const Text('Repetir esta Venda'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildItemPedido(
    String nome,
    int quantidade,
    double preco,
    NumberFormat formatoMoeda,
    IconData icone,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(icone, size: 14, color: Colors.white38),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              nome,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            '${quantidade}x',
            style: TextStyle(
              color: Colors.white.withOpacity(0.5),
              fontSize: 12,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            formatoMoeda.format(preco * quantidade),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
