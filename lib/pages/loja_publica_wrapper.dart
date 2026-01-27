import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:sistema_exodo_novo/services/data_service.dart';
import 'package:sistema_exodo_novo/services/auth_service.dart';
import 'package:sistema_exodo_novo/services/carrinho_service.dart';

import 'package:sistema_exodo_novo/pages/loja_publica_page.dart';
import 'package:sistema_exodo_novo/pages/agendamento_publico_page.dart';
import 'package:sistema_exodo_novo/widgets/exodo_loading.dart';
import '../theme.dart';
// Import condicional para Web
import 'html_helper_stub.dart' if (dart.library.html) 'html_helper_web.dart' as html_helper;

/// Wrapper para a loja pública que carrega dados sem autenticação
/// Tenta carregar dados de todas as empresas ou de uma empresa padrão
/// 
/// [codigoLink]: Código do link do vendedor (ex: ABC123). 
///               Se vazio, mostra loja pública fixa (sem vendedor específico)
class LojaPublicaWrapper extends StatefulWidget {
  final String codigoLink;
  final String? slugEmpresa;
  final bool forceAgendamento;

  const LojaPublicaWrapper({
    super.key, 
    required this.codigoLink,
    this.slugEmpresa,
    this.forceAgendamento = false,
  });

  @override
  State<LojaPublicaWrapper> createState() => _LojaPublicaWrapperState();
}

class _LojaPublicaWrapperState extends State<LojaPublicaWrapper> {
  bool _dadosCarregados = false;
  String? _empresaIdConfigurada;
  String? _ultimoSlugProcessado;

  @override
  void initState() {
    super.initState();
    print('>>> [LojaPublicaWrapper] @INIT - Slug: ${widget.slugEmpresa}');
    _carregarDados();
  }

  @override
  void didUpdateWidget(LojaPublicaWrapper oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.slugEmpresa != widget.slugEmpresa) {
      print('>>> [LojaPublicaWrapper] @UPDATE - Slug mudou: ${oldWidget.slugEmpresa} -> ${widget.slugEmpresa}');
      _carregarDados();
    }
  }

  // Monitorar mudanças no AuthService para reagir quando as empresas carregarem
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Se ainda não carregamos os dados OU se carregamos o padrão mas as empresas acabaram de chegar, tentar de novo
    final authService = Provider.of<AuthService>(context);
    // Retentar se ainda não carregamos com sucesso ou se estamos no fallback '1' mas mais empresas chegaram
    if (!_dadosCarregados || (_empresaIdConfigurada == null)) {
      if (authService.empresas.isNotEmpty) {
        debugPrint('>>> [LojaPublicaWrapper] @CHANGES - Empresas chegaram, tentando carregar...');
        _carregarDados();
      }
    }
  }

  Future<void> _carregarDados() async {
    final dataService = Provider.of<DataService>(context, listen: false);
    final authService = Provider.of<AuthService>(context, listen: false);
    
    final currentSlug = widget.slugEmpresa;
    _ultimoSlugProcessado = currentSlug;

    try {
      // 1. Aguardar carregamento inicial das empresas
      // Se temos um slug, vale a pena esperar um pouco mais
      int tentativas = 0;
      int maxTentativas = (currentSlug != null && currentSlug.isNotEmpty) ? 20 : 10; // Esperar até 10s se tiver slug
      
      // Se temos um slug, vale a pena esperar as empresas chegarem
      while (tentativas < maxTentativas) {
        // Se já temos empresas, tentar encontrar a solicitada
        if (authService.empresas.isNotEmpty) {
           final slugDeteccaoLocal = widget.slugEmpresa;
           if (slugDeteccaoLocal != null && slugDeteccaoLocal.isNotEmpty) {
              final detectada = authService.obterEmpresaPorSlug(slugDeteccaoLocal);
              if (detectada != null) break; // Encontramos!
           } else if (slugDeteccaoLocal == null || slugDeteccaoLocal.isEmpty) {
              break; // Sem slug, qualquer empresa (ou nenhuma) serve
           }
        }
        
        // Se ainda está carregando inicial ou a lista está vazia, esperamos
        if (authService.isCarregandoDados || authService.empresas.isEmpty) {
          await Future.delayed(const Duration(milliseconds: 500));
          tentativas++;
        } else {
          // Se não está carregando e já temos empresas (e não achamos o slug no break acima),
          // vamos dar uma última chance (mais 1s) caso o sync do Firebase ainda esteja rolando
          await Future.delayed(const Duration(seconds: 1));
          break;
        }
      }
      
      String? empresaIdParaUsar;
      String? slugDeteccao = currentSlug;
      
      // Detecção redundante da URL se o widget não recebeu o slug
      if (slugDeteccao == null || slugDeteccao.isEmpty) {
        if (kIsWeb) {
          final String path = html_helper.getWindowPathname();
          final segments = path.split('/').where((s) => s.isNotEmpty).toList();
          if (segments.isNotEmpty) {
            int idx = segments.indexOf('agendamento');
            if (idx != -1 && idx + 1 < segments.length) {
              slugDeteccao = segments[idx + 1];
            } else if (segments.indexOf('loja') == -1 && segments.indexOf('shop') == -1) {
              final first = segments[0];
              const reservados = {
                'login', 'home', 'dashboard', 'admin', 'auth', 'selecionar-empresa', 'debug',
                'clientes', 'produtos', 'servicos', 'pedidos', 'venda-direta', 'pdv',
                'entrada-mercadorias', 'contas-pagar', 'agenda-contas', 'cozinha-bar',
                'mesas', 'links-vendedores', 'vendedor-dashboard', 'funcionarios',
                'personalizar-loja', 'agenda-pet', 'gerenciar-imagens'
              };
              if (!reservados.contains(first)) {
                slugDeteccao = first;
              }
            }
          }
        }
      }

      print('>>> [LojaPublica] Buscando empresa para slug: "$slugDeteccao"');

      // 2. Localizar Empresa
      if (slugDeteccao != null && slugDeteccao.isNotEmpty) {
        final empresaPorSlug = authService.obterEmpresaPorSlug(slugDeteccao);
        if (empresaPorSlug != null) {
          empresaIdParaUsar = empresaPorSlug.id;
          dataService.setEmpresaAtual(empresaPorSlug); // SETAR OBJETO COMPLETO
          print('>>> [LojaPublica] ✅ Empresa encontrada por slug: ${empresaPorSlug.nomeExibicao} (ID: $empresaIdParaUsar)');
        } else {
          print('>>> [LojaPublica] ⚠ Slug "$slugDeteccao" não encontrado em ${authService.empresas.length} empresas');
        }
      }

      // 3. Fallback se não encontrar pelo slug
      if (empresaIdParaUsar == null) {
        if (authService.empresas.isNotEmpty) {
          // Se tiver um slug mas não achamos, vamos tentar achar por ID direto
          if (slugDeteccao != null) {
             final porId = authService.empresas.any((e) => e.id == slugDeteccao);
             if (porId) {
                empresaIdParaUsar = slugDeteccao;
                final empObj = authService.empresas.firstWhere((e) => e.id == slugDeteccao);
                dataService.setEmpresaAtual(empObj);
                print('>>> [LojaPublica] ✅ Empresa encontrada por ID direto: ${empObj.nomeExibicao} ($empresaIdParaUsar)');
              }
          }
          
          if (empresaIdParaUsar == null) {
            // Se ainda assim não achamos e o usuário não especificou slug, usar a primeira
            if (slugDeteccao == null || slugDeteccao.isEmpty) {
              empresaIdParaUsar = authService.empresas.first.id;
              print('>>> [LojaPublica] ⚠ Usando primeira empresa como padrão: $empresaIdParaUsar');
            } else {
              // SE ESPECIFICOU SLUG E NÃO ACHAMOS, É UM ERRO!
              print('>>> [LojaPublica] ❌ ERRO: Empresa "$slugDeteccao" não encontrada!');
              // Não vamos usar o fallback '1' se o slug for inválido
            }
          }
        } else {
          // Se não há empresas carregadas de jeito nenhum
          print('>>> [LojaPublica] ❌ Nenhuma empresa disponível no sistema');
        }
      }

      // 4. Configurar DataService
      if (empresaIdParaUsar != null && empresaIdParaUsar.isNotEmpty) {
        if (dataService.empresaIdAtual != empresaIdParaUsar) {
          print('>>> [LojaPublica] Definindo nova empresa no DataService: $empresaIdParaUsar');
          await dataService.definirEmpresaAtual(empresaIdParaUsar).timeout(
            const Duration(seconds: 25),
            onTimeout: () => print('>>> [LojaPublica] Timeout definirEmpresaAtual'),
          );
        } else {
          print('>>> [LojaPublica] Empresa já ativa, apenas recarregando...');
          await dataService.recarregarDados().timeout(
            const Duration(seconds: 25),
            onTimeout: () => print('>>> [LojaPublica] Timeout recarregarDados'),
          );
        }
      }
      
      if (mounted) {
        setState(() {
          _empresaIdConfigurada = empresaIdParaUsar;
          _dadosCarregados = true;
        });

        // REFORÇO DE URL: Se for Web, garantir que o link original NÃO mude para '/'
        if (kIsWeb && empresaIdParaUsar != null) {
          final slug = widget.slugEmpresa ?? slugDeteccao;
          if (slug != null) {
            // Decidir rota baseada no estado atual
            final isAgendamento = widget.forceAgendamento || html_helper.getWindowPathname().contains('agendamento');
            final path = isAgendamento ? '/agendamento/$slug' : '/loja/$slug';
            
            // Usar replace: true para não criar entrada extra no histórico
            debugPrint('>>> [LojaPublica] Sincronizando URL forçadamente para: $path');
            html_helper.updateUrl(path, replace: true);
          }
        }
      }
    } catch (e) {
      print('>>> [LojaPublica] ❌ Erro crítico no carregamento: $e');
      if (mounted) setState(() {
        _dadosCarregados = true;
        _empresaIdConfigurada = _empresaIdConfigurada ?? '1'; // Fallback de emergência apenas em erro
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final dataService = Provider.of<DataService>(context);
    
    if (!_dadosCarregados) {
      return AppTheme.appBackground(
        child: const ExodoLoading(mensagem: 'Carregando serviços...'),
      );
    }

    if (_empresaIdConfigurada == null) {
      return AppTheme.appBackground(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 64),
                const SizedBox(height: 16),
                const Text(
                  'Empresa não encontrada',
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'O link "${widget.slugEmpresa}" não corresponde a nenhuma empresa ativa.',
                  style: const TextStyle(color: Colors.white70),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () => _carregarDados(),
                  child: const Text('Tentar Novamente'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final carrinhoService = Provider.of<CarrinhoService>(context, listen: false);
    if (_empresaIdConfigurada != null) {
      carrinhoService.configurarEmpresa(_empresaIdConfigurada!);
    }
    
    // Detecção dinâmica de tipo de rota (Agendamento vs Loja)
    bool isAgendamento = widget.forceAgendamento;
    if (!isAgendamento) {
      try {
        final uri = Uri.base;
        final segments = uri.pathSegments;
        if (segments.any((s) => s.toLowerCase() == 'agendamento')) {
          isAgendamento = true;
        } else if (uri.fragment.toLowerCase().contains('agendamento')) {
          isAgendamento = true;
        }
      } catch (_) {}
    }

    Widget child;
    if (isAgendamento) {
      child = AgendamentoPublicoPage(slugEmpresa: widget.slugEmpresa);
    } else {
      child = LojaPublicaPage(
        codigoLink: widget.codigoLink.isNotEmpty ? widget.codigoLink : null,
      );
    }

    // Reforçar a URL no build se ela estiver vazia ou resetada (segurança extra)
    if (kIsWeb && _dadosCarregados && _empresaIdConfigurada != null) {
       final currentPath = html_helper.getWindowPathname();
       if (currentPath == '/' || currentPath.isEmpty) {
          final slug = widget.slugEmpresa ?? _empresaIdConfigurada;
          if (slug != null) {
            final path = isAgendamento ? '/agendamento/$slug' : '/loja/$slug';
            html_helper.updateUrl(path, replace: true);
          }
       }
    }

    // Cores da empresa atualizadas do DataService
    Color? corP;
    Color? corS;
    final empresaAtual = dataService.empresaAtual;
    
    if (empresaAtual != null) {
      try {
        if (empresaAtual.corPrimaria != null) {
          String hex = empresaAtual.corPrimaria!.replaceAll('#', '');
          if (hex.length == 6) corP = Color(int.parse("FF$hex", radix: 16));
        }
        if (empresaAtual.corSecundaria != null) {
          String hex = empresaAtual.corSecundaria!.replaceAll('#', '');
          if (hex.length == 6) corS = Color(int.parse("FF$hex", radix: 16));
        }
      } catch (e) {
        debugPrint('Erro cores: $e');
      }
    }

    return AppTheme.appBackground(
      child: child,
      corPrimaria: corP,
      corSecundaria: corS,
    );
  }
}
