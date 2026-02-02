import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sistema_exodo_novo/models/agendamento_servico.dart';
import 'package:sistema_exodo_novo/models/cliente.dart';
import 'package:sistema_exodo_novo/models/pet.dart';
import 'package:sistema_exodo_novo/services/data_service.dart';
import 'package:sistema_exodo_novo/services/auth_service.dart';
import 'package:intl/intl.dart';
import 'dart:ui';
import 'package:google_fonts/google_fonts.dart';

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

  
  String? _servicoIdSelecionado;
  String _porteAnimal = 'Pequeno'; // Pequeno, Médio, Grande, Gigante
  double _pesoAproximado = 5.0;
  DateTime? _dataSelecionada;
  TimeOfDay? _horaSelecionada;
  String _tipoEntrega = 'Retirada na Loja'; // 'Retirada na Loja', 'Taxi Dog'
  String? _bairroEntrega;
  String _petSexo = 'M'; // M ou F
  String _petEspecie = 'Cachorro';


  bool _enviando = false;
  bool _verificandoDisponibilidade = false;
  List<AgendamentoServico> _agendamentosCarrinho = [];

  final List<String> _portes = ['Pequeno', 'Médio', 'Grande', 'Gigante'];

  // Busca de cliente/pet automático
  List<Pet> _petsEncontrados = [];
  Cliente? _clienteEncontrado;
  bool _buscandoCliente = false;
  String? _ultimoTelefoneBuscado; // Para evitar loops de busca

  @override
  void initState() {
    super.initState();
    _whatsappController.addListener(_onWhatsappChanged);
  }

  void _onWhatsappChanged() {
    final tel = _whatsappController.text.replaceAll(RegExp(r'\D'), '');
    // Buscar se tiver pelo menos 8 dígitos (permitir busca parcial proativa)
    if (tel.length >= 8) {
      _buscarClientePorTelefone(tel);
    }
  }

  Future<void> _buscarClientePorTelefone(String telefone) async {
    if (_buscandoCliente || telefone.length < 8) {
      if (telefone.length < 8 && _clienteEncontrado != null) {
        setState(() {
          _clienteEncontrado = null;
          _petsEncontrados = [];
        });
      }
      return;
    }

    final dataService = Provider.of<DataService>(context, listen: false);
    
    // Evitar buscar se já for o mesmo cliente que acabamos de carregar
    final normalizado = telefone.replaceAll(RegExp(r'\D'), '');
    if (_clienteEncontrado != null) {
      final t = _clienteEncontrado!.telefone.replaceAll(RegExp(r'\D'), '');
      final w = (_clienteEncontrado!.whatsapp ?? '').replaceAll(RegExp(r'\D'), '');
      if (t == normalizado || w == normalizado) return;
    }

    debugPrint('>>> [Agendamento] 🔍 Buscando fone: $normalizado em ${dataService.clientes.length} clientes');

    setState(() {
      _buscandoCliente = true;
      _ultimoTelefoneBuscado = normalizado;
    });

    try {
      // 1. Chamar o DataService que agora sabe buscar no Firebase se necessário
      final candidatos = await dataService.buscarClientePorTelefone(normalizado);

      if (candidatos.isNotEmpty) {
        // Priorizar o candidato que tem pets cadastrados
        final sortedCandidatos = List<Cliente>.from(candidatos);
        sortedCandidatos.sort((a, b) {
          // 1. Quem tem pets ganha
          if (a.pets.isNotEmpty && b.pets.isEmpty) return -1;
          if (a.pets.isEmpty && b.pets.isNotEmpty) return 1;
          
          // 2. Quem tem mais pets ganha
          if (a.pets.length != b.pets.length) return b.pets.length.compareTo(a.pets.length);
          
          // 3. Quem tem endereço ganha
          bool aHasEnd = (a.endereco?.isNotEmpty ?? false);
          bool bHasEnd = (b.endereco?.isNotEmpty ?? false);
          if (aHasEnd && !bHasEnd) return -1;
          if (!aHasEnd && bHasEnd) return 1;
          
          // 4. Mais recente ganha
          return b.updatedAt.compareTo(a.updatedAt);
        });

        final encontrado = sortedCandidatos.first;
        
        setState(() {
          _clienteEncontrado = encontrado;
          _petsEncontrados = encontrado.pets;
          // Preenche o nome se estiver vazio
          if (_nomeController.text.isEmpty) {
            _nomeController.text = encontrado.nome;
          }
          
          // Preenche o endereço se estiver vazio
          if (_bairroEntrega == null) {
            _bairroEntrega = encontrado.bairro;
            _enderecoRuaController.text = encontrado.endereco ?? '';
            _enderecoNumeroController.text = encontrado.numero ?? '';
            _enderecoComplementoController.text = encontrado.complemento ?? '';
            _pontoReferenciaController.text = encontrado.pontoReferencia ?? '';
          }
          
          // Se houver apenas um pet, já pré-seleciona ele
          if (_petsEncontrados.length == 1) {
            final pet = _petsEncontrados.first;
            _petNomeController.text = pet.nome;
            _petRacaController.text = pet.raca ?? '';
            _petCorController.text = pet.cor ?? '';
            _petObsController.text = pet.observacoes ?? '';
            _petEspecie = pet.especie ?? 'Cachorro';
            _petSexo = pet.sexo ?? 'M';
            _porteAnimal = pet.tamanho ?? 'Pequeno';
            _pesoAproximado = pet.peso ?? 5.0;
          }
        });
        debugPrint('>>> [Agendamento] ✅ Encontrado: ${encontrado.nome} com ${encontrado.pets.length} pets');
      } else {
        debugPrint('>>> [Agendamento] ❌ Ninguém encontrado para $normalizado');
        if (_clienteEncontrado != null) {
          setState(() {
            _clienteEncontrado = null;
            _petsEncontrados = [];
          });
        }
      }
    } catch (e) {
      debugPrint('>>> [Agendamento] ❌ Erro na busca: $e');
    } finally {
      if (mounted) setState(() => _buscandoCliente = false);
    }
  }
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
    // --------------------------------------------

    return Scaffold(
      backgroundColor: _isDark ? _LojaPublicaStyle.backgroundColor : Colors.grey[100],
      appBar: AppBar(
        title: Text(empresa?.nomeExibicao ?? 'Agendamento'),
        backgroundColor: primary,
        elevation: 0,
        actions: [
          TextButton.icon(
            onPressed: () => _mostrarConsultaAgendamentos(primary),
            icon: const Icon(Icons.search, color: Colors.white, size: 20),
            label: const Text('Meus Agendamentos', style: TextStyle(color: Colors.white, fontSize: 12)),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            _buildStepper(primary, moduloPet),
            const SizedBox(height: 32),
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: _isDark ? _LojaPublicaStyle.cardColor : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.withOpacity(0.2)),
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    if (_agendamentosCarrinho.isNotEmpty) _buildResumoCarrinho(primary),
                    _buildCurrentStepView(moduloPet),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 32),
            _buildNavigationButtons(primary, moduloPet),
          ],
        ),
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

  Widget _buildStepper(Color primaryColor, bool moduloPet) {
    final List<String> stepLabels = [
      'Serviço', 
      'Seus Dados', 
      if (moduloPet) 'O Pet', 
      if (moduloPet) 'Entrega',
      'Horário'
    ];
    final List<IconData> stepIcons = [
      Icons.style_rounded,
      Icons.person_rounded,
      if (moduloPet) Icons.pets_rounded,
      if (moduloPet) Icons.local_shipping_rounded,
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
                            : (_isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.05)),
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
                        color: isActive ? (_isDark ? Colors.white : primaryColor) : (_isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.1)),
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
                            : (_isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.05)),
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

  Widget _buildCurrentStepView(bool moduloPet) {
    // Mapear o índice atual para o passo real
    int passoReal = _currentStep;
    if (!moduloPet) {
       if (_currentStep >= 2) {
          passoReal = _currentStep + 2; // Pula Pet e Entrega
       }
    }

    switch (passoReal) {
      case 0:
        return _buildStepServicos(moduloPet);
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
        final agendamentoConfig = config['agendamento'] as Map<String, dynamic>? ?? {};
        
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
      case 4:
        return _buildStepHorario();
      default:
        return const SizedBox();
    }
  }

  Widget _buildStepServicos(bool moduloPet) {
    final dataService = Provider.of<DataService>(context);
    final servicos = dataService.servicos;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStepTitle(
          'O que vamos fazer hoje?', 
          moduloPet ? 'Selecione o serviço desejado para o seu pet.' : 'Selecione o serviço desejado.',
        ),
        const SizedBox(height: 24),
        if (servicos.isEmpty)
          _buildEmptyState('Nenhum serviço disponível no momento.')
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: servicos.length,
            separatorBuilder: (context, index) => const SizedBox(height: 16),
            itemBuilder: (context, index) {
              final servico = servicos[index];
              bool isSelected = _servicoIdSelecionado == servico.id;

              return InkWell(
                onTap: () => setState(() => _servicoIdSelecionado = servico.id),
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: isSelected ? _primaryColor.withOpacity(0.15) : (_isDark ? Colors.white.withOpacity(0.03) : Colors.grey[50]),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isSelected ? _primaryColor : (_isDark ? Colors.white.withOpacity(0.1) : Colors.grey[200]!),
                      width: 2,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isSelected ? _primaryColor : Colors.white.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          _getIconForServico(servico.nome),
                          color: isSelected ? Colors.white : (_isDark ? _LojaPublicaStyle.textSecondaryColor : Colors.grey[500]),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Nome do Serviço (com + se houver adicional para facilitar entendimento de combo)
                            RichText(
                              text: TextSpan(
                                style: TextStyle(color: _isDark ? Colors.white : Colors.black87, fontWeight: FontWeight.bold, fontSize: 18),
                                children: [
                                  TextSpan(text: servico.nome),
                                  if (servico.descricaoAdicional?.isNotEmpty ?? false) ...[
                                    const TextSpan(text: ' + ', style: TextStyle(color: Colors.purpleAccent, fontSize: 20)),
                                    TextSpan(text: servico.descricaoAdicional!, style: const TextStyle(color: Colors.purpleAccent)),
                                  ],
                                ],
                              ),
                            ),
                            if (servico.descricao?.isNotEmpty ?? false) ...[
                              const SizedBox(height: 4),
                              Text(
                                servico.descricao!,
                                style: TextStyle(color: _isDark ? _LojaPublicaStyle.textSecondaryColor : Colors.grey[600], fontSize: 13),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (servico.valorAdicional > 0)
                             Text(
                              '${servico.nome}: R\$ ${servico.preco.toStringAsFixed(2)} + ${servico.descricaoAdicional ?? "Adicional"}: R\$ ${servico.valorAdicional.toStringAsFixed(2)}',
                              style: TextStyle(color: Colors.greenAccent.withOpacity(0.8), fontSize: 9, fontWeight: FontWeight.w500),
                            ),
                          Text(
                            'R\$ ${servico.precoTotal.toStringAsFixed(2)}',
                            style: GoogleFonts.outfit(
                              color: isSelected ? Colors.white : _primaryColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                          if (servico.duracaoPadraoMinutos != null)
                            Text(
                              '${servico.duracaoPadraoMinutos} min',
                              style: TextStyle(color: _isDark ? _LojaPublicaStyle.textSecondaryColor : Colors.grey[500], fontSize: 11),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
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
          Text(
            'Pets já cadastrados em seu telefone:',
            style: TextStyle(
              color: _primaryColor, 
              fontWeight: FontWeight.bold, 
              fontSize: 15,
              letterSpacing: 0.5
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 90,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _petsEncontrados.length + 1,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                if (index == _petsEncontrados.length) {
                  // Card para "Novo Pet"
                  bool isSelected = _petNomeController.text.isEmpty;
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
                      });
                    },
                  );
                }

                final pet = _petsEncontrados[index];
                bool isSelected = _petNomeController.text == pet.nome;

                return _buildPetSelectionCard(
                  title: pet.nome,
                  subtitle: pet.raca ?? 'Sem raça',
                  icon: (pet.especie?.toLowerCase() ?? '') == 'gato' ? Icons.pets : Icons.pets_rounded,
                  isSelected: isSelected,
                  onTap: () {
                    setState(() {
                      _petNomeController.text = pet.nome;
                      _petRacaController.text = pet.raca ?? '';
                      _petCorController.text = pet.cor ?? '';
                      _petObsController.text = pet.observacoes ?? '';
                      _petEspecie = pet.especie ?? 'Cachorro';
                      _petSexo = pet.sexo ?? 'M';
                      _porteAnimal = pet.tamanho ?? 'Pequeno';
                      _pesoAproximado = pet.peso ?? 5.0;
                    });
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 24),
          const Divider(color: Colors.white10),
          const SizedBox(height: 24),
        ] else if (_clienteEncontrado != null && !_buscandoCliente) ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.05),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _primaryColor.withOpacity(0.2)),
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
        
        _buildTextField(
          controller: _petNomeController,
          label: 'Nome do Pet *',
          icon: Icons.pets_rounded,
          placeholder: 'Nome do seu amigo',
          validator: (v) => v!.isEmpty ? 'Obrigatório' : null,
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
                onChanged: (v) => setState(() => _petEspecie = v!),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildTextField(
                controller: _petRacaController,
                label: 'Raça *',
                icon: Icons.search_rounded,
                placeholder: 'Ex: Shih-tzu',
                validator: (v) => v!.isEmpty ? 'Obrigatório' : null,
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
                onChanged: (v) => setState(() => _petSexo = v!),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildTextField(
                controller: _petCorController,
                label: 'Cor',
                icon: Icons.palette_rounded,
                placeholder: 'Ex: Branco, Preto',
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
              onTap: () => setState(() => _porteAnimal = porte),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: isSelected ? _primaryColor : (_isDark ? Colors.white.withOpacity(0.05) : Colors.grey[100]),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected ? Colors.white.withOpacity(0.2) : (_isDark ? Colors.white.withOpacity(0.1) : Colors.grey[300]!),
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
          inactiveColor: _isDark ? Colors.white.withOpacity(0.1) : Colors.grey[200],
          onChanged: (val) => setState(() => _pesoAproximado = val),
        ),
        
        const SizedBox(height: 20),
        
        _buildTextField(
          controller: _petObsController,
          label: 'Observações do Animal',
          icon: Icons.notes_rounded,
          placeholder: 'Ex: Ele é bravo, tem alergia a algum produto...',
          maxLines: 3,
        ),
      ],
    );
  }


  Widget _buildPetSelectionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 140,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? _primaryColor.withOpacity(0.15) : (_isDark ? Colors.white.withOpacity(0.05) : Colors.grey[100]),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? _primaryColor : (_isDark ? Colors.white.withOpacity(0.1) : Colors.grey[300]!),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: isSelected ? _primaryColor : Colors.grey[400], size: 24),
            const SizedBox(height: 8),
            Text(
              title,
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
    );
  }

  Widget _buildStepEntregaV2(List<Map<String, dynamic>> bairrosConfig) {
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
              fillColor: _isDark ? Colors.white.withOpacity(0.05) : Colors.grey[100],
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
              fillColor: _isDark ? Colors.white.withOpacity(0.05) : Colors.grey[100],
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
              prefixIcon: Icon(Icons.location_on_rounded, color: _primaryColor),
            ),
            items: bairros.map((b) => DropdownMenuItem(value: b, child: Text(b))).toList(),
            onChanged: (val) => setState(() => _bairroEntrega = val),
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
          color: isSelected ? _primaryColor.withOpacity(0.15) : (_isDark ? Colors.white.withOpacity(0.05) : Colors.grey[100]),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? _primaryColor : (_isDark ? Colors.white.withOpacity(0.1) : Colors.grey[300]!),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: isSelected ? _primaryColor : (_isDark ? Colors.white.withOpacity(0.05) : Colors.grey[200]), shape: BoxShape.circle),
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

  Widget _buildStepHorario() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStepTitle('Quando podemos receber vocês?', 'Escolha a data e o melhor horário disponível.'),
        const SizedBox(height: 32),
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
                label: 'Horário',
                value: _horaSelecionada == null 
                    ? 'Selecionar' 
                    : '${_horaSelecionada!.hour.toString().padLeft(2, '0')}:${_horaSelecionada!.minute.toString().padLeft(2, '0')}',
                icon: Icons.access_time_rounded,
                onTap: _pickTime,
              ),
            ),
          ],
        ),
        const SizedBox(height: 32),
        if (_dataSelecionada != null && _horaSelecionada != null)
          _buildDisponibilidadeCheck(),
      ],
    );
  }

  Widget _buildDisponibilidadeCheck() {
    if (_verificandoDisponibilidade) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: _isDark ? Colors.white.withOpacity(0.05) : Colors.grey[200],
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
    
    final duracao = dataService.servicos.firstWhere((s) => s.id == _servicoIdSelecionado, orElse: () => dataService.servicos.first).duracaoPadraoMinutos ?? 60;
    bool disponivel = dataService.checkDisponibilidade(inicio, duracao, ignorarPendentes: false);


    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: disponivel ? Colors.green.withOpacity(0.1) : _primaryColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: disponivel ? Colors.green.withOpacity(0.3) : _primaryColor.withOpacity(0.3),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: disponivel ? Colors.green : _primaryColor,
              shape: BoxShape.circle,
            ),
            child: Icon(
              disponivel ? Icons.check : Icons.notification_important_rounded,
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
                  disponivel ? 'Ótima escolha!' : 'Solicitação de Agendamento',
                  style: TextStyle(
                    color: disponivel ? Colors.green[300] : Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  disponivel 
                    ? 'Esse horário está livre em nossa agenda.' 
                    : 'Faremos o possível para te atender! Prosiga com o agendamento e aguarde nossa confirmação.',
                  style: TextStyle(
                    color: disponivel ? Colors.green[100]?.withOpacity(0.7) : Colors.white.withOpacity(0.7),
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
            hintStyle: TextStyle(color: _isDark ? Colors.white.withOpacity(0.2) : Colors.grey[400]),
            prefixIcon: Icon(icon, color: _primaryColor, size: 20),
            suffixIcon: suffixIcon,
            filled: true,
            fillColor: _isDark ? Colors.white.withOpacity(0.05) : Colors.grey[100],
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: _isDark ? Colors.white.withOpacity(0.1) : Colors.grey[300]!),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: _isDark ? Colors.white.withOpacity(0.1) : Colors.grey[300]!),
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
            color: _isDark ? Colors.white.withOpacity(0.05) : Colors.grey[100],
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _isDark ? Colors.white.withOpacity(0.1) : Colors.grey[300]!),
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
    required VoidCallback onTap,
  }) {
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
              color: _isDark ? Colors.white.withOpacity(0.05) : Colors.grey[100],
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _isDark ? Colors.white.withOpacity(0.1) : Colors.grey[300]!),
            ),
            child: Row(
              children: [
                Icon(icon, color: _primaryColor, size: 20),
                const SizedBox(width: 12),
                Text(
                  value,
                  style: TextStyle(
                    color: value == 'Selecionar' ? (_isDark ? Colors.white24 : Colors.grey[400]) : (_isDark ? Colors.white : Colors.black87),
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
    final int maxIndex = moduloPet ? 4 : 2;
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
                label: const Text('Agendar outro Pet', style: TextStyle(fontWeight: FontWeight.bold)),
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
                                ? (_agendamentosCarrinho.isEmpty ? 'Finalizar Agendamento' : 'Finalizar TUDO (${_agendamentosCarrinho.length + 1})') 
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
    if (_currentStep == 0 && _servicoIdSelecionado == null) {
      _showWarning('Por favor, escolha um serviço primeiro.');
      return;
    }

    final int maxIndex = moduloPet ? 4 : 2;

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

    setState(() => _enviando = true);

    final dataService = Provider.of<DataService>(context, listen: false);
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

      final servicoAtual = dataService.servicos.firstWhere((s) => s.id == _servicoIdSelecionado);
      
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
          id: 'pub_${DateTime.now().millisecondsSinceEpoch}',
          nome: _nomeController.text,
          telefone: _whatsappController.text,
          whatsapp: telefoneBusca,
          pets: [],
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        await dataService.addCliente(clienteReal);
        if (mounted) setState(() => _clienteEncontrado = clienteReal);
      } else {
        // Se existe mas o nome no formulário é diferente, atualizar
        if (_nomeController.text.isNotEmpty && clienteReal.nome != _nomeController.text) {
          clienteReal = clienteReal.copyWith(nome: _nomeController.text, updatedAt: DateTime.now());
          await dataService.updateCliente(clienteReal);
        }
      }

      // Tentar encontrar pet para o agendamento ATUAL
      if (moduloPet && _petNomeController.text.isNotEmpty) {
        try {
          petExistente = clienteReal.pets.firstWhere(
            (p) => p.nome.toLowerCase().trim() == _petNomeController.text.toLowerCase().trim()
          );
        } catch (_) {}
      }

      final petInfoAtual = moduloPet ? Pet(
        id: petExistente?.id ?? 'novo_${DateTime.now().millisecondsSinceEpoch}',
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

      final agendamentoAtual = AgendamentoServico(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        numero: '',
        servicoId: servicoAtual.id,
        servico: servicoAtual,
        clienteId: clienteReal.id,
        cliente: clienteReal,
        petId: petInfoAtual?.id,
        pet: petInfoAtual,
        clienteNome: _nomeController.text,
        clienteTelefone: _whatsappController.text,
        petNome: moduloPet ? _petNomeController.text : null,
        dataAgendamento: dataAgendamentoAtual,
        duracaoMinutos: servicoAtual.duracaoPadraoMinutos ?? 60,
        status: 'Aguardando Confirmação',
        tipoEntrega: moduloPet ? _tipoEntrega : null,
        bairroEntrega: moduloPet && _tipoEntrega != 'Retirada na Loja' ? _bairroEntrega : null,
        valorTaxiDog: moduloPet && _tipoEntrega != 'Retirada na Loja' ? _valorTaxiDog : null,
        endereco: moduloPet && _tipoEntrega != 'Retirada na Loja' ? _enderecoRuaController.text : null,
        numeroEndereco: moduloPet && _tipoEntrega != 'Retirada na Loja' ? _enderecoNumeroController.text : null,
        complemento: moduloPet && _tipoEntrega != 'Retirada na Loja' ? _enderecoComplementoController.text : null,
        pontoReferencia: moduloPet && _tipoEntrega != 'Retirada na Loja' ? _pontoReferenciaController.text : null,
        observacoes: 'SOLICITAÇÃO ONLINE DETALHADA',
      );

      // 2. Unir com agendamentos já salvos no carrinho local
      final todos = [..._agendamentosCarrinho, agendamentoAtual];
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
              id: 'per_${DateTime.now().millisecondsSinceEpoch}_${agdFinal.id}',
              nome: agdFinal.petNome!,
              updatedAt: DateTime.now(),
              createdAt: DateTime.now(),
            );
            final novosPets = [...clienteReal.pets, novoPet];
            clienteReal = clienteReal.copyWith(pets: novosPets, updatedAt: DateTime.now());
            await dataService.updateCliente(clienteReal);
            petNoCliente = novoPet;
          }

          agdFinal = agdFinal.copyWith(
            petId: petNoCliente.id,
            pet: petNoCliente,
          );
        }

        final disponivel = dataService.checkDisponibilidade(
          agdFinal.dataAgendamento, 
          agdFinal.servico?.duracaoPadraoMinutos ?? 60, 
          ignorarPendentes: false
        );
        if (!disponivel) algumOcupado = true;
        
        await dataService.addAgendamentoServico(agdFinal);
      }

      if (mounted) {
        _mostrarSucesso(horarioOcupado: algumOcupado);
      }

    } catch (e) {
      debugPrint('Erro ao finalizar: $e');
      _showError('Erro ao processar sua solicitação. Tente novamente.');
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }


  Widget _buildResumoCarrinho(Color primaryColor) {
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: primaryColor.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: primaryColor.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.shopping_basket_rounded, color: primaryColor, size: 20),
              const SizedBox(width: 10),
              Text(
                'Seus Agendamentos (${_agendamentosCarrinho.length})',
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
                  backgroundColor: primaryColor.withOpacity(0.1),
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
    final dataAgendamento = DateTime(
      _dataSelecionada!.year,
      _dataSelecionada!.month,
      _dataSelecionada!.day,
      _horaSelecionada!.hour,
      _horaSelecionada!.minute,
    );

    final servico = dataService.servicos.firstWhere((s) => s.id == _servicoIdSelecionado);
    
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

    final petInfo = moduloPet ? Pet(
      id: petExistente?.id ?? 'novo_${DateTime.now().millisecondsSinceEpoch}',
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

    final agendamento = AgendamentoServico(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
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
      status: 'Aguardando Confirmação',
      tipoEntrega: moduloPet ? _tipoEntrega : null,
      bairroEntrega: moduloPet && _tipoEntrega != 'Retirada na Loja' ? _bairroEntrega : null,
      valorTaxiDog: moduloPet && _tipoEntrega != 'Retirada na Loja' ? _valorTaxiDog : null,
      endereco: moduloPet && _tipoEntrega != 'Retirada na Loja' ? _enderecoRuaController.text : null,
      numeroEndereco: moduloPet && _tipoEntrega != 'Retirada na Loja' ? _enderecoNumeroController.text : null,
      complemento: moduloPet && _tipoEntrega != 'Retirada na Loja' ? _enderecoComplementoController.text : null,
      pontoReferencia: moduloPet && _tipoEntrega != 'Retirada na Loja' ? _pontoReferenciaController.text : null,
      observacoes: 'SOLICITAÇÃO ONLINE ADICIONAL',
    );

    setState(() {
      _agendamentosCarrinho.add(agendamento);
      // Resetar apenas campos do PET e SERVIÇO e HORÁRIO e ENDEREÇO
      _servicoIdSelecionado = null;
      _petNomeController.clear();
      _petRacaController.clear();
      _petCorController.clear();
      _petObsController.clear();
      _enderecoRuaController.clear();
      _enderecoNumeroController.clear();
      _enderecoComplementoController.clear();
      _pontoReferenciaController.clear();
      _dataSelecionada = null;
      _horaSelecionada = null;
      _currentStep = 0; // Volta para o início para o próximo pet
    });

    _showWarning('Agendamento adicionado! Você pode agendar outro pet agora.');
  }

  void _mostrarSucesso({bool horarioOcupado = false}) {
    final cardColor = _isDark ? _LojaPublicaStyle.cardColor : Colors.white;
    final textColor = _isDark ? Colors.white : const Color(0xFF1E293B);
    final textSecondary = _isDark ? _LojaPublicaStyle.textSecondaryColor : Colors.black54;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
        child: AlertDialog(
          backgroundColor: cardColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
          content: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: (horarioOcupado ? Colors.orange : Colors.green).withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    horarioOcupado ? Icons.warning_amber_rounded : Icons.check_circle_rounded, 
                    color: horarioOcupado ? Colors.orange : Colors.green, 
                    size: 80
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  horarioOcupado ? 'Solicitações Enviadas' : 'Tudo pronto!',
                  style: GoogleFonts.outfit(color: textColor, fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                Text(
                  'Recebemos suas solicitações de agendamento.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: textSecondary),
                ),
                const SizedBox(height: 16),
                ..._agendamentosCarrinho.map((a) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '• ${a.petNome ?? 'Serviço'} - ${DateFormat('dd/MM HH:mm').format(a.dataAgendamento)}',
                    style: TextStyle(color: textColor.withOpacity(0.7), fontSize: 13),
                  ),
                )).toList(),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      setState(() {
                        _currentStep = 0;
                        _agendamentosCarrinho.clear();
                        _servicoIdSelecionado = null;
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
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _primaryColor,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: const Text('Entendido', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(String message) {
    return Center(
      child: Column(
        children: [
          Icon(Icons.search_off_rounded, color: _isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.1), size: 64),
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
    final meusAgendamentos = dataService.agendamentosServico.where((a) {
      final String rawInput = telefone.replaceAll(RegExp(r'[^\d]'), '');
      if (rawInput.length < 8) return false;

      // Pegar os últimos 8 dígitos para uma busca mais flexível (ignora DDD/0/55)
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
      if (comparar(a.clienteNome)) return true;

      return false;
    }).toList();

    // Ordenar por data (mais recente primeiro)
    meusAgendamentos.sort((a, b) => b.dataAgendamento.compareTo(a.dataAgendamento));

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.8,
        decoration: BoxDecoration(
          color: _isDark ? _LojaPublicaStyle.backgroundColor : Colors.grey[100],
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 24),
            Text('Seu Histórico', style: GoogleFonts.outfit(color: _isDark ? Colors.white : Colors.black87, fontSize: 24, fontWeight: FontWeight.bold)),
            Text('Agendamentos vinculados ao WhatsApp $telefone', style: const TextStyle(color: Colors.white54, fontSize: 14)),
            const SizedBox(height: 24),
            Expanded(
              child: meusAgendamentos.isEmpty 
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.event_busy_rounded, size: 64, color: Colors.white10),
                        const SizedBox(height: 16),
                        const Text('Nenhum agendamento encontrado.', style: TextStyle(color: Colors.white30)),
                      ],
                    ),
                  )
                : ListView.separated(
                    itemCount: meusAgendamentos.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final agd = meusAgendamentos[index];
                      return Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: _isDark ? _LojaPublicaStyle.cardColor : Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white.withOpacity(0.05)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(color: primaryColor.withOpacity(0.1), shape: BoxShape.circle),
                              child: Icon(Icons.calendar_today_rounded, color: primaryColor, size: 20),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(agd.servico?.nome ?? 'Serviço', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                  Text(DateFormat('dd/MM/yyyy HH:mm').format(agd.dataAgendamento), style: const TextStyle(color: Colors.white54, fontSize: 13)),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: _getStatusColor(agd.status).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(agd.status, style: TextStyle(color: _getStatusColor(agd.status), fontSize: 11, fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'Concluído': return Colors.greenAccent;
      case 'Cancelado': return Colors.redAccent;
      case 'Aguardando Confirmação': return Colors.orangeAccent;
      case 'Em Andamento': return Colors.blueAccent;
      default: return Colors.white54;
    }
  }
}
