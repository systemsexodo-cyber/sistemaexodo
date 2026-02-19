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
  bool _estaCarregando = false; // Guarda para evitar loop infinito
  String? _empresaIdConfigurada;
  String? _ultimoSlugProcessado;

  @override
  void initState() {
    super.initState();
    print('>>> [LojaPublicaWrapper] @INIT - Slug: ${widget.slugEmpresa} | ForceAgendamento: ${widget.forceAgendamento}');
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
    
    // Evitar disparar se já estamos carregando ou se já terminou com sucesso
    if (_estaCarregando || _dadosCarregados) return;

    final authService = Provider.of<AuthService>(context);
    // Retentar apenas se as empresas chegaram e ainda não configuramos o ID
    if (_empresaIdConfigurada == null && authService.empresas.isNotEmpty) {
      debugPrint('>>> [LojaPublicaWrapper] @CHANGES - Empresas chegaram, disparando carregamento...');
      _carregarDados();
    }
  }

  Future<void> _carregarDados() async {
    if (_estaCarregando) return;
    
    setState(() {
      _estaCarregando = true;
    });

    final dataService = Provider.of<DataService>(context, listen: false);
    final authService = Provider.of<AuthService>(context, listen: false);
    
    final currentSlug = widget.slugEmpresa;
    _ultimoSlugProcessado = currentSlug;

    String? empresaIdParaUsar;

    try {
      // 1. Tentar encontrar a empresa solicitada IMEDIATAMENTE (Otimizado)
      if (currentSlug != null && currentSlug.isNotEmpty) {
        final detectada = await authService.buscarEmpresaPorSlugAsync(currentSlug);
        if (detectada != null) {
          print('>>> [LojaPublica] ✅ Empresa detectada via Busca Direta: ${detectada.nomeExibicao}');
          empresaIdParaUsar = detectada.id;
          dataService.setEmpresaAtual(detectada); 
        } else {
          // Retentativa rápida para casos de latência do Firebase (o "não encontrada ainda" do usuário)
          debugPrint('>>> [LojaPublica] ⏳ Slug não encontrado de primeira, aguardando 1.5s para retentar...');
          await Future.delayed(const Duration(milliseconds: 1500));
          final detectada2 = await authService.buscarEmpresaPorSlugAsync(currentSlug);
          if (detectada2 != null) {
            print('>>> [LojaPublica] ✅ Empresa detectada na Retentativa: ${detectada2.nomeExibicao}');
            empresaIdParaUsar = detectada2.id;
            dataService.setEmpresaAtual(detectada2);
          }
        }
      }

      // 2. Se ainda não achamos, vamos esperar um pouco se o AuthService ainda estiver carregando a lista global
      if (empresaIdParaUsar == null) {
        int tentativas = 0;
        int maxTentativas = 8; // Reduzido para 4s total de espera passiva
        
        while (tentativas < maxTentativas) {
          if (authService.empresas.isNotEmpty) break;
          
          if (authService.isCarregandoDados) {
            await Future.delayed(const Duration(milliseconds: 500));
            tentativas++;
          } else {
            break;
          }
        }
      }
      
      String? slugDeteccao = currentSlug;
      
      // Detecção redundante da URL se o widget não recebeu o slug (Fallback Web)
      if (empresaIdParaUsar == null && (slugDeteccao == null || slugDeteccao.isEmpty)) {
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
                'personalizar-loja', 'agenda-pet', 'gerenciar-imagens', 'servico',
                'caixa', 'comissoes', 'entregas', 'empresas', 'taxas-entrega', 
                'gerenciar-permissoes', 'historico-vendas', 'historico-operacoes',
                'gerenciar-usuarios', 'trocas-devolucoes', 'configuracoes-agenda'
              };
              if (!reservados.contains(first)) {
                slugDeteccao = first;
              }
            }
          }
        }
      }

      // 3. Localizar Empresa se ainda não temos o ID
      if (empresaIdParaUsar == null && slugDeteccao != null && slugDeteccao.isNotEmpty) {
        print('>>> [LojaPublica] Buscando empresa para slug: "$slugDeteccao" (Fase Final)');
        final empresaPorSlug = await authService.buscarEmpresaPorSlugAsync(slugDeteccao);
        if (empresaPorSlug != null) {
          empresaIdParaUsar = empresaPorSlug.id;
          dataService.setEmpresaAtual(empresaPorSlug);
          print('>>> [LojaPublica] ✅ Empresa encontrada por slug: ${empresaPorSlug.nomeExibicao} (ID: $empresaIdParaUsar)');
        } else {
          print('>>> [LojaPublica] ⚠ Slug "$slugDeteccao" não encontrado em ${authService.empresas.length} empresas');
        }
      }

      // 4. Fallback final se não encontrar pelo slug
      if (empresaIdParaUsar == null) {
        if (authService.empresas.isNotEmpty) {
          // Se tiver um slug mas não achamos, vamos tentar achar por ID direto
          if (slugDeteccao != null) {
             final porId = authService.empresas.any((e) => e.id == slugDeteccao);
             if (porId) {
                final empObj = authService.empresas.firstWhere((e) => e.id == slugDeteccao);
                empresaIdParaUsar = empObj.id;
                dataService.setEmpresaAtual(empObj);
                print('>>> [LojaPublica] ✅ Empresa encontrada por ID direto: ${empObj.nomeExibicao} ($empresaIdParaUsar)');
              }
          }
          
          if (empresaIdParaUsar == null) {
            // Se ainda assim não achamos e o usuário não especificou slug, usar a primeira
            if (slugDeteccao == null || slugDeteccao.isEmpty) {
              empresaIdParaUsar = authService.empresas.first.id;
              dataService.setEmpresaAtual(authService.empresas.first);
              print('>>> [LojaPublica] ⚠ Usando primeira empresa como padrão: $empresaIdParaUsar');
            } else {
              // SE ESPECIFICOU SLUG E NÃO ACHAMOS, É UM ERRO!
              print('>>> [LojaPublica] ❌ ERRO: Empresa "$slugDeteccao" não encontrada!');
            }
          }
        } else {
          // Se não há empresas carregadas de jeito nenhum
          print('>>> [LojaPublica] ❌ Nenhuma empresa disponível no sistema');
        }
      }

      // 5. Configurar DataService definitivamente
      if (empresaIdParaUsar != null && empresaIdParaUsar.isNotEmpty) {
        if (dataService.empresaIdAtual != empresaIdParaUsar) {
          print('>>> [LojaPublica] Definindo nova empresa no DataService: $empresaIdParaUsar');
          await dataService.definirEmpresaAtual(empresaIdParaUsar, modoLeve: true).timeout(
            const Duration(seconds: 25),
            onTimeout: () => print('>>> [LojaPublica] Timeout definirEmpresaAtual'),
          );
        } else {
          print('>>> [LojaPublica] Empresa já ativa, apenas recarregando...');
          await dataService.recarregarDados(modoLeve: true).timeout(
            const Duration(seconds: 25),
            onTimeout: () => print('>>> [LojaPublica] Timeout recarregarDados'),
          );
        }
      }
      
      if (mounted) {
        setState(() {
          _empresaIdConfigurada = empresaIdParaUsar;
          _dadosCarregados = true;
          _estaCarregando = false;
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
        _estaCarregando = false;
        // Não definir fallback '1' aqui se temos um slug, para mostrar a tela de erro correta
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

    debugPrint('>>> [LojaPublicaWrapper] build() -> isAgendamento: $isAgendamento | forceAgendamento: ${widget.forceAgendamento}');

    Widget child;
    if (isAgendamento) {
      debugPrint('>>> [LojaPublicaWrapper] Renderizando AgendamentoPublicoPage');
      child = AgendamentoPublicoPage(slugEmpresa: widget.slugEmpresa);
    } else {
      debugPrint('>>> [LojaPublicaWrapper] Renderizando LojaPublicaPage');
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
