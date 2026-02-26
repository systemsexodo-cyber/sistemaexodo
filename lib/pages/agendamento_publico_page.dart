import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sistema_exodo_novo/models/servico.dart';
import 'package:sistema_exodo_novo/models/agendamento_servico.dart';
import 'package:sistema_exodo_novo/models/cliente.dart';
import 'package:sistema_exodo_novo/models/pet.dart';
import 'package:sistema_exodo_novo/services/data_service.dart';
import 'package:sistema_exodo_novo/services/auth_service.dart';
import 'package:intl/intl.dart';
import 'dart:ui';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:async';

class AgendamentoPublicoPage extends StatefulWidget {
  final String? slugEmpresa;

  const AgendamentoPublicoPage({super.key, this.slugEmpresa});

  @override
  State<AgendamentoPublicoPage> createState() => _AgendamentoPublicoPageState();
}

class _LojaPublicaStyle {
  static Color getPrimary(Color? custom) => custom ?? const Color(0xFF6366F1);
  static Color getSecondary(Color? custom) => custom ?? const Color(0xFF8B5CF6);
  static const accentColor = Color(0xFF10B981);
  static const backgroundColor = Color(0xFF0F172A);
  static const cardColor = Color(0xFF1E293B);
  static const textColor = Color(0xFFF8FAFC);
  static const textSecondaryColor = Color(0xFF94A3B8);
}

class _AgendamentoPublicoPageState extends State<AgendamentoPublicoPage> {
  final _formKey = GlobalKey<FormState>();
  int _currentStep = 0;
  bool _isDark = true; // Mesmo padrão do e-commerce

  Color get _primaryColor {
    try {
      final auth = Provider.of<AuthService>(context, listen: false);
      final data = Provider.of<DataService>(context, listen: false);
      final empresa = auth.obterEmpresaPorSlug(widget.slugEmpresa ?? '') ?? data.empresaAtual;
      if (empresa?.corPrimaria != null) {
        String hex = empresa!.corPrimaria!.replaceAll('#', '');
        return Color(int.parse("FF$hex", radix: 16));
      }
    } catch (_) {}
    return const Color(0xFF6366F1);
  }

  Color get _secondaryColor {
    try {
      final auth = Provider.of<AuthService>(context, listen: false);
      final data = Provider.of<DataService>(context, listen: false);
      final empresa = auth.obterEmpresaPorSlug(widget.slugEmpresa ?? '') ?? data.empresaAtual;
      if (empresa?.corSecundaria != null) {
        String hex = empresa!.corSecundaria!.replaceAll('#', '');
        return Color(int.parse("FF$hex", radix: 16));
      }
    } catch (_) {}
    return const Color(0xFF8B5CF6);
  }

  // Dados do formulário
  final _nomeController = TextEditingController();
  final _whatsappController = TextEditingController();
  final _petNomeController = TextEditingController();
  final _petRacaController = TextEditingController();
  final _petEspecieController = TextEditingController();
  final _petCorController = TextEditingController();
  final _petObsController = TextEditingController();
  
  // Endereço para Taxi Dog
  final _enderecoRuaController = TextEditingController();
  final _enderecoNumeroController = TextEditingController();
  final _enderecoComplementoController = TextEditingController();
  final _pontoReferenciaController = TextEditingController();
  final _bairroController = TextEditingController();


  
  List<String> _servicosSelecionadosIds = [];
  String _porteAnimal = 'Pequeno'; // Pequeno, Médio, Grande, Gigante
  double _pesoAproximado = 5.0;
  DateTime? _dataSelecionada;
  TimeOfDay? _horaSelecionada;
  String _tipoEntrega = 'Retirada na Loja'; // 'Retirada na Loja', 'Taxi Dog'
  String? _bairroEntrega;
  String _petSexo = 'M'; // M ou F
  String _petEspecie = 'Cachorro';
  bool _modoMultiPets = false;
  List<Pet> _petsMultiSelecionados = [];
  String? _funcionarioSelecionadoId;
  String? _funcionarioSelecionadoNome;


  bool _enviando = false;
  bool _verificandoDisponibilidade = false;
  List<AgendamentoServico> _agendamentosCarrinho = [];

  final List<String> _portes = ['Pequeno', 'Médio', 'Grande', 'Gigante'];

  // Busca de cliente/pet automático
  List<Pet> _petsEncontrados = [];
  Pet? _petSendoEditado;
  bool _mostrarFormularioPet = true;
  Cliente? _clienteEncontrado;
  bool _buscandoCliente = false;
  String? _ultimoTelefoneBuscado; // Para evitar loops de busca
  Timer? _debounceBusca;

  @override
  void initState() {
    super.initState();
    _whatsappController.addListener(_onWhatsappChanged);
    _nomeController.addListener(_onNomeChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _inicializarEmpresa();
  }

  Future<void> _inicializarEmpresa() async {
    final dataService = Provider.of<DataService>(context, listen: false);
    final authService = Provider.of<AuthService>(context, listen: false);
    
    if (widget.slugEmpresa != null) {
      // Sempre tentar buscar a versão mais recente da empresa ao entrar na página
      final emp = await authService.buscarEmpresaPorSlugAsync(widget.slugEmpresa!);
      if (emp != null) {
        debugPrint('>>> [Agendamento] Configurando empresa: ${emp.nomeExibicao} (${emp.id})');
        
        // Garantir que o DataService saiba qual a empresa atual
        if (dataService.empresaIdAtual != emp.id) {
          await dataService.definirEmpresaAtual(emp.id, modoLeve: true);
        }
        
        // Atualizar o objeto empresa no DataService para ter as configurações de agendamento frescas
        dataService.setEmpresaAtual(emp);
        
        if (mounted) setState(() {});
      }
    }
  }

  void _onNomeChanged() {
    _agendarBusca();
  }

  void _onWhatsappChanged() {
    _agendarBusca();
  }

  void _agendarBusca() {
    _debounceBusca?.cancel();
    _debounceBusca = Timer(const Duration(milliseconds: 600), () {
      final tel = _whatsappController.text.replaceAll(RegExp(r'\D'), '');
      if (tel.length >= 8) {
        _buscarClientePorTelefone(tel);
      }
    });
  }

  Future<void> _buscarClientePorTelefone(String telefone) async {
    final normalizado = telefone.replaceAll(RegExp(r'\D'), '');
    
    if (normalizado.length < 8) {
      if (_clienteEncontrado != null) {
        setState(() {
          _clienteEncontrado = null;
          _petsEncontrados = [];
        });
      }
      return;
    }

    if (_buscandoCliente && _ultimoTelefoneBuscado == normalizado) {
      debugPrint('>>> [Agendamento] Busca já em andamento para $normalizado');
      return;
    }

    final dataService = Provider.of<DataService>(context, listen: false);
    final nomeDigitado = _nomeController.text.toLowerCase().trim();

    if (_clienteEncontrado != null) {
      final t = _clienteEncontrado!.telefone.replaceAll(RegExp(r'\D'), '');
      final w = (_clienteEncontrado!.whatsapp ?? '').replaceAll(RegExp(r'\D'), '');
      final n = _clienteEncontrado!.nome.toLowerCase().trim();
      
      if ((t == normalizado || w == normalizado) && (nomeDigitado.isEmpty || n == nomeDigitado)) {
        debugPrint('>>> [Agendamento] Cliente ${_clienteEncontrado!.nome} já carregado e coincide. Pulando busca.');
        return;
      }
    }

    debugPrint('>>> [Agendamento] 🔍 Iniciando busca: fone $normalizado, nome "$nomeDigitado"');

    setState(() {
      _buscandoCliente = true;
      _ultimoTelefoneBuscado = normalizado;
    });

    try {
      final candidatos = await dataService.buscarClientePorTelefone(normalizado);

      if (candidatos.isNotEmpty) {
        debugPrint('>>> [Agendamento] ✅ ${candidatos.length} candidatos encontrados.');
        
        final sortedCandidatos = List<Cliente>.from(candidatos);
        final nomeBusca = _nomeController.text.toLowerCase().trim();

        sortedCandidatos.sort((a, b) {
          if (nomeBusca.isNotEmpty) {
            final aMatches = a.nome.toLowerCase().trim() == nomeBusca;
            final bMatches = b.nome.toLowerCase().trim() == nomeBusca;
            if (aMatches && !bMatches) return -1;
            if (!aMatches && bMatches) return 1;
          }
          if (a.pets.isNotEmpty && b.pets.isEmpty) return -1;
          if (a.pets.isEmpty && b.pets.isNotEmpty) return 1;
          if (a.pets.length != b.pets.length) return b.pets.length.compareTo(a.pets.length);
          return b.updatedAt.compareTo(a.updatedAt);
        });

        final encontrado = sortedCandidatos.first;
        debugPrint('>>> [Agendamento] Selecionado: ${encontrado.nome} (${encontrado.pets.length} pets)');
        
        setState(() {
          _clienteEncontrado = encontrado;
          _petsEncontrados = encontrado.pets;
          
          if (_nomeController.text.isEmpty) {
            _nomeController.text = encontrado.nome;
          }
          
          if (_bairroEntrega == null || _enderecoRuaController.text.isEmpty) {
            _bairroEntrega = encontrado.bairro;
            _bairroController.text = encontrado.bairro ?? '';
            _enderecoRuaController.text = encontrado.endereco ?? '';
            _enderecoNumeroController.text = encontrado.numero ?? '';
            _enderecoComplementoController.text = encontrado.complemento ?? '';
            _pontoReferenciaController.text = encontrado.pontoReferencia ?? '';
          }
          
          if (_petsEncontrados.length == 1 && _petNomeController.text.isEmpty) {
            final pet = _petsEncontrados.first;
            debugPrint('>>> [Agendamento] Auto-selecionando pet: ${pet.nome}');
            _petNomeController.text = pet.nome;
            _petRacaController.text = pet.raca ?? '';
            _petCorController.text = pet.cor ?? '';
            _petObsController.text = pet.observacoes ?? '';
            _petEspecie = pet.especie ?? 'Cachorro';
            _petSexo = pet.sexo ?? 'M';
            _porteAnimal = pet.tamanho ?? 'Pequeno';
            _pesoAproximado = pet.peso ?? 5.0;
            _mostrarFormularioPet = false;
            _petSendoEditado = null; // No auto-edit for selection to keep UI clean
          }
          
          // Se cliente não tem Taxi Dog habilitado, resetar para Retirada na Loja
          if (!encontrado.habilitaTaxiDog && _tipoEntrega != 'Retirada na Loja') {
            debugPrint('>>> [Agendamento] Cliente sem Taxi Dog habilitado - resetando para Retirada na Loja');
            _tipoEntrega = 'Retirada na Loja';
          }
        });
      } else {
        debugPrint('>>> [Agendamento] ❌ Nada encontrado para $normalizado');
        if (_clienteEncontrado != null) {
          setState(() {
            _clienteEncontrado = null;
            _petsEncontrados = [];
          });
        }
      }
    } catch (e) {
      debugPrint('>>> [Agendamento] ❌ Erro: $e');
    } finally {
      if (mounted) setState(() => _buscandoCliente = false);
    }
  }

  @override
  void dispose() {
    _nomeController.dispose();
    _whatsappController.dispose();
    _petNomeController.dispose();
    _petRacaController.dispose();
    _petEspecieController.dispose();
    _petCorController.dispose();
    _petObsController.dispose();
    _enderecoRuaController.dispose();
    _enderecoNumeroController.dispose();
    _enderecoComplementoController.dispose();
    _pontoReferenciaController.dispose();
    _debounceBusca?.cancel();
    super.dispose();
  }

  @override

  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    final dataService = Provider.of<DataService>(context);
    
    // Priorização: Se o slug bater ou não houver slug, preferir a empresa do DataService
    // pois ela é a fonte de verdade para a empresa ativa e seus dados frescos.
    final slug = widget.slugEmpresa ?? '';
    final empresaFromData = dataService.empresaAtual;
    final empresaFromAuth = authService.obterEmpresaPorSlug(slug);
    
    final empresa = (slug.isNotEmpty && empresaFromData?.slug == slug) 
        ? empresaFromData 
        : (empresaFromAuth ?? empresaFromData);

    final bool moduloPet = empresa?.moduloPet ?? false;
    final agendamentoConfig = (empresa?.configuracoes?['agendamento'] as Map<String, dynamic>?) ?? {};
    final bool esconderValores = agendamentoConfig['esconderValores'] as bool? ?? false;
    final String? whatsappLoja = agendamentoConfig['whatsappContato']?.toString();

    Color? pColor;
    Color? sColor;
    if (empresa != null) {
      try {
        if (empresa.corPrimaria != null) pColor = Color(int.parse("FF${empresa.corPrimaria!.replaceAll('#', '')}", radix: 16));
        if (empresa.corSecundaria != null) sColor = Color(int.parse("FF${empresa.corSecundaria!.replaceAll('#', '')}", radix: 16));
      } catch (_) {}
    }

    final primary = _LojaPublicaStyle.getPrimary(pColor);

    print('>>> [AgendamentoPage] Construindo para: ${widget.slugEmpresa} | Empresa: ${empresa?.nomeExibicao} | Clientes: ${dataService.clientes.length}');
 
    // --- SINCRONIZAÇÃO DE DADOS EM TEMPO REAL ---
    if (_clienteEncontrado != null && dataService.clientes.isNotEmpty) {
      try {
        final id = _clienteEncontrado!.id;
        final latest = dataService.clientes.firstWhere(
          (c) => c.id == id,
          orElse: () => _clienteEncontrado!,
        );
        
        // Se a referência mudou OU a lista de pets mudou (mesmo na mesma instância)
        if (latest != _clienteEncontrado || latest.pets.length != _petsEncontrados.length) {
          _clienteEncontrado = latest;
          _petsEncontrados = latest.pets;
          debugPrint('>>> [Agendamento] 🔄 Dados de ${latest.nome} atualizados (Pets: ${latest.pets.length})');
        }
      } catch (_) {}
    }

    final foneLimpo = _whatsappController.text.replaceAll(RegExp(r'\D'), '');
    if (foneLimpo.length >= 8 && _clienteEncontrado == null && !_buscandoCliente && foneLimpo != _ultimoTelefoneBuscado) {
       Future.microtask(() => _buscarClientePorTelefone(_whatsappController.text));
    }
    
    // Feedback de carregamento global no topo se estiver sincronizando
    final bool isSyncingData = dataService.isLoading && dataService.firebaseHabilitado;
    // --------------------------------------------

    return Scaffold(
      backgroundColor: _isDark ? _LojaPublicaStyle.backgroundColor : Colors.grey[100],
      appBar: AppBar(
        title: Text(empresa?.nomeExibicao ?? 'Agendamento'),
        backgroundColor: primary,
        elevation: 0,
        bottom: isSyncingData ? PreferredSize(
          preferredSize: const Size.fromHeight(2),
          child: LinearProgressIndicator(
            backgroundColor: Colors.white.withAlpha(25),
            valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
            minHeight: 2,
          ),
        ) : null,
        actions: [
          TextButton.icon(
            onPressed: () => _mostrarConsultaAgendamentos(primary),
            icon: const Icon(Icons.search, color: Colors.white, size: 20),
            label: const Text('Meus Agendamentos', style: TextStyle(color: Colors.white, fontSize: 12)),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  _buildWelcomeBanner(primary),
                  _buildStepper(primary, moduloPet),
                  const SizedBox(height: 32),
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: _isDark ? _LojaPublicaStyle.cardColor : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.withAlpha(51)),
                    ),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          if (_agendamentosCarrinho.isNotEmpty) _buildResumoCarrinho(primary, esconderValores),
                          _buildCurrentStepView(moduloPet, esconderValores),
                        ],
                      ),
                    ),
                  ),
                  // Espaço extra no final para não ficar colado no rodapé se rolar tudo
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
          // Rodapé Fixo com botões de navegação
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            decoration: BoxDecoration(
              color: _isDark ? _LojaPublicaStyle.cardColor : Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(51),
                  blurRadius: 15,
                  offset: const Offset(0, -5),
                ),
              ],
              border: Border(
                top: BorderSide(
                  color: _isDark ? Colors.white12 : Colors.black.withAlpha(12),
                ),
              ),
            ),
            child: SafeArea(
              top: false,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 800), // Manter alinhado em telas largas
                child: _buildNavigationButtons(primary, moduloPet),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderPremium(String nomeEmpresa, Color primaryColor, Color textColor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _buildHeader(nomeEmpresa),
        IconButton(
          icon: Icon(_isDark ? Icons.light_mode : Icons.dark_mode, color: primaryColor),
          onPressed: () => setState(() => _isDark = !_isDark),
        ),
      ],
    );
  }

  Widget _buildWelcomeBanner(Color primary) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      margin: const EdgeInsets.only(bottom: 32),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [primary, primary.withOpacity(0.8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: primary.withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'É um prazer te ver por aqui!',
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Escolha o serviço e o melhor horário para você. Nossa equipe está pronta para te atender com toda dedicação!',
            style: GoogleFonts.inter(
              color: Colors.white.withOpacity(0.9),
              fontSize: 14,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  // Update existing private build methods to accept color parameters if needed, or rely on Theme.of(context)
  // I'll update the signatures in the chunks if they were hardcoded.

  Widget _buildAnimatedBackground(Color primaryColor, Color secondaryColor) {
    if (!_isDark) return const SizedBox.shrink(); // Fundo limpo no modo claro

    return SizedBox.expand(
      child: Stack(
        children: [
          Positioned(
            top: -100,
            right: -100,
            child: Container(
              width: 400,
              height: 400,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: primaryColor.withOpacity(0.08),
              ),
            ),
          ),
          Positioned(
            bottom: -50,
            left: -50,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: secondaryColor.withOpacity(0.08),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(String nomeEmpresa) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [_primaryColor, _secondaryColor],
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.calendar_month_rounded, color: Colors.white, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Agendamento Online',
                    style: GoogleFonts.inter(
                      color: _isDark ? _LojaPublicaStyle.textSecondaryColor : Colors.grey[600],
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 1.1,
                    ),
                  ),
                  Text(
                    nomeEmpresa,
                    style: GoogleFonts.outfit(
                      color: _isDark ? Colors.white : Colors.black87,
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  // Helper: se o passo de Entrega deve ser exibido
  bool get _mostrarPassoEntrega => _clienteEncontrado?.habilitaTaxiDog ?? false;

  Widget _buildStepper(Color primaryColor, bool moduloPet) {
    final agendamentoConfig = Provider.of<DataService>(context, listen: false).empresaAtual?.configuracoes?['agendamento'] as Map<String, dynamic>? ?? {};
    final bool mostrarEntrega = moduloPet && _mostrarPassoEntrega;
    final List<String> stepLabels = [
      'Serviço', 
      'Seus Dados', 
      if (moduloPet) 'O Pet', 
      if (mostrarEntrega) 'Entrega',
      if (agendamentoConfig['permitirEscolhaProfissional'] == true) 'Profissional',
      'Horário'
    ];
    final List<IconData> stepIcons = [
      Icons.style_rounded,
      Icons.person_rounded,
      if (moduloPet) Icons.pets_rounded,
      if (mostrarEntrega) Icons.local_shipping_rounded,
      if (agendamentoConfig['permitirEscolhaProfissional'] == true) Icons.person_search,
      Icons.access_time_filled_rounded
    ];

    final int totalPassos = stepLabels.length;

    return Row(
      children: List.generate(totalPassos, (index) {
        bool isCompleted = _currentStep > index;
        bool isActive = _currentStep == index;
        
        return Expanded(
          child: Column(
            children: [
              Row(
                children: [
                  if (index > 0)
                    Expanded(
                      child: Container(
                        height: 2,
                        color: isCompleted || isActive 
                            ? primaryColor 
                            : (_isDark ? Colors.white.withAlpha(25) : Colors.black.withAlpha(12)),
                      ),
                    ),
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: isCompleted || isActive 
                          ? LinearGradient(
                              colors: [_primaryColor, _secondaryColor],
                            )
                          : null,
                      color: isCompleted || isActive ? null : Theme.of(context).cardColor,
                      boxShadow: isActive ? [
                        BoxShadow(
                          color: primaryColor.withOpacity(0.4),
                          blurRadius: 12,
                          spreadRadius: 2,
                        )
                      ] : null,
                      border: Border.all(
                        color: isActive ? (_isDark ? Colors.white : primaryColor) : (_isDark ? Colors.white.withAlpha(25) : Colors.black.withAlpha(25)),
                        width: 2,
                      ),
                    ),
                    child: Center(
                      child: isCompleted 
                          ? const Icon(Icons.check, color: Colors.white, size: 20)
                          : Icon(
                              stepIcons[index], 
                              color: isActive ? Colors.white : (_isDark ? Colors.white24 : Colors.grey[400]),
                              size: 18,
                            ),
                    ),
                  ),
                  if (index < totalPassos - 1)
                    Expanded(
                      child: Container(
                        height: 2,
                        color: isCompleted 
                            ? primaryColor 
                            : (_isDark ? Colors.white.withAlpha(25) : Colors.black.withAlpha(12)),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                stepLabels[index],
                style: GoogleFonts.inter(
                  color: isActive ? (_isDark ? Colors.white : primaryColor) : (_isDark ? _LojaPublicaStyle.textSecondaryColor : Colors.grey[500]),
                  fontSize: 11,
                  fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  Widget _buildCurrentStepView(bool moduloPet, bool esconderValores) {
    // Mapear o índice atual para o passo real
    // Passos reais: 0=Serviço, 1=Dados, 2=Pet, 3=Entrega, 4=Horário
    // Passos reais: 0=Serviço, 1=Dados, 2=Pet, 3=Entrega, 4=Horário, 5=Profissional
    
    // Passo 5: Profissional (Opcional)
    final agendamentoConfig = Provider.of<DataService>(context, listen: false).empresaAtual?.configuracoes?['agendamento'] as Map<String, dynamic>? ?? {};
    final bool permiteProfissional = agendamentoConfig['permitirEscolhaProfissional'] == true;
    
    // Se está no último passo visual mas ainda não é o passoReal 4, 
    // precisamos ajustar para saber se cai ou não no profissional
    final List<int> passosReaisHabilitados = [0, 1];
    if (moduloPet) passosReaisHabilitados.add(2);
    if (moduloPet && _mostrarPassoEntrega) passosReaisHabilitados.add(3);
    if (permiteProfissional) passosReaisHabilitados.add(5);
    passosReaisHabilitados.add(4); // Horário sempre por último

    int passoReal = passosReaisHabilitados[_currentStep];

    switch (passoReal) {
      case 0:
        return _buildStepServicos(moduloPet, esconderValores);
      case 1:
        return _buildStepDadosPessoais();
      case 2:
        return _buildStepDadosPet();
      case 3:
        final authService = Provider.of<AuthService>(context, listen: false);
        final dataService = Provider.of<DataService>(context, listen: false);
        
        final slugP = widget.slugEmpresa ?? '';
        final eFromData = dataService.empresaAtual;
        final eFromAuth = authService.obterEmpresaPorSlug(slugP);
        final empresa = (slugP.isNotEmpty && eFromData?.slug == slugP) ? eFromData : (eFromAuth ?? eFromData);

        final config = empresa?.configuracoes ?? {};
        // agendamentoConfig já está definido acima, mas aqui é usado para a lógica de bairros
        // final agendamentoConfig = config['agendamento'] as Map<String, dynamic>? ?? {};
        
        // --- CONSOLIDAÇÃO DE CONFIGURAÇÕES (Exclusivo da Agenda) ---
        final Map<String, Map<String, dynamic>> bairrosUnicos = {};

        void registerBairro(String nome, double taxa, {double? taxaBusca, double? taxaSoleva}) {
          final nomeTrimmado = nome.trim();
          if (nomeTrimmado.isEmpty) return;
          
          final chave = nomeTrimmado.toLowerCase();
          if (!bairrosUnicos.containsKey(chave)) {
            bairrosUnicos[chave] = {
              'bairro': nomeTrimmado,
              'taxa': taxa,
              'taxaBusca': taxaBusca ?? taxa, // Fallback para taxa normal se não informado
              'taxaSoleva': taxaSoleva ?? taxa, // Fallback para taxa normal se não informado
            };
          }
        }

        // 1. Taxas da Configuração V2 (Prioridade - Configurado na Engrenagem da Agenda)
        final bairrosV2 = (agendamentoConfig['bairrosTaxiDogV2'] ?? config['bairrosTaxiDogV2']) as List<dynamic>?;
        if (bairrosV2 != null) {
          for (final item in bairrosV2) {
            final m = Map<String, dynamic>.from(item);
            registerBairro(
              m['bairro'] ?? '', 
              (m['taxa'] as num?)?.toDouble() ?? 0.0,
              taxaBusca: (m['taxaBusca'] as num?)?.toDouble(),
              taxaSoleva: (m['taxaSoleva'] as num?)?.toDouble(),
            );
          }
        }

        // 2. Bairros Simples V1 (Compatibilidade)
        final bairrosV1 = (agendamentoConfig['bairrosTaxiDog'] ?? config['bairrosTaxiDog']) as List<dynamic>?;
        if (bairrosV1 != null) {
          for (final b in bairrosV1) {
            registerBairro(b.toString(), 0.0);
          }
        }

        if (bairrosUnicos.isNotEmpty) {
          final sortedList = bairrosUnicos.values.toList();
          sortedList.sort((a, b) => (a['bairro'] as String).compareTo(b['bairro'] as String));
          return _buildStepEntregaV2(sortedList);
        }

        // 3. Fallback: Lista Padrão se nada estiver configurado
        return _buildStepEntrega([]);
      case 5:
        return _buildStepProfissional();
      case 4:
        return _buildStepHorario();
      default:
        return const SizedBox();
    }
  }

  Widget _buildStepServicos(bool moduloPet, bool esconderValores) {
    final dataService = Provider.of<DataService>(context);
    // Filtrar serviços para não mostrar duplicatas causadas por lançamentos com Taxi Dog
    final servicos = dataService.servicos.where((s) {
      final n = s.nome.toLowerCase();
      // Não mostrar serviços que foram poluídos com Taxi Dog no nome
      return !n.contains('taxi dog') && !n.contains('entrega');
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStepTitle(
          'O que vamos fazer hoje?', 
          moduloPet ? 'Selecione o serviço desejado para o seu pet.' : 'Selecione o serviço desejado.',
        ),
        const SizedBox(height: 24),
      if (servicos.isEmpty && dataService.isLoading)
        Center(
          child: Column(
            children: [
              const SizedBox(height: 40),
              CircularProgressIndicator(color: _primaryColor),
              const SizedBox(height: 16),
              Text(
                'Sincronizando serviços...',
                style: TextStyle(color: _isDark ? _LojaPublicaStyle.textSecondaryColor : Colors.grey[600]),
              ),
            ],
          ),
        )
      else if (servicos.isEmpty)
        _buildEmptyState('Nenhum serviço disponível no momento.')
      else
          LayoutBuilder(
            builder: (context, constraints) {
              // Em telas maiores que 900px, exibimos 2 colunas para aproveitar o espaço horizontal
              final crossAxisCount = constraints.maxWidth > 900 ? 2 : 1;
              
              return Column(
                children: [
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: servicos.length,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxisCount,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                      // Mantemos uma altura fixa para os cards para garantir o alinhamento no grid
                      mainAxisExtent: 110, 
                    ),
                    itemBuilder: (context, index) {
                      final servico = servicos[index];
                      bool isSelected = _servicosSelecionadosIds.contains(servico.id);

                      return InkWell(
                        onTap: () {
                          setState(() {
                            if (isSelected) {
                              _servicosSelecionadosIds.remove(servico.id);
                            } else {
                              _servicosSelecionadosIds.add(servico.id);
                            }
                          });
                        },
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: isSelected ? _primaryColor.withAlpha(38) : (_isDark ? Colors.white.withAlpha(8) : Colors.grey[50]),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: isSelected ? _primaryColor : (_isDark ? Colors.white.withAlpha(25) : Colors.grey[200]!),
                              width: 2,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: isSelected ? _primaryColor : Colors.white.withAlpha(12),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  _getIconForServico(servico.nome),
                                  color: isSelected ? Colors.white : (_isDark ? _LojaPublicaStyle.textSecondaryColor : Colors.grey[500]),
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      servico.nome,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: _isDark ? Colors.white : Colors.black87, 
                                        fontWeight: FontWeight.bold, 
                                        fontSize: 16
                                      ),
                                    ),
                                    if (servico.descricao?.isNotEmpty ?? false) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        servico.descricao!,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: _isDark ? _LojaPublicaStyle.textSecondaryColor : Colors.grey[600], 
                                          fontSize: 12
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  if (!esconderValores)
                                    Text(
                                      'R\$ ${servico.precoTotal.toStringAsFixed(2)}',
                                      style: GoogleFonts.outfit(
                                        color: isSelected ? (_isDark ? Colors.white : _primaryColor) : _primaryColor,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                  if (servico.duracaoPadraoMinutos != null)
                                    Text(
                                      '${servico.duracaoPadraoMinutos} min',
                                      style: TextStyle(color: _isDark ? _LojaPublicaStyle.textSecondaryColor : Colors.grey[500], fontSize: 10),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  if (_servicosSelecionadosIds.isNotEmpty) ...[
                    const SizedBox(height: 32),
                    _buildServicosSelecionadosSummary(servicos, esconderValores),
                  ],
                ],
              );
            },
          ),
      ],
    );
  }

  IconData _getIconForServico(String nome) {
    final n = nome.toLowerCase();
    
    // Pets e Banho
    if (n.contains('banho')) return Icons.waves_rounded;
    if (n.contains('tosa')) return Icons.content_cut_rounded;
    if (n.contains('vacina')) return Icons.vaccines_rounded;
    if (n.contains('consulta')) return Icons.medical_services_rounded;
    if (n.contains('hospedagem')) return Icons.hotel_rounded;
    
    // Estética e Beleza (conforme imagem)
    if (n.contains('bronzeamento')) return Icons.wb_sunny_rounded;
    if (n.contains('sombrancelha')) return Icons.remove_red_eye_rounded;
    if (n.contains('limpeza de pele') || n.contains('facial')) return Icons.face_retouching_natural_rounded;
    if (n.contains('unha') || n.contains('manicure')) return Icons.back_hand_rounded;
    if (n.contains('cabelo') || n.contains('corte')) return Icons.content_cut_rounded;
    if (n.contains('massagem')) return Icons.self_improvement_rounded;
    if (n.contains('estetica')) return Icons.auto_awesome_rounded;
    
    // Padrão
    return Icons.star_rounded;
  }

  Widget _buildStepDadosPessoais() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStepTitle('Fale um pouco de você', 'Precisamos desses dados para confirmar seu agendamento.'),
        const SizedBox(height: 32),
        _buildTextField(
          controller: _nomeController,
          label: 'Seu Nome Completo',
          icon: Icons.person_outline_rounded,
          placeholder: 'Como podemos te chamar?',
          validator: (v) => v!.isEmpty ? 'Obrigatório' : null,
        ),
        const SizedBox(height: 20),
        _buildTextField(
          controller: _whatsappController,
          label: 'Seu WhatsApp',
          icon: Icons.phone_android_rounded,
          placeholder: '(00) 00000-0000',
          keyboardType: TextInputType.phone,
          validator: (v) => v!.isEmpty ? 'Obrigatório' : null,
          onChanged: (_) => _onWhatsappChanged(),
          suffixIcon: _buscandoCliente 
            ? Container(
                padding: const EdgeInsets.all(12),
                width: 44, 
                height: 44,
                child: Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: _primaryColor),
                  ),
                ),
              )
            : _clienteEncontrado != null 
              ? Container(
                  width: 44,
                  alignment: Alignment.center,
                  child: Icon(Icons.check_circle_rounded, color: Colors.greenAccent),
                )
              : IconButton(
                  icon: Icon(Icons.search_rounded, color: _primaryColor.withOpacity(0.5)),
                  onPressed: () => _buscarClientePorTelefone(_whatsappController.text),
                ),
        ),
        _buildTextField(
          controller: _enderecoRuaController,
          label: 'Sua rua (Opcional)',
          icon: Icons.map_rounded,
          placeholder: 'Ex: Rua das Flores',
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              flex: 2,
              child: _buildTextField(
                controller: _enderecoNumeroController,
                label: 'Número',
                icon: Icons.home_rounded,
                placeholder: '123',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 3,
              child: _buildTextField(
                controller: _bairroController, 
                label: 'Bairro',
                icon: Icons.location_city_rounded,
                placeholder: 'Centro',
              ),
            ),
          ],
        ),
        if (_clienteEncontrado != null) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Icon(Icons.person_pin_circle_rounded, color: Colors.greenAccent, size: 14),
                const SizedBox(width: 8),
                Text(
                  'Cliente reconhecido: ${_clienteEncontrado!.nome}',
                  style: TextStyle(color: Colors.greenAccent, fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildStepDadosPet() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStepTitle('E quem é o cliente VIP?', 'Conte-nos sobre o animalzinho que receberá o cuidado.'),
        const SizedBox(height: 32),

        if (_petsEncontrados.isNotEmpty) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Seus Pets Cadastrados:',
                style: TextStyle(
                  color: _primaryColor, 
                  fontWeight: FontWeight.bold, 
                  fontSize: 15,
                  letterSpacing: 0.5
                ),
              ),
              InkWell(
                onTap: () {
                  setState(() {
                    _modoMultiPets = !_modoMultiPets;
                    if (!_modoMultiPets) _petsMultiSelecionados.clear();
                  });
                },
                child: Row(
                  children: [
                    Icon(
                      _modoMultiPets ? Icons.check_circle_rounded : Icons.add_task_rounded,
                      size: 18,
                      color: _modoMultiPets ? Colors.greenAccent : _primaryColor.withOpacity(0.7),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _modoMultiPets ? 'Concluir seleção' : 'Agendar vários',
                      style: TextStyle(
                        color: _modoMultiPets ? Colors.greenAccent : _primaryColor.withOpacity(0.7),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 115,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _petsEncontrados.length + 1,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                if (index == _petsEncontrados.length) {
                  // Card para "Novo Pet"
                  if (_modoMultiPets) return const SizedBox.shrink(); 

                  bool isSelected = _petNomeController.text.isEmpty && _petsMultiSelecionados.isEmpty;
                  return _buildPetSelectionCard(
                    title: 'Outro Pet',
                    subtitle: 'Novo cadastro',
                    icon: Icons.add_circle_outline_rounded,
                    isSelected: isSelected,
                    onTap: () {
                      setState(() {
                        _petNomeController.clear();
                        _petRacaController.clear();
                        _petCorController.clear();
                        _petObsController.clear();
                        _petEspecie = 'Cachorro';
                        _petSexo = 'M';
                        _porteAnimal = 'Pequeno';
                        _pesoAproximado = 5.0;
                        _petsMultiSelecionados.clear();
                        _mostrarFormularioPet = true;
                        _petSendoEditado = null;
                      });
                    },
                  );
                }

                final pet = _petsEncontrados[index];
                bool isSelected = _modoMultiPets 
                    ? _petsMultiSelecionados.any((p) => p.id == pet.id)
                    : _petNomeController.text == pet.nome;

                return _buildPetSelectionCard(
                  title: pet.nome,
                  subtitle: pet.raca ?? 'Sem raça',
                  icon: (pet.especie?.toLowerCase() ?? '') == 'gato' ? Icons.pets : Icons.pets_rounded,
                  isSelected: isSelected,
                  onEdit: isSelected ? () {
                    setState(() {
                      _petSendoEditado = pet;
                      _mostrarFormularioPet = true;
                      _petNomeController.text = pet.nome;
                      _petRacaController.text = pet.raca ?? '';
                      _petCorController.text = pet.cor ?? '';
                      _petObsController.text = pet.observacoes ?? '';
                      _petEspecie = pet.especie ?? 'Cachorro';
                      _petSexo = pet.sexo ?? 'M';
                      _porteAnimal = pet.tamanho ?? 'Pequeno';
                      _pesoAproximado = pet.peso ?? 5.0;
                    });
                  } : null,
                  onTap: () {
                    setState(() {
                      if (_modoMultiPets) {
                        if (isSelected) {
                          _petsMultiSelecionados.removeWhere((p) => p.id == pet.id);
                          if (_petSendoEditado?.id == pet.id) {
                            _petSendoEditado = null;
                            _mostrarFormularioPet = false;
                          }
                        } else {
                          _petsMultiSelecionados.add(pet);
                        }
                        _mostrarFormularioPet = false;
                      } else {
                        _petNomeController.text = pet.nome;
                        _petRacaController.text = pet.raca ?? '';
                        _petCorController.text = pet.cor ?? '';
                        _petObsController.text = pet.observacoes ?? '';
                        _petEspecie = pet.especie ?? 'Cachorro';
                        _petSexo = pet.sexo ?? 'M';
                        _porteAnimal = pet.tamanho ?? 'Pequeno';
                        _pesoAproximado = pet.peso ?? 5.0;
                        _petsMultiSelecionados.clear();
                        _mostrarFormularioPet = false;
                        _petSendoEditado = pet;
                      }
                    });
                  },
                );
              },
            ),
          ),

          if (!_modoMultiPets && _petNomeController.text.isNotEmpty && !_mostrarFormularioPet) ...[
             const SizedBox(height: 20),
             Container(
               padding: const EdgeInsets.all(16),
               decoration: BoxDecoration(
                 color: _primaryColor.withAlpha(12),
                 borderRadius: BorderRadius.circular(16),
                 border: Border.all(color: _primaryColor.withAlpha(51)),
               ),
               child: Column(
                 crossAxisAlignment: CrossAxisAlignment.start,
                 children: [
                   Row(
                     children: [
                       Icon(Icons.check_circle_rounded, color: Colors.greenAccent, size: 20),
                       const SizedBox(width: 10),
                       Text(
                         'Pet Selecionado: ${_petNomeController.text}',
                         style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                       ),
                     ],
                   ),
                   const SizedBox(height: 8),
                   Text(
                     'Raça: ${_petRacaController.text.isEmpty ? "Não informada" : _petRacaController.text} • Porte: $_porteAnimal',
                     style: const TextStyle(color: Colors.white70, fontSize: 12),
                   ),
                   const SizedBox(height: 16),
                   OutlinedButton.icon(
                     onPressed: () => setState(() => _mostrarFormularioPet = true),
                     icon: const Icon(Icons.edit_rounded, size: 16),
                     label: const Text('Editar dados do pet'),
                     style: OutlinedButton.styleFrom(
                       foregroundColor: _primaryColor,
                       side: BorderSide(color: _primaryColor.withOpacity(0.5)),
                       shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                     ),
                   ),
                 ],
               ),
             ),
          ],

          if (_mostrarFormularioPet || (!_modoMultiPets && _petNomeController.text.isEmpty)) ...[
            const SizedBox(height: 24),
            const Divider(color: Colors.white10),
            const SizedBox(height: 24),
          ],
        ] else if (_clienteEncontrado != null && !_buscandoCliente) ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue.withAlpha(12),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _primaryColor.withAlpha(51)),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded, color: _primaryColor, size: 24),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Bem-vindo de volta, ${_clienteEncontrado!.nome}!',
                        style: TextStyle(color: _primaryColor, fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Não encontramos animais cadastrados em seu nome. Por favor, preencha os dados do seu pet abaixo.',
                        style: TextStyle(color: _isDark ? Colors.white70 : Colors.black87, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
        ],

        if (_mostrarFormularioPet || (_petsEncontrados.isEmpty && _clienteEncontrado != null)) ...[
          if (_petSendoEditado != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Row(
                children: [
                  Icon(Icons.edit_rounded, color: _primaryColor, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'Editando dados de ${_petSendoEditado!.nome}',
                    style: TextStyle(color: _primaryColor, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => setState(() => _mostrarFormularioPet = false),
                    child: const Text('Cancelar edição'),
                  ),
                ],
              ),
            ),

          _buildTextField(
            controller: _petNomeController,
            label: 'Nome do Pet *',
            icon: Icons.pets_rounded,
            placeholder: 'Nome do seu amigo',
            onChanged: (_) => _atualizarDadosPetSendoEditadoSync(),
            validator: (v) {
              if (_modoMultiPets && _petsMultiSelecionados.isNotEmpty) return null;
              if (!_mostrarFormularioPet && _petNomeController.text.isNotEmpty) return null;
              return v!.isEmpty ? 'Obrigatório' : null;
            },
          ),
          
          const SizedBox(height: 20),
          
          Row(
            children: [
              Expanded(
                child: _buildDropdown<String>(
                  label: 'Espécie',
                  icon: Icons.category_rounded,
                  value: _petEspecie,
                  items: ['Cachorro', 'Gato', 'Pássaro', 'Coelho', 'Outros'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                  onChanged: (v) {
                    setState(() => _petEspecie = v!);
                    _atualizarDadosPetSendoEditadoSync();
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildTextField(
                  controller: _petRacaController,
                  label: 'Raça *',
                  icon: Icons.search_rounded,
                  placeholder: 'Ex: Shih-tzu',
                  onChanged: (_) => _atualizarDadosPetSendoEditadoSync(),
                  validator: (v) {
                    if (_modoMultiPets && _petsMultiSelecionados.isNotEmpty) return null;
                    if (!_mostrarFormularioPet && _petNomeController.text.isNotEmpty) return null;
                    return v!.isEmpty ? 'Obrigatório' : null;
                  },
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 20),
          
          Row(
            children: [
              Expanded(
                child: _buildDropdown<String>(
                  label: 'Sexo',
                  icon: Icons.wc_rounded,
                  value: _petSexo,
                  items: [
                    const DropdownMenuItem(value: 'M', child: Text('Macho')),
                    const DropdownMenuItem(value: 'F', child: Text('Fêmea')),
                  ],
                  onChanged: (v) {
                    setState(() => _petSexo = v!);
                    _atualizarDadosPetSendoEditadoSync();
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildTextField(
                  controller: _petCorController,
                  label: 'Cor',
                  icon: Icons.palette_rounded,
                  placeholder: 'Ex: Branco, Preto',
                  onChanged: (_) => _atualizarDadosPetSendoEditadoSync(),
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 32),
          
          Text(
            'Qual o porte do pet?',
            style: TextStyle(color: _isDark ? Colors.white : Colors.black87, fontWeight: FontWeight.w600, fontSize: 16),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: _portes.map((porte) {
              bool isSelected = _porteAnimal == porte;
              return InkWell(
                onTap: () {
                  setState(() => _porteAnimal = porte);
                  _atualizarDadosPetSendoEditadoSync();
                },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: isSelected ? _primaryColor : (_isDark ? Colors.white.withAlpha(12) : Colors.grey[100]),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected ? Colors.white.withAlpha(51) : (_isDark ? Colors.white.withAlpha(25) : Colors.grey[300]!),
                    ),
                  ),
                  child: Text(
                    porte,
                    style: TextStyle(
                      color: isSelected ? Colors.white : (_isDark ? _LojaPublicaStyle.textSecondaryColor : Colors.grey[600]),
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          
          const SizedBox(height: 32),
          
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Peso aproximado:',
                style: TextStyle(color: _isDark ? Colors.white70 : Colors.grey[700]),
              ),
              Text(
                '${_pesoAproximado.toStringAsFixed(1)} kg',
                style: TextStyle(color: _primaryColor, fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ],
          ),
          Slider(
            value: _pesoAproximado,
            min: 0.5,
            max: 80,
            activeColor: _primaryColor,
            inactiveColor: _isDark ? Colors.white.withAlpha(25) : Colors.grey[200],
            onChanged: (val) {
              setState(() => _pesoAproximado = val);
              _atualizarDadosPetSendoEditadoSync();
            },
          ),
          
          const SizedBox(height: 20),
          
          _buildTextField(
            controller: _petObsController,
            label: 'Observações do Animal',
            icon: Icons.notes_rounded,
            placeholder: 'Ex: Ele é bravo, tem alergia a algum produto...',
            maxLines: 3,
            onChanged: (_) => _atualizarDadosPetSendoEditadoSync(),
          ),
        ],
      ],
    );
  }

  void _atualizarDadosPetSendoEditadoSync() {
    if (_petSendoEditado == null) return;
    
    setState(() {
      final updated = _petSendoEditado!.copyWith(
        nome: _petNomeController.text,
        especie: _petEspecie,
        raca: _petRacaController.text,
        sexo: _petSexo,
        cor: _petCorController.text,
        tamanho: _porteAnimal,
        peso: _pesoAproximado,
        observacoes: _petObsController.text,
        updatedAt: DateTime.now(),
      );
      
      _petSendoEditado = updated;
      
      // Update in multi-selected list
      final idx = _petsMultiSelecionados.indexWhere((p) => p.id == updated.id);
      if (idx != -1) _petsMultiSelecionados[idx] = updated;
      
      // Update in found pets (for card UI)
      final idx2 = _petsEncontrados.indexWhere((p) => p.id == updated.id);
      if (idx2 != -1) _petsEncontrados[idx2] = updated;
    });
  }


  Widget _buildPetSelectionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
    VoidCallback? onEdit,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Stack(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 140,
            height: 100,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isSelected ? _primaryColor.withOpacity(0.15) : (_isDark ? Colors.white.withAlpha(12) : Colors.grey[100]),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isSelected ? _primaryColor : (_isDark ? Colors.white.withAlpha(25) : Colors.grey[300]!),
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: isSelected ? _primaryColor : Colors.grey[400], size: 24),
                const SizedBox(height: 4),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: isSelected ? Colors.white : (_isDark ? Colors.white70 : Colors.black87),
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    fontSize: 13,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: isSelected ? _primaryColor : Colors.grey[500],
                    fontSize: 10,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (_modoMultiPets)
            Positioned(
              top: 8,
              right: 8,
              child: Icon(
                isSelected ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                color: isSelected ? _primaryColor : Colors.white24,
                size: 18,
              ),
            ),
          if (isSelected && onEdit != null)
            Positioned(
              top: 8,
              left: 8,
              child: InkWell(
                onTap: onEdit,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: _primaryColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  child: const Icon(Icons.edit_rounded, color: Colors.white, size: 12),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStepEntregaV2(List<Map<String, dynamic>> bairrosConfig) {
    // Taxi Dog só aparece para clientes com habilitaTaxiDog ativado no cadastro
    final bool clienteTemTaxiDog = _clienteEncontrado?.habilitaTaxiDog ?? false;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStepTitle('Opções de Entrega', 'Como o pet chegará até nós?'),
        const SizedBox(height: 32),
        _buildOpcaoEntregaCard(
          titulo: 'Eu levo e busco na loja',
          subtitulo: 'Você traz seu pet e retira após o serviço.',
          icon: Icons.store_rounded,
          tipo: 'Retirada na Loja',
        ),
        // Taxi Dog e derivados só aparecem se o cliente tem habilitaTaxiDog ativado
        if (clienteTemTaxiDog) ...[
          const SizedBox(height: 16),
          _buildOpcaoEntregaCard(
            titulo: 'Taxi Dog (Leva e Traz)',
            subtitulo: 'Nós buscamos o pet na sua casa e levamos de volta.',
            icon: Icons.local_shipping_rounded,
            tipo: 'Taxi Dog',
          ),
          const SizedBox(height: 16),
          _buildOpcaoEntregaCard(
            titulo: 'Apenas Busca (Nós buscamos)',
            subtitulo: 'Nós buscamos o pet na sua casa, e você retira na loja.',
            icon: Icons.arrow_downward_rounded,
            tipo: 'Apenas Busca',
          ),
          const SizedBox(height: 16),
          _buildOpcaoEntregaCard(
            titulo: 'Apenas Entrega (Nós levamos)',
            subtitulo: 'Você traz o pet na loja, e nós entregamos em casa.',
            icon: Icons.arrow_upward_rounded,
            tipo: 'Apenas Entrega',
          ),
        ],
        if (_tipoEntrega != 'Retirada na Loja') ...[
          const SizedBox(height: 32),
          Text(
            'Informe seu bairro para o Taxi Dog:',
            style: TextStyle(color: _isDark ? Colors.white70 : Colors.grey[700], fontSize: 13, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _bairroEntrega,
            dropdownColor: _isDark ? _LojaPublicaStyle.cardColor : Colors.white,
            style: TextStyle(color: _isDark ? Colors.white : Colors.black87),
            decoration: InputDecoration(
              filled: true,
              fillColor: _isDark ? Colors.white.withAlpha(12) : Colors.grey[100],
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
              prefixIcon: Icon(Icons.location_on_rounded, color: _primaryColor),
            ),
            items: () {
              // Proteção contra crash de valor não encontrado (ex: "parque")
              final items = bairrosConfig.map((item) {
                final String b = item['bairro'] ?? '';
                // Omitir valor da taxa do cliente conforme pedido
                return DropdownMenuItem(
                  value: b, 
                  child: Text(b),
                );
              }).toList();

              // Se o bairro atual não está na lista, adicionamos para não crashar
              if (_bairroEntrega != null && !bairrosConfig.any((e) => e['bairro'] == _bairroEntrega)) {
                items.add(DropdownMenuItem(value: _bairroEntrega!, child: Text(_bairroEntrega!)));
              }
              return items;
            }(),
            onChanged: (val) {
              final config = bairrosConfig.firstWhere((e) => e['bairro'] == val, orElse: () => {});
              setState(() {
                _bairroEntrega = val;
                
                // Definir valor com base no tipo selecionado
                if (_tipoEntrega == 'Taxi Dog') {
                   _valorTaxiDog = (config['taxa'] as num?)?.toDouble() ?? 0.0;
                } else if (_tipoEntrega == 'Apenas Busca') {
                   // Se não houver taxa específica de busca, usar a taxa normal (fallback)
                   _valorTaxiDog = (config['taxaBusca'] as num?)?.toDouble() ?? (config['taxa'] as num?)?.toDouble() ?? 0.0;
                } else if (_tipoEntrega == 'Apenas Entrega') {
                   // Se não houver taxa específica de leva, usar a taxa normal (fallback)
                   _valorTaxiDog = (config['taxaSoleva'] as num?)?.toDouble() ?? (config['taxa'] as num?)?.toDouble() ?? 0.0;
                } else {
                   _valorTaxiDog = 0.0;
                }
              });
            },
            validator: (v) => _tipoEntrega != 'Retirada na Loja' && v == null ? 'Selecione o bairro' : null,
          ),
          const SizedBox(height: 20),
          _buildTextField(
            controller: _enderecoRuaController,
            label: 'Rua / Logradouro *',
            icon: Icons.map_rounded,
            placeholder: 'Nome da sua rua',
            validator: (v) => _tipoEntrega != 'Retirada na Loja' && (v == null || v.isEmpty) ? 'Obrigatório para entrega' : null,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: _buildTextField(
                  controller: _enderecoNumeroController,
                  label: 'Número *',
                  icon: Icons.home_rounded,
                  placeholder: 'Ex: 123',
                  validator: (v) => _tipoEntrega != 'Retirada na Loja' && (v == null || v.isEmpty) ? 'Obrigatório' : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 3,
                child: _buildTextField(
                  controller: _enderecoComplementoController,
                  label: 'Complemento',
                  icon: Icons.info_outline_rounded,
                  placeholder: 'Apt, Bloco...',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildTextField(
            controller: _pontoReferenciaController,
            label: 'Ponto de Referência',
            icon: Icons.assistant_navigation,
            placeholder: 'Ex: Próximo ao mercado...',
          ),
        ],
      ],
    );
  }

  double _valorTaxiDog = 0.0;

  Widget _buildStepEntrega(List<String> bairrosCustom) {
    final List<String> bairros = bairrosCustom.isNotEmpty 
        ? (bairrosCustom..sort())
        : ['Centro', 'Vila Nova', 'Jardim Alvorada', 'Outros'];

    // Se o bairro selecionado não estiver na lista (ex: lista padrão mudou ou foi editada)
    // adicionamos ele temporariamente para não quebrar o Dropdown
    if (_bairroEntrega != null && !bairros.contains(_bairroEntrega)) {
      bairros.add(_bairroEntrega!);
      bairros.sort();
    }

    // Taxi Dog só aparece para clientes com habilitaTaxiDog ativado no cadastro
    final bool clienteTemTaxiDog = _clienteEncontrado?.habilitaTaxiDog ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStepTitle('Opções de Entrega', 'Como o pet chegará até nós?'),
        const SizedBox(height: 32),
        _buildOpcaoEntregaCard(
          titulo: 'Eu levo e busco na loja',
          subtitulo: 'Você traz seu pet e retira após o serviço.',
          icon: Icons.store_rounded,
          tipo: 'Retirada na Loja',
        ),
        // Taxi Dog e derivados só aparecem se o cliente tem habilitaTaxiDog ativado
        if (clienteTemTaxiDog) ...[
          const SizedBox(height: 16),
          _buildOpcaoEntregaCard(
            titulo: 'Taxi Dog (Leva e Traz)',
            subtitulo: 'Nós buscamos o pet na sua casa e levamos de volta.',
            icon: Icons.local_shipping_rounded,
            tipo: 'Taxi Dog',
          ),
          const SizedBox(height: 16),
          _buildOpcaoEntregaCard(
            titulo: 'Apenas Entrega (Traz por conta)',
            subtitulo: 'Você traz o pet na loja, e nós entregamos em casa.',
            icon: Icons.home_rounded,
            tipo: 'Apenas Entrega',
          ),
        ],
        if (_tipoEntrega != 'Retirada na Loja') ...[
          const SizedBox(height: 32),
          Text(
            'Informe seu bairro para o Taxi Dog:',
            style: TextStyle(color: _isDark ? Colors.white70 : Colors.grey[700], fontSize: 13, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _bairroEntrega,
            dropdownColor: _isDark ? _LojaPublicaStyle.cardColor : Colors.white,
            style: TextStyle(color: _isDark ? Colors.white : Colors.black87),
            decoration: InputDecoration(
              filled: true,
              fillColor: _isDark ? Colors.white.withAlpha(12) : Colors.grey[100],
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
              prefixIcon: Icon(Icons.location_on_rounded, color: _primaryColor),
            ),
            items: bairros.map((b) => DropdownMenuItem(value: b, child: Text(b))).toList(),
            onChanged: (val) {
              setState(() {
                _bairroEntrega = val;
                if (val != null && val != 'Outros') {
                  _bairroController.text = val;
                }
              });
            },
            validator: (v) => _tipoEntrega != 'Retirada na Loja' && v == null ? 'Selecione o bairro' : null,
          ),
          const SizedBox(height: 20),
          _buildTextField(
            controller: _enderecoRuaController,
            label: 'Rua / Logradouro *',
            icon: Icons.map_rounded,
            placeholder: 'Nome da sua rua',
            validator: (v) => _tipoEntrega != 'Retirada na Loja' && (v == null || v.isEmpty) ? 'Obrigatório para entrega' : null,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: _buildTextField(
                  controller: _enderecoNumeroController,
                  label: 'Número *',
                  icon: Icons.home_rounded,
                  placeholder: 'Ex: 123',
                  validator: (v) => _tipoEntrega != 'Retirada na Loja' && (v == null || v.isEmpty) ? 'Obrigatório' : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 3,
                child: _buildTextField(
                  controller: _enderecoComplementoController,
                  label: 'Complemento',
                  icon: Icons.info_outline_rounded,
                  placeholder: 'Apt, Bloco...',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildTextField(
            controller: _pontoReferenciaController,
            label: 'Ponto de Referência',
            icon: Icons.assistant_navigation,
            placeholder: 'Ex: Próximo ao mercado...',
          ),
        ],
      ],
    );
  }

  Widget _buildOpcaoEntregaCard({required String titulo, required String subtitulo, required IconData icon, required String tipo}) {
    bool isSelected = _tipoEntrega == tipo;
    return InkWell(
      onTap: () {
        setState(() {
          _tipoEntrega = tipo;
          
          // Se o bairro já estiver selecionado, precisamos recalcular o valor do taxi dog
          // com base na nova modalidade (só busca, só leva ou ambos)
          if (_bairroEntrega != null) {
            final dataService = Provider.of<DataService>(context, listen: false);
            final config = dataService.empresaAtual?.configuracoes ?? {};
            final agendamentoConfig = config['agendamento'] as Map<String, dynamic>? ?? {};
            final bairrosConfig = (agendamentoConfig['bairrosTaxiDogV2'] ?? config['bairrosTaxiDogV2']) as List<dynamic>?;
            
            if (bairrosConfig != null) {
              final bConfig = bairrosConfig.firstWhere((e) => e['bairro'] == _bairroEntrega, orElse: () => {});
              
              if (_tipoEntrega == 'Taxi Dog') {
                _valorTaxiDog = (bConfig['taxa'] as num?)?.toDouble() ?? 0.0;
              } else if (_tipoEntrega == 'Apenas Busca') {
                _valorTaxiDog = (bConfig['taxaBusca'] as num?)?.toDouble() ?? (bConfig['taxa'] as num?)?.toDouble() ?? 0.0;
              } else if (_tipoEntrega == 'Apenas Entrega') {
                _valorTaxiDog = (bConfig['taxaSoleva'] as num?)?.toDouble() ?? (bConfig['taxa'] as num?)?.toDouble() ?? 0.0;
              } else {
                _valorTaxiDog = 0.0;
              }
            }
          } else {
            _valorTaxiDog = 0.0;
          }
        });
      },
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isSelected ? _primaryColor.withOpacity(0.15) : (_isDark ? Colors.white.withAlpha(12) : Colors.grey[100]),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? _primaryColor : (_isDark ? Colors.white.withAlpha(25) : Colors.grey[300]!),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: isSelected ? _primaryColor : (_isDark ? Colors.white.withAlpha(12) : Colors.grey[200]), shape: BoxShape.circle),
              child: Icon(icon, color: isSelected ? Colors.white : (_isDark ? Colors.white54 : Colors.grey[600])),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(titulo, style: TextStyle(color: _isDark ? Colors.white : Colors.black87, fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 4),
                  Text(subtitulo, style: TextStyle(color: _isDark ? Colors.white54 : Colors.grey[600], fontSize: 13)),
                ],
              ),
            ),
            if (isSelected) Icon(Icons.check_circle_rounded, color: _primaryColor),
          ],
        ),
      ),
    );
  }

  Widget _buildHorariosGrid() {
    final dataService = Provider.of<DataService>(context);
    
    final agendamentoConfig = dataService.empresaAtual?.configuracoes?['agendamento'] as Map<String, dynamic>?;
    final hAberturaStr = agendamentoConfig?['horarioAbertura']?.toString() ?? '08:00';
    final hFechamentoStr = agendamentoConfig?['horarioFechamento']?.toString() ?? '18:00';

    double hAbertura = _timeToDouble(hAberturaStr);
    double hFechamento = _timeToDouble(hFechamentoStr);

    // Gerar lista de horários respeitando limites da empresa
    final List<TimeOfDay> slots = [];
    
    // 1. Gerar slots base (conforme o intervalo configurado: 30m, 15m, etc)
    final partsA = hAberturaStr.split(':');
    DateTime current = DateTime((_dataSelecionada ?? DateTime.now()).year, (_dataSelecionada ?? DateTime.now()).month, (_dataSelecionada ?? DateTime.now()).day, int.parse(partsA[0]), int.parse(partsA[1]));
    
    final partsF = hFechamentoStr.split(':');
    final DateTime limit = DateTime((_dataSelecionada ?? DateTime.now()).year, (_dataSelecionada ?? DateTime.now()).month, (_dataSelecionada ?? DateTime.now()).day, int.parse(partsF[0]), int.parse(partsF[1]));

    final intervaloSlots = agendamentoConfig?['intervaloSlots'] != null 
        ? int.tryParse(agendamentoConfig!['intervaloSlots'].toString()) ?? 30 
        : 30;

    while (current.isBefore(limit) || current.isAtSameMomentAs(limit)) {
      slots.add(TimeOfDay(hour: current.hour, minute: current.minute));
      current = current.add(Duration(minutes: intervaloSlots));
    }

    // 2. ENCAIXE INTELIGENTE: Adicionar horários baseados no fim dos agendamentos existentes
    // Isso permite que se um serviço termina 18:10, o sistema ofereça 18:10 como opção.
    final selDate = _dataSelecionada ?? DateTime.now();
    final dataFilter = DateTime(selDate.year, selDate.month, selDate.day);
    final agendamentosDoDia = dataService.agendamentosServico.where((a) {
      final dataA = DateTime(a.dataAgendamento.year, a.dataAgendamento.month, a.dataAgendamento.day);
      return dataA.isAtSameMomentAs(dataFilter) && a.status != 'Cancelado';
    }).toList();

    for (final agd in agendamentosDoDia) {
      final fimEfetivo = agd.dataTerminoEfetiva; // Já inclui a pausa
      final timeFim = TimeOfDay(hour: fimEfetivo.hour, minute: fimEfetivo.minute);
      
      // Se o horário de término está dentro do expediente, é um potencial horário de início
      double hFimDouble = _timeToDouble('${fimEfetivo.hour}:${fimEfetivo.minute}');
      if (hFimDouble >= hAbertura && hFimDouble <= hFechamento) {
        // Evitar duplicatas próximas (se já tem 18:15, não precisa de 18:13)
        bool jaExiste = slots.any((s) {
          final diff = (s.hour * 60 + s.minute) - (timeFim.hour * 60 + timeFim.minute);
          return diff.abs() < 5; // Tolerância de 5 minutos
        });
        
        if (!jaExiste) {
          slots.add(timeFim);
        }
      }
    }

    // Ordenar os slots cronologicamente
    slots.sort((a, b) => (a.hour * 60 + a.minute).compareTo(b.hour * 60 + b.minute));

    final selecionados = dataService.servicos.where((s) => _servicosSelecionadosIds.contains(s.id)).toList();
    final duracaoTotal = selecionados.fold(0, (sum, s) => sum + (s.duracaoPadraoMinutos ?? 60));
    final intervaloMaximo = selecionados.fold(0, (max, s) => (s.intervaloMinutos ?? 0) > max ? (s.intervaloMinutos ?? 0) : max);

    // 3. FILTRAR: Manter apenas os que estão realmente disponíveis para agendar
    final List<Map<String, dynamic>> slotsDisponiveis = [];
    
    for (final time in slots) {
      final checkTime = DateTime(
        selDate.year,
        selDate.month,
        selDate.day,
        time.hour,
        time.minute,
      );

      bool isBloqueadoAdmin = _isHorarioBloqueadoAdmin(dataService, checkTime, duracaoTotal);
      bool isDisponivel = dataService.checkDisponibilidade(
        checkTime, 
        duracaoTotal, 
        intervaloMinutos: intervaloMaximo,
        ignorarPendentes: false
      );

      if (isDisponivel && !isBloqueadoAdmin) {
        slotsDisponiveis.add({
          'time': time,
          'dateTime': checkTime,
        });
      }
    }

    if (slotsDisponiveis.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Icon(Icons.event_busy_rounded, color: Colors.white24, size: 48),
              const SizedBox(height: 16),
              const Text(
                'Nenhum horário disponível para esta data.\nTente outro dia ou verifique o expediente.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white54, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.auto_awesome_rounded, color: Colors.amberAccent, size: 16),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Horários Disponíveis (Já adaptados às pausas)',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'Os horários abaixo são calculados para que você seja atendido sem esperas.',
          style: TextStyle(color: Colors.white38, fontSize: 11),
        ),
        const SizedBox(height: 16),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: slotsDisponiveis.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4,
            mainAxisExtent: 50,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemBuilder: (context, index) {
            final item = slotsDisponiveis[index];
            final TimeOfDay time = item['time'];
            final isSelected = _horaSelecionada?.hour == time.hour && _horaSelecionada?.minute == time.minute;

            return InkWell(
              onTap: () {
                setState(() {
                  _horaSelecionada = time;
                  _verificandoDisponibilidade = true;
                });
                Future.delayed(const Duration(milliseconds: 600), () {
                  if (mounted) setState(() => _verificandoDisponibilidade = false);
                });
              },
              borderRadius: BorderRadius.circular(12),
              child: Container(
                decoration: BoxDecoration(
                  color: isSelected ? _primaryColor : Colors.white.withAlpha(12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected ? _primaryColor : Colors.white.withAlpha(25),
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    fontSize: 15,
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildStepProfissional() {
    final dataService = Provider.of<DataService>(context);
    final funcionarios = dataService.funcionarios.where((f) => f.ativo).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStepTitle('Escolha o Profissional', 'Quem você gostaria que atendesse seu pet?'),
        const SizedBox(height: 32),
        
        // Opção "Qualquer Profissional"
        _buildProfissionalCard(
          id: null,
          nome: 'Qualquer Profissional',
          detalhes: 'O profissional disponível no horário escolhido.',
          isSelected: _funcionarioSelecionadoId == null,
          onTap: () {
            setState(() {
              _funcionarioSelecionadoId = null;
              _funcionarioSelecionadoNome = null;
            });
          },
        ),
        const SizedBox(height: 12),
        
        ...funcionarios.map((f) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _buildProfissionalCard(
            id: f.id,
            nome: f.nome,
            detalhes: 'Profissional especialista', // Pode adicionar especialidade no futuro
            isSelected: _funcionarioSelecionadoId == f.id,
            onTap: () {
              setState(() {
                _funcionarioSelecionadoId = f.id;
                _funcionarioSelecionadoNome = f.nome;
              });
            },
          ),
        )),
      ],
    );
  }

  Widget _buildProfissionalCard({
    required String? id,
    required String nome,
    required String detalhes,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? _primaryColor.withOpacity(0.1) : (_isDark ? Colors.white.withAlpha(12) : Colors.grey[100]),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? _primaryColor : (_isDark ? Colors.white.withAlpha(25) : Colors.grey[300]!),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: isSelected ? _primaryColor : (_isDark ? Colors.white.withAlpha(25) : Colors.grey[300]),
                shape: BoxShape.circle,
              ),
              child: Icon(
                id == null ? Icons.people_rounded : Icons.person_rounded,
                color: isSelected ? Colors.white : (_isDark ? Colors.white38 : Colors.grey[600]),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    nome,
                    style: TextStyle(
                      color: isSelected ? Colors.white : (_isDark ? Colors.white70 : Colors.black87),
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      fontSize: 16,
                    ),
                  ),
                  Text(
                    detalhes,
                    style: TextStyle(
                      color: isSelected ? _primaryColor : Colors.grey[500],
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Icon(Icons.check_circle_rounded, color: _primaryColor),
          ],
        ),
      ),
    );
  }

  Widget _buildStepHorario() {
    final dataService = Provider.of<DataService>(context);
    final agendamentoConfig = dataService.empresaAtual?.configuracoes?['agendamento'] as Map<String, dynamic>?;
    final bool modoSolicitacao = agendamentoConfig?['modoSolicitacao'] as bool? ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStepTitle(
          modoSolicitacao 
              ? 'Quando você gostaria de ser atendido?' 
              : 'Quando podemos receber vocês?',
          modoSolicitacao 
              ? 'Escolha a data e o horário de sua preferência. Confirmaremos sua solicitação em breve!' 
              : 'Escolha a data e veja os horários disponíveis.',
        ),
        const SizedBox(height: 32),

        if (modoSolicitacao) ...[
          // === MODO SOLICITAÇÃO: Só date picker + time picker livre ===
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.amber.withOpacity(0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.amber.withAlpha(51)),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline_rounded, color: Colors.amberAccent, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Sua solicitação será analisada e confirmada pela nossa equipe.',
                    style: TextStyle(color: Colors.amber[200], fontSize: 12, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: _buildPickerTile(
                  label: 'Data Desejada',
                  value: _dataSelecionada == null 
                      ? 'Selecionar' 
                      : DateFormat('dd/MM/yyyy').format(_dataSelecionada!),
                  icon: Icons.calendar_today_rounded,
                  onTap: _pickDate,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildPickerTile(
                  label: 'Horário Desejado',
                  value: _horaSelecionada == null 
                      ? 'Selecionar' 
                      : '${_horaSelecionada!.hour.toString().padLeft(2, '0')}:${_horaSelecionada!.minute.toString().padLeft(2, '0')}',
                  icon: Icons.access_time_rounded,
                  onTap: _pickTime,
                ),
              ),
            ],
          ),
        ] else ...[
          // === MODO AGENDA INTELIGENTE: Grade de disponibilidade ===
          Row(
            children: [
              Expanded(
                child: _buildPickerTile(
                  label: 'Data',
                  value: _dataSelecionada == null 
                      ? 'Selecionar' 
                      : DateFormat('dd/MM/yyyy').format(_dataSelecionada!),
                  icon: Icons.calendar_today_rounded,
                  onTap: _pickDate,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildPickerTile(
                  label: _horaSelecionada == null ? 'Selecione abaixo ↓' : 'Horário Escolhido',
                  value: _horaSelecionada == null 
                      ? '--:--' 
                      : '${_horaSelecionada!.hour.toString().padLeft(2, '0')}:${_horaSelecionada!.minute.toString().padLeft(2, '0')}',
                  icon: Icons.access_time_rounded,
                  onTap: null, // Não permite seleção manual — apenas pelos slots abaixo
                ),
              ),
            ],
          ),
          
          if (_dataSelecionada != null) ...[
            const SizedBox(height: 32),
            _buildHorariosGrid(),
          ],

          const SizedBox(height: 32),
          if (_dataSelecionada != null && _horaSelecionada != null)
            _buildDisponibilidadeCheck(),
        ],
      ],
    );
  }

  double _timeToDouble(String timeStr) {
    try {
      final parts = timeStr.split(':');
      if (parts.length != 2) return 0.0;
      return int.parse(parts[0]) + (int.parse(parts[1]) / 60.0);
    } catch (_) {
      return 0.0;
    }
  }

  /// Verifica se um horário está bloqueado administrativamente
  /// Suporta tipos: todos, dia, periodo, diaSemana (e bloqueios antigos sem tipo)
  bool _isHorarioBloqueadoAdmin(DataService dataService, DateTime inicio, int duracaoMinutos) {
    try {
      final config = dataService.empresaAtual?.configuracoes?['agendamento'] as Map<String, dynamic>?;
      
      // -- VERIFICAR HORÁRIO DE FUNCIONAMENTO --
      final hAberturaStr = config?['horarioAbertura']?.toString() ?? '08:00';
      final hFechamentoStr = config?['horarioFechamento']?.toString() ?? '18:00';
      
      final hAbertura = _timeToDouble(hAberturaStr);
      final hFechamento = _timeToDouble(hFechamentoStr);
      
      final double hInicio = inicio.hour + (inicio.minute / 60.0);
      final double hFim = hInicio + (duracaoMinutos / 60.0);
      
      // Se começar antes de abrir ou TERMINAR depois de fechar, está bloqueado.
      if (hInicio < hAbertura || hFim > hFechamento) {
        return true;
      }

      final bloqueados = config?['horariosIndisponiveis'] as List<dynamic>?;
      if (bloqueados == null || bloqueados.isEmpty) return false;

      final double horaInicio = inicio.hour + inicio.minute / 60.0;
      final double horaFim = horaInicio + (duracaoMinutos / 60.0);
      final String dataStr = '${inicio.year}-${inicio.month.toString().padLeft(2, '0')}-${inicio.day.toString().padLeft(2, '0')}';
      final int diaSemana = inicio.weekday; // 1=Mon ... 7=Sun

      for (final b in bloqueados) {
        final bMap = Map<String, dynamic>.from(b);
        final String? bInicioStr = bMap['inicio'] as String?;
        final String? bFimStr = bMap['fim'] as String?;
        if (bInicioStr == null || bFimStr == null) continue;

        // Verificar se o bloqueio se aplica à data
        final String tipo = bMap['tipo']?.toString() ?? 'todos';
        bool aplicavel = false;

        switch (tipo) {
          case 'dia':
            aplicavel = bMap['data'] == dataStr;
            break;
          case 'periodo':
            final di = bMap['dataInicio']?.toString();
            final df = bMap['dataFim']?.toString();
            if (di != null && df != null) {
              aplicavel = dataStr.compareTo(di) >= 0 && dataStr.compareTo(df) <= 0;
            }
            break;
          case 'diaSemana':
            final dias = bMap['diasSemana'];
            if (dias is List) {
              aplicavel = dias.any((d) => d == diaSemana);
            }
            break;
          case 'todos':
          default:
            if (bMap['data'] != null && tipo == 'todos') {
              aplicavel = bMap['data'] == dataStr;
            } else {
              aplicavel = true;
            }
            break;
        }

        if (!aplicavel) continue;

        final bInParts = bInicioStr.split(':');
        final bFiParts = bFimStr.split(':');
        if (bInParts.length != 2 || bFiParts.length != 2) continue;
        final double bIn = int.parse(bInParts[0]) + int.parse(bInParts[1]) / 60.0;
        final double bFi = int.parse(bFiParts[0]) + int.parse(bFiParts[1]) / 60.0;

        if (horaInicio < bFi && horaFim > bIn) {
          return true;
        }
      }
    } catch (_) {}
    return false;
  }

  Widget _buildDisponibilidadeCheck() {
    if (_verificandoDisponibilidade) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: _isDark ? Colors.white.withAlpha(12) : Colors.grey[200],
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70),
            ),
            const SizedBox(width: 16),
            Text(
              'Verificando agenda...',
              style: TextStyle(color: _isDark ? Colors.white70 : Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    final dataService = Provider.of<DataService>(context);
    final inicio = DateTime(
      _dataSelecionada!.year,
      _dataSelecionada!.month,
      _dataSelecionada!.day,
      _horaSelecionada!.hour,
      _horaSelecionada!.minute,
    );
    
    final selecionados = dataService.servicos.where((s) => _servicosSelecionadosIds.contains(s.id)).toList();
    if (selecionados.isEmpty) return const SizedBox();

    final int duracaoTotal = selecionados.fold(0, (sum, s) => sum + (s.duracaoPadraoMinutos ?? 60));
    final int intervaloMaximo = selecionados.fold(0, (max, s) => (s.intervaloMinutos ?? 0) > max ? (s.intervaloMinutos ?? 0) : max);
    
    // Verificar se é um horário bloqueado administrativamente (para mensagem específica)
    bool isBloqueadoAdmin = _isHorarioBloqueadoAdmin(dataService, inicio, duracaoTotal);

    bool disponivel = dataService.checkDisponibilidade(
      inicio, 
      duracaoTotal, 
      intervaloMinutos: intervaloMaximo,
      ignorarPendentes: false
    );

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: disponivel 
            ? Colors.green.withAlpha(25) 
            : (isBloqueadoAdmin ? Colors.red.withAlpha(25) : _primaryColor.withAlpha(25)),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: disponivel 
              ? Colors.green.withOpacity(0.3) 
              : (isBloqueadoAdmin ? Colors.red.withOpacity(0.3) : _primaryColor.withOpacity(0.3)),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: disponivel ? Colors.green : (isBloqueadoAdmin ? Colors.red : _primaryColor),
              shape: BoxShape.circle,
            ),
            child: Icon(
              disponivel ? Icons.check : (isBloqueadoAdmin ? Icons.block_rounded : Icons.notification_important_rounded),
              color: Colors.white,
              size: 16,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  disponivel 
                      ? 'Ótima escolha!' 
                      : (isBloqueadoAdmin ? 'Horário Indisponível' : 'Solicitação de Agendamento'),
                  style: TextStyle(
                    color: disponivel ? Colors.green[300] : (isBloqueadoAdmin ? Colors.red[300] : Colors.white),
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  disponivel 
                    ? 'Esse horário está livre em nossa agenda.' 
                    : (isBloqueadoAdmin 
                        ? 'Este horário não está disponível para agendamentos. Por favor, escolha outro horário.'
                        : 'Faremos o possível para te atender! Prosiga com o agendamento e aguarde nossa confirmação.'),
                  style: TextStyle(
                    color: disponivel 
                        ? Colors.green[100]?.withOpacity(0.7) 
                        : (isBloqueadoAdmin ? Colors.red[100]?.withOpacity(0.7) : Colors.white.withOpacity(0.7)),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Helpers UI
  Widget _buildStepTitle(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GoogleFonts.outfit(
            color: _isDark ? Colors.white : Colors.black87,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: TextStyle(
            color: _isDark ? _LojaPublicaStyle.textSecondaryColor : Colors.grey[600],
            fontSize: 14,
          ),
        ),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required String placeholder,
    TextInputType? keyboardType,
    int maxLines = 1,
    String? Function(String?)? validator,
    void Function(String)? onChanged,
    Widget? suffixIcon,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(color: _isDark ? Colors.white70 : Colors.grey[700], fontSize: 13, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          validator: validator,
          onChanged: onChanged,
          maxLines: maxLines,
          style: TextStyle(color: _isDark ? Colors.white : Colors.black87, fontSize: 16),
          decoration: InputDecoration(
            hintText: placeholder,
            hintStyle: TextStyle(color: _isDark ? Colors.white.withAlpha(51) : Colors.grey[400]),
            prefixIcon: Icon(icon, color: _primaryColor, size: 20),
            suffixIcon: suffixIcon,
            filled: true,
            fillColor: _isDark ? Colors.white.withAlpha(12) : Colors.grey[100],
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: _isDark ? Colors.white.withAlpha(25) : Colors.grey[300]!),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: _isDark ? Colors.white.withAlpha(25) : Colors.grey[300]!),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: _primaryColor, width: 2),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Colors.redAccent),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDropdown<T>({
    required String label,
    required IconData icon,
    required T value,
    required List<DropdownMenuItem<T>> items,
    required void Function(T?) onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(color: _isDark ? Colors.white70 : Colors.grey[700], fontSize: 13, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: _isDark ? Colors.white.withAlpha(12) : Colors.grey[100],
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _isDark ? Colors.white.withAlpha(25) : Colors.grey[300]!),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              value: value,
              items: items,
              onChanged: onChanged,
              isExpanded: true,
              icon: Icon(Icons.arrow_drop_down, color: _primaryColor),
              dropdownColor: _isDark ? _LojaPublicaStyle.cardColor : Colors.white,
              style: TextStyle(color: _isDark ? Colors.white : Colors.black87, fontSize: 16),
            ),
          ),
        ),
      ],
    );
  }


  Widget _buildPickerTile({
    required String label,
    required String value,
    required IconData icon,
    VoidCallback? onTap,
  }) {
    final bool desabilitado = onTap == null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(color: _isDark ? Colors.white70 : Colors.grey[700], fontSize: 13),
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            decoration: BoxDecoration(
              color: desabilitado
                  ? (_isDark ? Colors.white.withOpacity(0.02) : Colors.grey[50])
                  : (_isDark ? Colors.white.withAlpha(12) : Colors.grey[100]),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: desabilitado
                    ? (_isDark ? Colors.white.withAlpha(12) : Colors.grey[200]!)
                    : (_isDark ? Colors.white.withAlpha(25) : Colors.grey[300]!),
              ),
            ),
            child: Row(
              children: [
                Icon(icon, color: desabilitado ? (_isDark ? Colors.white24 : Colors.grey[400]) : _primaryColor, size: 20),
                const SizedBox(width: 12),
                Text(
                  value,
                  style: TextStyle(
                    color: (value == 'Selecionar' || value == '--:--')
                        ? (_isDark ? Colors.white24 : Colors.grey[400])
                        : desabilitado
                            ? (_isDark ? Colors.white54 : Colors.grey[600])
                            : (_isDark ? Colors.white : Colors.black87),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNavigationButtons(Color primaryColor, bool moduloPet) {
    final agendamentoConfig = Provider.of<DataService>(context, listen: false).empresaAtual?.configuracoes?['agendamento'] as Map<String, dynamic>? ?? {};
    final bool permiteProfissional = agendamentoConfig['permitirEscolhaProfissional'] == true;
    final List<int> passosReaisHabilitados = [0, 1];
    if (moduloPet) passosReaisHabilitados.add(2);
    if (moduloPet && _mostrarPassoEntrega) passosReaisHabilitados.add(3);
    if (permiteProfissional) passosReaisHabilitados.add(5);
    passosReaisHabilitados.add(4); // Horário sempre por último

    final int maxIndex = passosReaisHabilitados.length - 1;
    final bool noUltimoPasso = _currentStep == maxIndex;

    return Column(
      children: [
        if (noUltimoPasso && moduloPet)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _enviando ? null : () => _adicionarAoCarrinho(moduloPet),
                icon: const Icon(Icons.add_circle_outline),
                label: const Text('Solicitar para outro Pet', style: TextStyle(fontWeight: FontWeight.bold)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: primaryColor,
                  side: BorderSide(color: primaryColor),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ),
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            if (_currentStep > 0)
              TextButton.icon(
                onPressed: () => setState(() => _currentStep--),
                icon: const Icon(Icons.arrow_back_rounded, size: 18),
                label: const Text('Voltar'),
                style: TextButton.styleFrom(
                  foregroundColor: _isDark ? _LojaPublicaStyle.textSecondaryColor : Colors.grey[600],
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                ),
              )
            else
              const SizedBox(),
            
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(left: 12),
                child: ElevatedButton(
                  onPressed: _enviando ? null : () => _onNext(moduloPet),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: _enviando ? 0 : 8,
                    shadowColor: primaryColor.withOpacity(0.5),
                  ),
                  child: Ink(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: _enviando 
                          ? [Colors.grey, Colors.grey.withOpacity(0.8)]
                          : [primaryColor, primaryColor.withOpacity(0.8)],
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (_enviando)
                            const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          else ...[
                            Text(
                              noUltimoPasso 
                                ? (_agendamentosCarrinho.isEmpty ? 'Enviar Solicitação' : 'Enviar TODAS (${_agendamentosCarrinho.length + 1})') 
                                : 'Próximo Passo',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
                            ),
                            const SizedBox(width: 12),
                            const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 18),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _onNext(bool moduloPet) {
    if (_enviando) return;
    if (_currentStep == 0 && _servicosSelecionadosIds.isEmpty) {
      _showWarning('Por favor, escolha um serviço primeiro.');
      return;
    }

    final agendamentoConfig = Provider.of<DataService>(context, listen: false).empresaAtual?.configuracoes?['agendamento'] as Map<String, dynamic>? ?? {};
    final bool permiteProfissional = agendamentoConfig['permitirEscolhaProfissional'] == true;
    final List<int> passosReaisHabilitados = [0, 1];
    if (moduloPet) passosReaisHabilitados.add(2);
    if (moduloPet && _mostrarPassoEntrega) passosReaisHabilitados.add(3);
    if (permiteProfissional) passosReaisHabilitados.add(5);
    passosReaisHabilitados.add(4); // Horário sempre por último

    final int maxIndex = passosReaisHabilitados.length - 1;

    if (_formKey.currentState!.validate()) {
      if (_currentStep < maxIndex) {
        setState(() => _currentStep++);
      } else {
        _finalizar(moduloPet);
      }
    }
  }

  Future<void> _finalizar(bool moduloPet) async {
    if (_dataSelecionada == null || _horaSelecionada == null) {
      _showWarning('Selecione a data e o horário desejado.');
      return;
    }

    final dataService = Provider.of<DataService>(context, listen: false);

    // Verificação extra de horário bloqueado administrativamente (apenas no modo agenda inteligente)
    final agendamentoConfig = dataService.empresaAtual?.configuracoes?['agendamento'] as Map<String, dynamic>?;
    final bool modoSolicitacao = agendamentoConfig?['modoSolicitacao'] as bool? ?? false;

    if (!modoSolicitacao) {
      try {
        final inicio = DateTime(
          _dataSelecionada!.year,
          _dataSelecionada!.month,
          _dataSelecionada!.day,
          _horaSelecionada!.hour,
          _horaSelecionada!.minute,
        );
        final selecionadosCheck = dataService.servicos.where((s) => _servicosSelecionadosIds.contains(s.id)).toList();
        final duracaoCheck = selecionadosCheck.fold(0, (sum, s) => sum + (s.duracaoPadraoMinutos ?? 60));
        
        if (_isHorarioBloqueadoAdmin(dataService, inicio, duracaoCheck)) {
          _showError('Este horário não está disponível para agendamentos. Por favor, escolha outro.');
          return;
        }
      } catch (_) {}
    }

    setState(() => _enviando = true);

    final authService = Provider.of<AuthService>(context, listen: false);

    try {
      // 1. Criar o agendamento atual (o último que está sendo editado)
      final dataAgendamentoAtual = DateTime(
        _dataSelecionada!.year,
        _dataSelecionada!.month,
        _dataSelecionada!.day,
        _horaSelecionada!.hour,
        _horaSelecionada!.minute,
      );

      final servicosSelecionados = dataService.servicos.where((s) => _servicosSelecionadosIds.contains(s.id)).toList();
      final servicoPrincipal = servicosSelecionados.isNotEmpty ? servicosSelecionados.first : dataService.servicos.first;
      final duracaoTotal = servicosSelecionados.fold(0, (sum, s) => sum + (s.duracaoPadraoMinutos ?? 60));
      final intervaloMaximo = servicosSelecionados.fold(0, (max, s) => (s.intervaloMinutos ?? 0) > max ? (s.intervaloMinutos ?? 0) : max);
      
      // Identificar cliente/pet para o agendamento atual
      final telefoneBusca = _whatsappController.text.replaceAll(RegExp(r'\D'), '');
      Cliente? clienteReal;
      Pet? petExistente;

      try {
        clienteReal = dataService.clientes.firstWhere(
          (c) => c.telefone.replaceAll(RegExp(r'\D'), '') == telefoneBusca
        );
      } catch (_) {}

      // Se não existe, criar o cliente agora
      if (clienteReal == null) {
        clienteReal = Cliente(
          id: 'pub_${DateTime.now().microsecondsSinceEpoch}',
          nome: _nomeController.text,
          telefone: _whatsappController.text,
          whatsapp: telefoneBusca,
          endereco: _enderecoRuaController.text.isNotEmpty ? _enderecoRuaController.text : null,
          numero: _enderecoNumeroController.text.isNotEmpty ? _enderecoNumeroController.text : null,
          bairro: _bairroController.text.isNotEmpty ? _bairroController.text : null,
          pets: [],
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        await dataService.addCliente(clienteReal);
        if (mounted) setState(() => _clienteEncontrado = clienteReal);
      } else {
        // Se existe mas algum dado no formulário é diferente, atualizar
        bool mudou = false;
        String novoNome = _nomeController.text;
        String novoEndereco = _enderecoRuaController.text;
        String novoNumero = _enderecoNumeroController.text;
        String novoBairro = _bairroController.text;

        if (novoNome.isNotEmpty && clienteReal.nome != novoNome) mudou = true;
        if (novoEndereco.isNotEmpty && clienteReal.endereco != novoEndereco) mudou = true;
        if (novoNumero.isNotEmpty && clienteReal.numero != novoNumero) mudou = true;
        if (novoBairro.isNotEmpty && clienteReal.bairro != novoBairro) mudou = true;

        if (mudou) {
          clienteReal = clienteReal.copyWith(
            nome: novoNome.isNotEmpty ? novoNome : clienteReal.nome,
            endereco: novoEndereco.isNotEmpty ? novoEndereco : clienteReal.endereco,
            numero: novoNumero.isNotEmpty ? novoNumero : clienteReal.numero,
            bairro: novoBairro.isNotEmpty ? novoBairro : clienteReal.bairro,
            updatedAt: DateTime.now()
          );
          await dataService.updateCliente(clienteReal);
        }
      }

      final bool moduloPet = dataService.empresaAtual?.moduloPet ?? false;

      // Tentar encontrar pet para o agendamento ATUAL (se não for multi-pet)
      if (moduloPet && !_modoMultiPets && _petNomeController.text.isNotEmpty) {
        try {
          petExistente = clienteReal.pets.firstWhere(
            (p) => p.nome.toLowerCase().trim() == _petNomeController.text.toLowerCase().trim()
          );
        } catch (_) {}
      }

      // 1. Criar agendamento(s) atual(is)
      final List<AgendamentoServico> agendamentosAtuais = [];
      
      if (_modoMultiPets && _petsMultiSelecionados.isNotEmpty) {
        final timestamp = DateTime.now().microsecondsSinceEpoch;
        int counter = 0;

        // Dividir o valor do Taxi Dog entre os pets agendados se houver mais de um
        double? valorTaxiDogPorPet = (moduloPet && _tipoEntrega != 'Retirada na Loja') ? _valorTaxiDog : null;
        if (valorTaxiDogPorPet != null && valorTaxiDogPorPet > 0 && _petsMultiSelecionados.length > 1) {
          valorTaxiDogPorPet = double.parse((valorTaxiDogPorPet / _petsMultiSelecionados.length).toStringAsFixed(2));
        }

        for (var pet in _petsMultiSelecionados) {
          agendamentosAtuais.add(AgendamentoServico(
            id: '${timestamp}_${pet.id}_$counter',
            numero: '',
            servicoId: servicoPrincipal.id,
            servico: servicoPrincipal,
            servicosIds: _servicosSelecionadosIds,
            servicos: servicosSelecionados,
            clienteId: clienteReal!.id,
            cliente: clienteReal,
            petId: pet.id,
            pet: pet,
            clienteNome: _nomeController.text,
            clienteTelefone: _whatsappController.text,
            petNome: pet.nome,
            dataAgendamento: dataAgendamentoAtual,
            duracaoMinutos: duracaoTotal,
            intervaloMinutos: intervaloMaximo,
            status: 'Aguardando Confirmação',
            tipoEntrega: moduloPet ? _tipoEntrega : null,
            bairroEntrega: moduloPet ? (_bairroEntrega ?? _bairroController.text) : null,
            valorTaxiDog: valorTaxiDogPorPet,
            endereco: _enderecoRuaController.text.isNotEmpty ? _enderecoRuaController.text : null,
            numeroEndereco: _enderecoNumeroController.text.isNotEmpty ? _enderecoNumeroController.text : null,
            complemento: _enderecoComplementoController.text.isNotEmpty ? _enderecoComplementoController.text : null,
            pontoReferencia: _pontoReferenciaController.text.isNotEmpty ? _pontoReferenciaController.text : null,
            observacoes: 'SOLICITAÇÃO ONLINE MÚLTIPLA',
          ));
          counter++;
        }
      } else {
        Pet? petInfoAtual = moduloPet ? Pet(
          id: petExistente?.id ?? 'temp_${DateTime.now().millisecondsSinceEpoch}',
          nome: _petNomeController.text,
          especie: _petEspecie,
          raca: _petRacaController.text,
          sexo: _petSexo,
          cor: _petCorController.text,
          tamanho: _porteAnimal,
          peso: _pesoAproximado,
          observacoes: _petObsController.text,
          updatedAt: DateTime.now(),
          createdAt: petExistente?.createdAt ?? DateTime.now(),
        ) : null;

        agendamentosAtuais.add(AgendamentoServico(
          id: '${DateTime.now().microsecondsSinceEpoch}_single',
          numero: '',
          servicoId: servicoPrincipal.id,
          servico: servicoPrincipal,
          servicosIds: _servicosSelecionadosIds,
          servicos: servicosSelecionados,
          clienteId: clienteReal!.id,
          cliente: clienteReal,
          petId: petInfoAtual?.id,
          pet: petInfoAtual,
          clienteNome: _nomeController.text,
          clienteTelefone: _whatsappController.text,
          petNome: moduloPet ? _petNomeController.text : null,
          dataAgendamento: dataAgendamentoAtual,
          duracaoMinutos: duracaoTotal,
          intervaloMinutos: intervaloMaximo,
          status: 'Aguardando Confirmação',
          tipoEntrega: moduloPet ? _tipoEntrega : null,
          bairroEntrega: moduloPet ? (_bairroEntrega ?? _bairroController.text) : null,
          valorTaxiDog: moduloPet && _tipoEntrega != 'Retirada na Loja' ? _valorTaxiDog : null,
          endereco: _enderecoRuaController.text.isNotEmpty ? _enderecoRuaController.text : null,
          numeroEndereco: _enderecoNumeroController.text.isNotEmpty ? _enderecoNumeroController.text : null,
          complemento: _enderecoComplementoController.text.isNotEmpty ? _enderecoComplementoController.text : null,
          pontoReferencia: _pontoReferenciaController.text.isNotEmpty ? _pontoReferenciaController.text : null,
          observacoes: 'SOLICITAÇÃO ONLINE DETALHADA',
          funcionarioId: _funcionarioSelecionadoId,
          funcionarioNome: _funcionarioSelecionadoNome,
        ));
      }

      // 2. Unir com agendamentos já salvos no carrinho local
      final List<AgendamentoServico> todos = [..._agendamentosCarrinho, ...agendamentosAtuais];
      bool algumOcupado = false;

      // Garantir empresa ativa
      if (dataService.empresaIdAtual == null) {
        final slugParaUsar = widget.slugEmpresa;
        if (slugParaUsar != null) {
          final emp = authService.obterEmpresaPorSlug(slugParaUsar);
          if (emp != null) await dataService.definirEmpresaAtual(emp.id);
        }
      }

      // 3. Processar envio de todos, garantindo pets no cliente
      for (var agd in todos) {
        var agdFinal = agd.copyWith(
          clienteId: clienteReal!.id,
          cliente: clienteReal,
        );

        // SINCRONIZAÇÃO DE ENDEREÇO: Garantir que o endereço do agendamento seja salvo no cadastro do cliente se houver mudanças
        final endAgd = agdFinal.endereco?.trim() ?? '';
        final numAgd = agdFinal.numeroEndereco?.trim() ?? '';
        final bairroAgd = (agdFinal.bairroEntrega ?? _bairroController.text).trim();

        if (endAgd.isNotEmpty && (
            endAgd != (clienteReal!.endereco ?? '').trim() ||
            numAgd != (clienteReal!.numero ?? '').trim() ||
            bairroAgd != (clienteReal!.bairro ?? '').trim()
        )) {
          clienteReal = clienteReal!.copyWith(
            endereco: endAgd,
            numero: numAgd,
            complemento: agdFinal.complemento?.trim(),
            pontoReferencia: agdFinal.pontoReferencia?.trim(),
            bairro: bairroAgd,
            updatedAt: DateTime.now(),
          );
          await dataService.updateCliente(clienteReal!);
          agdFinal = agdFinal.copyWith(cliente: clienteReal);
        }

        if (moduloPet && agdFinal.petNome != null && agdFinal.petNome!.isNotEmpty) {
          Pet? petNoCliente;
          try {
            petNoCliente = clienteReal.pets.firstWhere(
              (p) => p.nome.toLowerCase().trim() == agdFinal.petNome!.toLowerCase().trim()
            );
          } catch (_) {}

          if (petNoCliente == null) {
            // Novo pet, adicionar ao cliente
            final novoPet = agdFinal.pet ?? Pet(
              id: 'per_${DateTime.now().microsecondsSinceEpoch}',
              nome: agdFinal.petNome!,
              updatedAt: DateTime.now(),
              createdAt: DateTime.now(),
            );
            final List<Pet> novosPets = [...clienteReal.pets, novoPet];
            clienteReal = clienteReal.copyWith(pets: novosPets, updatedAt: DateTime.now());
            await dataService.updateCliente(clienteReal);
            petNoCliente = novoPet;
          }

          agdFinal = agdFinal.copyWith(
            petId: petNoCliente!.id,
            pet: petNoCliente,
          );

          // Se o pet está sendo editado, atualizar seus dados agora
          if (!_modoMultiPets && _petSendoEditado != null && _petSendoEditado!.id == petNoCliente.id && _mostrarFormularioPet) {
            final petAtualizado = petNoCliente.copyWith(
              nome: _petNomeController.text,
              especie: _petEspecie,
              raca: _petRacaController.text,
              sexo: _petSexo,
              cor: _petCorController.text,
              tamanho: _porteAnimal,
              peso: _pesoAproximado,
              observacoes: _petObsController.text,
              updatedAt: DateTime.now(),
            );
            
            // Atualizar na lista do cliente
            final List<Pet> novosPets = clienteReal!.pets.map((p) => p.id == petAtualizado.id ? petAtualizado : p).toList();
            clienteReal = clienteReal!.copyWith(pets: novosPets, updatedAt: DateTime.now());
            await dataService.updateCliente(clienteReal!);
            
            agdFinal = agdFinal.copyWith(pet: petAtualizado, petNome: petAtualizado.nome);
          }
        }

        final disponivel = dataService.checkDisponibilidade(
          agdFinal.dataAgendamento, 
          agdFinal.duracaoMinutos, 
          intervaloMinutos: agdFinal.intervaloMinutos,
          ignorarPendentes: false
        );
        if (!disponivel) algumOcupado = true;
        
        await dataService.addAgendamentoServico(agdFinal);
      }

      // Garantir que a UI local seja notificada (refresh do carrinho/contadores)
      dataService.notifyListeners();

      if (mounted) {
        final configAgd = (dataService.empresaAtual?.configuracoes?['agendamento'] as Map<String, dynamic>?) ?? {};
        _mostrarSucesso(
          horarioOcupado: algumOcupado, 
          agendamentosEnviados: todos, 
          whatsappLoja: configAgd['whatsappContato']?.toString()
        );
      }

    } catch (e) {
      debugPrint('Erro ao finalizar: $e');
      _showError('Erro ao processar sua solicitação. Tente novamente.');
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }


  Widget _buildResumoCarrinho(Color primaryColor, bool esconderValores) {
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: primaryColor.withAlpha(12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: primaryColor.withAlpha(51)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.shopping_basket_rounded, color: primaryColor, size: 20),
              const SizedBox(width: 10),
              Text(
                'Suas Solicitações (${_agendamentosCarrinho.length})',
                style: GoogleFonts.outfit(color: _isDark ? Colors.white : Colors.black87, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ..._agendamentosCarrinho.map((agd) => Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _isDark ? Colors.white.withOpacity(0.03) : Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: primaryColor.withAlpha(25),
                  radius: 18,
                  child: Icon(agd.pet != null ? Icons.pets : Icons.style, color: primaryColor, size: 16),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${agd.petNome ?? 'Serviço'} - ${agd.servico?.nome ?? ''}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
                      ),
                      Text(
                        '${DateFormat('dd/MM HH:mm').format(agd.dataAgendamento)}',
                        style: TextStyle(color: _isDark ? Colors.white54 : Colors.black54, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline, color: Colors.redAccent, size: 20),
                  onPressed: () => setState(() => _agendamentosCarrinho.remove(agd)),
                ),
              ],
            ),
          )).toList(),
        ],
      ),
    );
  }

  void _adicionarAoCarrinho(bool moduloPet) {
    if (_dataSelecionada == null || _horaSelecionada == null) {
      _showWarning('Selecione a data e o horário desejado.');
      return;
    }

    final dataService = Provider.of<DataService>(context, listen: false);

    // Verificação de horário bloqueado administrativamente (apenas no modo agenda inteligente)
    final agendConfig = dataService.empresaAtual?.configuracoes?['agendamento'] as Map<String, dynamic>?;
    final bool modoSolicitacaoCarrinho = agendConfig?['modoSolicitacao'] as bool? ?? false;

    if (!modoSolicitacaoCarrinho) {
      try {
        final inicio = DateTime(
          _dataSelecionada!.year,
          _dataSelecionada!.month,
          _dataSelecionada!.day,
          _horaSelecionada!.hour,
          _horaSelecionada!.minute,
        );
        final selecionadosCart = dataService.servicos.where((s) => _servicosSelecionadosIds.contains(s.id)).toList();
        final duracaoCart = selecionadosCart.fold(0, (sum, s) => sum + (s.duracaoPadraoMinutos ?? 60));
        
        if (_isHorarioBloqueadoAdmin(dataService, inicio, duracaoCart)) {
          _showError('Este horário não está disponível para agendamentos.');
          return;
        }
      } catch (_) {}
    }
    final dataAgendamento = DateTime(
      _dataSelecionada!.year,
      _dataSelecionada!.month,
      _dataSelecionada!.day,
      _horaSelecionada!.hour,
      _horaSelecionada!.minute,
    );

    final selecionados = dataService.servicos.where((s) => _servicosSelecionadosIds.contains(s.id)).toList();
    final servico = selecionados.isNotEmpty ? selecionados.first : dataService.servicos.first;
    
    // Identificar cliente/pet existentes se possível
    final telefoneBusca = _whatsappController.text.replaceAll(RegExp(r'\D'), '');
    Cliente? clienteExistente = _clienteEncontrado;
    Pet? petExistente;

    if (moduloPet && clienteExistente != null && _petNomeController.text.isNotEmpty) {
      try {
        petExistente = clienteExistente.pets.firstWhere(
          (p) => p.nome.toLowerCase().trim() == _petNomeController.text.toLowerCase().trim()
        );
      } catch (_) {}
    }

    final List<AgendamentoServico> agendamentosNovos = [];
    final timestamp = DateTime.now().microsecondsSinceEpoch;

    if (_modoMultiPets && _petsMultiSelecionados.isNotEmpty) {
      int counter = 0;
      for (var pet in _petsMultiSelecionados) {
        agendamentosNovos.add(AgendamentoServico(
          id: '${timestamp}_cart_${pet.id}_$counter',
          numero: '',
          servicoId: servico.id,
          servico: servico,
          clienteId: clienteExistente?.id ?? 'publico',
          cliente: clienteExistente,
          petId: pet.id,
          pet: pet,
          clienteNome: _nomeController.text,
          clienteTelefone: _whatsappController.text,
          petNome: pet.nome,
          dataAgendamento: dataAgendamento,
          duracaoMinutos: servico.duracaoPadraoMinutos ?? 60,
          intervaloMinutos: servico.intervaloMinutos ?? 0,
          status: 'Aguardando Confirmação',
          tipoEntrega: moduloPet ? _tipoEntrega : null,
          bairroEntrega: moduloPet && _tipoEntrega != 'Retirada na Loja' ? _bairroEntrega : null,
          valorTaxiDog: moduloPet && _tipoEntrega != 'Retirada na Loja' ? _valorTaxiDog : null,
          endereco: _enderecoRuaController.text.isNotEmpty ? _enderecoRuaController.text : null,
          numeroEndereco: _enderecoNumeroController.text.isNotEmpty ? _enderecoNumeroController.text : null,
          complemento: _enderecoComplementoController.text.isNotEmpty ? _enderecoComplementoController.text : null,
          pontoReferencia: _pontoReferenciaController.text.isNotEmpty ? _pontoReferenciaController.text : null,
          observacoes: 'SOLICITAÇÃO ONLINE ADICIONAL (MULTI)',
          funcionarioId: _funcionarioSelecionadoId,
          funcionarioNome: _funcionarioSelecionadoNome,
        ));
        counter++;
      }
    } else {
      final petInfo = moduloPet ? Pet(
        id: petExistente?.id ?? 'novo_${DateTime.now().microsecondsSinceEpoch}',
        nome: _petNomeController.text,
        especie: _petEspecie,
        raca: _petRacaController.text,
        sexo: _petSexo,
        cor: _petCorController.text,
        tamanho: _porteAnimal,
        peso: _pesoAproximado,
        observacoes: _petObsController.text,
        updatedAt: DateTime.now(),
        createdAt: petExistente?.createdAt ?? DateTime.now(),
      ) : null;

      agendamentosNovos.add(AgendamentoServico(
        id: '${timestamp}_cart_single',
        numero: '',
        servicoId: servico.id,
        servico: servico,
        clienteId: clienteExistente?.id ?? 'publico',
        cliente: clienteExistente,
        petId: petInfo?.id,
        pet: petInfo,
        clienteNome: _nomeController.text,
        clienteTelefone: _whatsappController.text,
        petNome: moduloPet ? _petNomeController.text : null,
        dataAgendamento: dataAgendamento,
        duracaoMinutos: servico.duracaoPadraoMinutos ?? 60,
        intervaloMinutos: servico.intervaloMinutos ?? 0,
        status: 'Aguardando Confirmação',
        tipoEntrega: moduloPet ? _tipoEntrega : null,
        bairroEntrega: moduloPet && _tipoEntrega != 'Retirada na Loja' ? _bairroEntrega : null,
        valorTaxiDog: moduloPet && _tipoEntrega != 'Retirada na Loja' ? _valorTaxiDog : null,
        endereco: _enderecoRuaController.text.isNotEmpty ? _enderecoRuaController.text : null,
        numeroEndereco: _enderecoNumeroController.text.isNotEmpty ? _enderecoNumeroController.text : null,
        complemento: _enderecoComplementoController.text.isNotEmpty ? _enderecoComplementoController.text : null,
        pontoReferencia: _pontoReferenciaController.text.isNotEmpty ? _pontoReferenciaController.text : null,
        observacoes: 'SOLICITAÇÃO ONLINE ADICIONAL',
        funcionarioId: _funcionarioSelecionadoId,
        funcionarioNome: _funcionarioSelecionadoNome,
      ));
    }

    setState(() {
      _agendamentosCarrinho.addAll(agendamentosNovos);
      // Resetar campos
      _servicosSelecionadosIds = [];
      _petNomeController.clear();
      _petRacaController.clear();
      _petCorController.clear();
      _petObsController.clear();
      _petsMultiSelecionados.clear(); // Limpar seleção multi após adicionar ao carrinho
      // Não resetar endereço se for o mesmo cliente (Mantendo preenchido para o próximo pet)
      _dataSelecionada = null;
      _horaSelecionada = null;
      _currentStep = 0; // Volta para o início para o próximo pet
    });

    _showWarning('Solicitação adicionada! Você pode adicionar outro agendamento agora.');
  }

  Future<void> _abrirWhatsAppNotificacao(String whatsapp, List<AgendamentoServico> agendamentos) async {
    try {
      final String tel = whatsapp.replaceAll(RegExp(r'\D'), '');
      if (tel.isEmpty) return;

      String mensagem = "*Novo Agendamento Realizado*\n\n";
      mensagem += "*Cliente:* ${_nomeController.text}\n";
      mensagem += "*WhatsApp:* ${_whatsappController.text}\n\n";
      
      for (var agd in agendamentos) {
        mensagem += "--------------------------\n";
        mensagem += "*Serviço:* ${agd.servico?.nome}\n";
        if (agd.petNome != null) mensagem += "*Pet:* ${agd.petNome}\n";
        if (agd.funcionarioNome != null) mensagem += "*Profissional:* ${agd.funcionarioNome}\n";
        mensagem += "*Data:* ${DateFormat('dd/MM/yyyy HH:mm').format(agd.dataAgendamento)}\n";
        if (agd.tipoEntrega != null) mensagem += "*Entrega:* ${agd.tipoEntrega}\n";
        if (agd.valorTaxiDog != null && agd.valorTaxiDog! > 0) mensagem += "*Taxa Taxi Dog:* R\$ ${agd.valorTaxiDog!.toStringAsFixed(2)}\n";
      }

      final String uri = "https://wa.me/$tel?text=${Uri.encodeComponent(mensagem)}";
      
      final Uri url = Uri.parse(uri);
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('Erro ao abrir WhatsApp: $e');
    }
  }

  Widget _buildAgendamentoCardPublico(AgendamentoServico agd, Color primaryColor) {
    final statusColor = _getStatusColor(agd.status);
    final isDark = _isDark;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? _LojaPublicaStyle.cardColor : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isDark ? Colors.white.withAlpha(12) : Colors.black.withAlpha(12)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(25),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: statusColor.withAlpha(25),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(
              agd.pet != null ? Icons.pets_rounded : Icons.event_available_rounded,
              color: statusColor,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  agd.servico?.nome ?? 'Serviço',
                  style: GoogleFonts.outfit(
                    color: isDark ? Colors.white : Colors.black87,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 4),
                if (agd.petNome != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        Icon(Icons.pets, size: 12, color: isDark ? Colors.white54 : Colors.grey),
                        const SizedBox(width: 4),
                        Text(agd.petNome!, style: TextStyle(color: isDark ? Colors.white70 : Colors.black54, fontSize: 13)),
                      ],
                    ),
                  ),
                Row(
                  children: [
                    Icon(Icons.access_time_filled_rounded, size: 12, color: primaryColor),
                    const SizedBox(width: 4),
                    Text(
                      '${DateFormat('dd/MM').format(agd.dataAgendamento)} às ${DateFormat('HH:mm').format(agd.dataAgendamento)}',
                      style: TextStyle(color: isDark ? Colors.white54 : Colors.black54, fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: statusColor.withAlpha(51)),
                ),
                child: Text(
                  agd.status,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              if (agd.numero.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '#${agd.numero}',
                    style: TextStyle(color: isDark ? Colors.white24 : Colors.black12, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  void _mostrarSucesso({bool horarioOcupado = false, List<AgendamentoServico>? agendamentosEnviados, String? whatsappLoja}) {
    final cardColor = _isDark ? _LojaPublicaStyle.backgroundColor : Colors.grey[100];
    final textColor = _isDark ? Colors.white : const Color(0xFF1E293B);
    final primary = _primaryColor;
    final telCliente = _whatsappController.text;

    // Se temos agendamentos enviados, vamos mostrá-los de forma mais visual
    final List<AgendamentoServico> listaMostrar = agendamentosEnviados ?? [];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.9,
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(40)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 100),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.green.withAlpha(25),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.check_circle_rounded, color: Colors.green, size: 80),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Solicitação Recebida!',
                      style: GoogleFonts.outfit(color: textColor, fontSize: 28, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Agendamentos realizados com sucesso. Aguarde nossa equipe analisar e confirmar.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: textColor.withOpacity(0.6), fontSize: 16),
                    ),
                    const SizedBox(height: 32),
                    
                    if (listaMostrar.isNotEmpty) ...[
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Resumo do seu pedido:',
                          style: GoogleFonts.outfit(color: textColor, fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(height: 16),
                      ...listaMostrar.map((agd) => _buildAgendamentoCardPublico(agd, primary)).toList(),
                    ],

                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.orange.withAlpha(12),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.orange.withAlpha(51)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline_rounded, color: Colors.orange),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'O agendamento ainda NÃO está confirmado. Enviaremos uma atualização em breve.',
                              style: TextStyle(color: textColor.withOpacity(0.8), fontSize: 12, fontWeight: FontWeight.w500),
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    const SizedBox(height: 32),
                    if (whatsappLoja != null && whatsappLoja.isNotEmpty) ...[
                      const Text('Deseja agilizar?', style: TextStyle(color: Colors.white54, fontSize: 14)),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () => _abrirWhatsAppNotificacao(whatsappLoja, listaMostrar),
                          icon: const Icon(Icons.chat_bubble_rounded, color: Colors.white),
                          label: const Text('Notificar via WhatsApp', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF25D366),
                            padding: const EdgeInsets.symmetric(vertical: 18),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                            elevation: 0,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: _isDark ? _LojaPublicaStyle.cardColor : Colors.white,
                border: Border(top: BorderSide(color: Colors.white.withAlpha(12))),
              ),
              child: SafeArea(
                top: false,
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      // Resetar estado global
                      setState(() {
                        _currentStep = 0;
                        _agendamentosCarrinho.clear();
                        _servicosSelecionadosIds = [];
                        _nomeController.clear();
                        _whatsappController.clear();
                        _petNomeController.clear();
                        _petRacaController.clear();
                        _petEspecieController.clear();
                        _petCorController.clear();
                        _petObsController.clear();
                        _enderecoRuaController.clear();
                        _enderecoNumeroController.clear();
                        _enderecoComplementoController.clear();
                        _pontoReferenciaController.clear();
                        _dataSelecionada = null;
                        _horaSelecionada = null;
                      });
                      // Opcional: Abrir a lista de agendamentos automaticamente se tiver telefone
                      if (telCliente.isNotEmpty) {
                         Future.delayed(const Duration(milliseconds: 500), () => _exibirListaAgendamentos(telCliente, primary));
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primary,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      elevation: 8,
                      shadowColor: primary.withOpacity(0.4),
                    ),
                    child: const Text('Continuar Navegando', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 16)),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _mostrarConsultaAgendamentos(Color primaryColor) {
    final TextEditingController phoneController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _isDark ? _LojaPublicaStyle.cardColor : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            Icon(Icons.history_rounded, color: primaryColor),
            const SizedBox(width: 12),
            Text('Meus Agendamentos', style: GoogleFonts.outfit(color: _isDark ? Colors.white : Colors.black87, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Informe seu WhatsApp para consultar seus agendamentos realizados nesta empresa:', style: TextStyle(color: Colors.white70, fontSize: 14)),
            const SizedBox(height: 20),
            _buildTextField(
              controller: phoneController,
              label: 'WhatsApp',
              icon: Icons.phone_rounded,
              placeholder: '(00) 00000-0000',
              keyboardType: TextInputType.phone,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancelar', style: TextStyle(color: _isDark ? Colors.white54 : Colors.grey))),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _exibirListaAgendamentos(phoneController.text, primaryColor);
            },
            style: ElevatedButton.styleFrom(backgroundColor: primaryColor, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            child: const Text('Consultar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _exibirListaAgendamentos(String telefone, Color primaryColor) {
    final dataService = Provider.of<DataService>(context, listen: false);
    final String rawInput = telefone.replaceAll(RegExp(r'[^\d]'), '');
    
    if (rawInput.length < 8) {
      _showWarning('Por favor, informe um WhatsApp válido.');
      return;
    }

    final meusAgendamentos = dataService.agendamentosServico.where((a) {
      final String inputFlexivel = rawInput.substring(rawInput.length - 8);

      bool comparar(String? valor) {
        if (valor == null || valor.isEmpty) return false;
        final String v = valor.replaceAll(RegExp(r'[^\d]'), '');
        if (v.length < 8) return false;
        return v.contains(rawInput) || rawInput.contains(v) || v.contains(inputFlexivel);
      }

      if (comparar(a.clienteTelefone)) return true;
      if (comparar(a.cliente?.telefone)) return true;
      if (comparar(a.observacoes)) return true;
      
      return false;
    }).toList();

    // Ordenar por data (mais recente primeiro)
    meusAgendamentos.sort((a, b) => b.dataAgendamento.compareTo(a.dataAgendamento));

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: BoxDecoration(
          color: _isDark ? _LojaPublicaStyle.backgroundColor : Colors.grey[100],
          borderRadius: const BorderRadius.vertical(top: Radius.circular(40)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Seu Histórico', style: GoogleFonts.outfit(color: _isDark ? Colors.white : Colors.black87, fontSize: 26, fontWeight: FontWeight.bold)),
                      IconButton(onPressed: () => Navigator.pop(context), icon: Icon(Icons.close_rounded, color: _isDark ? Colors.white54 : Colors.black54)),
                    ],
                  ),
                  Text('Localizamos ${meusAgendamentos.length} agendamentos vinculados ao WhatsApp $telefone', style: TextStyle(color: _isDark ? Colors.white54 : Colors.black54, fontSize: 14)),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Expanded(
              child: meusAgendamentos.isEmpty 
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.event_note_rounded, size: 80, color: _isDark ? Colors.white.withAlpha(12) : Colors.black.withAlpha(12)),
                        const SizedBox(height: 16),
                        Text('Nenhum agendamento encontrado.', style: TextStyle(color: _isDark ? Colors.white30 : Colors.black26, fontSize: 16)),
                        const SizedBox(height: 8),
                        Text('Verifique se o número está correto.', style: TextStyle(color: _isDark ? Colors.white10 : Colors.black12, fontSize: 12)),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 40),
                    itemCount: meusAgendamentos.length,
                    itemBuilder: (context, index) {
                      return _buildAgendamentoCardPublico(meusAgendamentos[index], primaryColor);
                    },
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(String message) {
    return Center(
      child: Column(
        children: [
          Icon(Icons.search_off_rounded, color: _isDark ? Colors.white.withAlpha(25) : Colors.black.withAlpha(25), size: 64),
          const SizedBox(height: 16),
          Text(message, style: TextStyle(color: _isDark ? _LojaPublicaStyle.textSecondaryColor : Colors.grey[600])),
        ],
      ),
    );
  }

  Widget _buildLoadingOverlay(Color primaryColor) {
    return Container(
      color: Colors.black.withOpacity(0.7),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: primaryColor),
            const SizedBox(height: 24),
            Text(
              'Enviando sua solicitação...',
              style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFooter(Color textSecondary) {
    return Center(
      child: Column(
        children: [
          Divider(color: _isDark ? Colors.white10 : Colors.black12),
          const SizedBox(height: 24),
          Text(
            'Powered by Exodo Systems',
            style: TextStyle(color: textSecondary.withOpacity(0.5), fontSize: 12),
          ),
        ],
      ),
    );
  }

  void _showWarning(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.orange, behavior: SnackBarBehavior.floating),
    );
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.redAccent, behavior: SnackBarBehavior.floating),
    );
  }

  // Pickers logic
  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 60)),
      builder: (context, child) {
        return Theme(
          data: _isDark ? ThemeData.dark().copyWith(
            colorScheme: ColorScheme.dark(
              primary: _primaryColor,
              onPrimary: Colors.white,
              surface: _LojaPublicaStyle.cardColor,
              onSurface: Colors.white,
            ),
          ) : ThemeData.light().copyWith(
            colorScheme: ColorScheme.light(
              primary: _primaryColor,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black87,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _dataSelecionada = picked;
        _verificandoDisponibilidade = true;
      });
      // Simular um pequeno tempo de verificação para dar feedback visual
      Future.delayed(const Duration(milliseconds: 1500), () {
        if (mounted) setState(() => _verificandoDisponibilidade = false);
      });
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 9, minute: 0),
      builder: (context, child) {
        return Theme(
          data: _isDark ? ThemeData.dark().copyWith(
            colorScheme: ColorScheme.dark(
              primary: _primaryColor,
              onPrimary: Colors.white,
              surface: _LojaPublicaStyle.cardColor,
              onSurface: Colors.white,
            ),
          ) : ThemeData.light().copyWith(
            colorScheme: ColorScheme.light(
              primary: _primaryColor,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black87,
            ),
          ),
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
            child: child!,
          ),
        );
      },
    );
    if (picked != null) {
      setState(() {
        _horaSelecionada = picked;
        _verificandoDisponibilidade = true;
      });
      // Simular um pequeno tempo de verificação para dar feedback visual
      Future.delayed(const Duration(milliseconds: 1500), () {
        if (mounted) setState(() => _verificandoDisponibilidade = false);
      });
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'Concluído': return const Color(0xFF00C853);
      case 'Cancelado': return const Color(0xFFFF5252);
      case 'Aguardando Confirmação': return const Color(0xFFFFAB40);
      case 'Em Andamento': return const Color(0xFF448AFF);
      case 'Agendado': return const Color(0xFF64B5F6);
      default: return Colors.white54;
    }
  }

  Widget _buildServicosSelecionadosSummary(List<Servico> todosServicos, bool esconderValores) {
    final selecionados = todosServicos.where((s) => _servicosSelecionadosIds.contains(s.id)).toList();
    final precoTotal = selecionados.fold<double>(0.0, (double sum, Servico s) => sum + s.precoTotal);
    final int duracaoTotal = selecionados.fold<int>(0, (int sum, Servico s) => sum + (s.duracaoPadraoMinutos ?? 60));

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _primaryColor.withAlpha(25),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _primaryColor.withAlpha(76)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.shopping_basket_rounded, color: _primaryColor),
              const SizedBox(width: 12),
              const Text(
                'Serviços Selecionados',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...selecionados.map((Servico s) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(child: Text(s.nome, style: const TextStyle(color: Colors.white70))),
                if (!esconderValores)
                  Text('R\$ ${s.precoTotal.toStringAsFixed(2)}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ],
            ),
          )),
          const Divider(color: Colors.white24, height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Duração Estimada', style: TextStyle(color: Colors.white38, fontSize: 12)),
                  Text('$duracaoTotal minutos', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ],
              ),
              if (!esconderValores)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text('Valor Total', style: TextStyle(color: Colors.white38, fontSize: 12)),
                    Text('R\$ ${precoTotal.toStringAsFixed(2)}', style: TextStyle(color: _primaryColor, fontWeight: FontWeight.bold, fontSize: 20)),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}
