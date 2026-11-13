import 'package:flutter/material.dart';

import 'package:sistema_exodo_novo/theme.dart';
import 'package:sistema_exodo_novo/pages/home_page.dart';
import 'package:sistema_exodo_novo/pages/bloqueio_mensalidade_page.dart';
import 'package:sistema_exodo_novo/pages/ativacao_licenca_page.dart';
import 'package:sistema_exodo_novo/pages/login_page.dart';
import 'package:sistema_exodo_novo/services/licenca_instalacao_service.dart';
import 'package:sistema_exodo_novo/pages/selecionar_empresa_page.dart';
import 'package:sistema_exodo_novo/pages/nfe_page.dart';
import 'package:sistema_exodo_novo/pages/portal_contador_page.dart';
import 'package:sistema_exodo_novo/pages/pedido_cliente_page.dart';
import 'package:sistema_exodo_novo/services/data_service.dart';
import 'package:sistema_exodo_novo/services/auth_service.dart';
import 'package:sistema_exodo_novo/models/empresa.dart';
import 'package:sistema_exodo_novo/services/cliente_auth_service.dart';
import 'package:sistema_exodo_novo/services/carrinho_service.dart';
import 'package:sistema_exodo_novo/services/theme_service.dart';
import 'package:sistema_exodo_novo/services/supabase_service.dart';
import 'package:sistema_exodo_novo/services/env_config.dart';
import 'package:sistema_exodo_novo/services/config_servidor_mobile.dart';
import 'package:sistema_exodo_novo/services/app_update_service.dart';
import 'package:sistema_exodo_novo/services/nfce_contingencia_service.dart';
import 'package:sistema_exodo_novo/services/nfce_xml_local_service.dart';
import 'package:sistema_exodo_novo/services/clock_check_service.dart';
import 'package:sistema_exodo_novo/services/diagnostico_layout_service.dart';
import 'package:sistema_exodo_novo/services/app_log_service.dart';

import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:ui' show AppExitResponse;
import 'package:provider/provider.dart';
import 'package:sistema_exodo_novo/widgets/exodo_loading.dart';
import 'package:sistema_exodo_novo/widgets/exodo_logo.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:sistema_exodo_novo/pages/loja_publica_wrapper.dart';
import 'package:sistema_exodo_novo/pages/html_helper_stub.dart'
    if (dart.library.html) 'package:sistema_exodo_novo/pages/html_helper_web.dart'
    as html_helper;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

Future<void> _corrigirSharedPreferencesCorrompido() async {
  if (kIsWeb) return;
  try {
    final supportDir = await getApplicationSupportDirectory();
    final file = File(p.join(supportDir.path, 'shared_preferences.json'));
    if (await file.exists()) {
      final size = await file.length();
      if (size == 0) {
        debugPrint(
          '>>> [AutoRepair] 🛠️ Corrigindo shared_preferences.json vazio (0 bytes)...',
        );
        await file.writeAsString('{}');
        return;
      }
      try {
        final content = await file.readAsString();
        jsonDecode(content);
      } catch (_) {
        debugPrint(
          '>>> [AutoRepair] 🛠️ Corrigindo shared_preferences.json corrompido...',
        );
        await file.writeAsString('{}');
      }
    }
  } catch (e) {
    debugPrint(
      '>>> [AutoRepair] ⚠️ Erro ao verificar/corrigir SharedPreferences: $e',
    );
  }
}

/// Grava um log de inicialização em boot.log para diagnosticar problemas
/// de abertura do app em máquinas novas (C:\Users\...\AppData\Roaming\...\boot.log).
Future<void> _logBoot(String msg) async {
  debugPrint('>>> [BOOT] $msg');
  if (kIsWeb) return;
  try {
    final supportDir = await getApplicationSupportDirectory();
    final logFile = File(p.join(supportDir.path, 'boot.log'));
    await logFile.writeAsString(
      '${DateTime.now().toIso8601String()} - $msg\n',
      mode: FileMode.append,
    );
  } catch (_) {}
}

/// Instala a empresa no DataService na ordem segura (usada no pós-frame do
/// builder quando a empresa do AuthService mudou).
///
/// ORDEM IMPORTANTE (igual ao `onEmpresaSelecionada`): `definirEmpresaAtual`
/// PRIMEIRO — ele limpa a memória e fixa `_currentEmpresaId` na empresa nova.
/// Se `setEmpresaAtual` rodasse antes, as listas de configuração (perfis,
/// estoques, métodos de pagamento) eram recarregadas da empresa nova no
/// estado DE:empresa-ANTIGA, e qualquer gravação nesse intervalo usava a
/// chave da empresa antiga — era assim que os estoques de uma empresa
/// apareciam/eram gravados na outra ao trocar de empresa.
Future<void> _migrarEmpresaBoot(
  DataService dataService,
  Empresa empresa,
) async {
  await dataService.definirEmpresaAtual(empresa.id);
  dataService.setEmpresaAtual(empresa);
}

/// Fila de gravação do log de erros.
///
/// As gravações são assíncronas e antes rodavam TODAS ao mesmo tempo. Quando
/// três erros caíam no mesmo frame, os blocos saíam embaralhados no arquivo
/// (pilhas cortadas no meio) e entradas inteiras se perdiam — a PIOR delas é
/// justamente a primeira, que é a que explica a tela vermelha. Agora cada
/// gravação só começa quando a anterior termina.
Future<void> _filaDoLogDeErros = Future<void>.value();

/// Grava um erro do framework (tela vermelha) em erro_flutter.log, no mesmo
/// diretório do boot.log, com o contexto (widget que estava sendo construído)
/// e a pilha completa. Sem isto o erro só existe no console do `flutter run` —
/// quando o app é fechado (ou quando se olha só a tela) a causa se perde.
Future<void> _logErroFramework(
  FlutterErrorDetails details, {
  String origem = 'FLUTTER',
}) {
  final gravar = _filaDoLogDeErros.then(
    (_) => _gravarErroFramework(details, origem: origem),
  );
  _filaDoLogDeErros = gravar.catchError((_) {});
  return gravar;
}

/// Grava UM erro no arquivo, em partes.
///
/// Cada parte é gravada sozinha e protegida por conta própria DE PROPÓSITO: o
/// relatório de estouro de layout anda na árvore de renderização, e quando a
/// árvore JÁ está quebrada (que é o caso de uma tela vermelha) esse passe pode
/// estourar. Antes, uma falha no diagnóstico levava junto a mensagem do erro —
/// a causa raiz se perdia no meio do caminho. Agora o essencial (erro +
/// contexto) é gravado primeiro, e só depois vêm os enfeites.
Future<void> _gravarErroFramework(
  FlutterErrorDetails details, {
  String origem = 'FLUTTER',
}) async {
  if (kIsWeb) return;
  late final File logFile;
  try {
    final supportDir = await getApplicationSupportDirectory();
    logFile = File(p.join(supportDir.path, 'erro_flutter.log'));
    // Não deixa o arquivo crescer sem limite numa máquina em uso diário.
    if (await logFile.exists() && await logFile.length() > 1024 * 1024) {
      await logFile.writeAsString('');
    }
    final buffer = StringBuffer()
      ..writeln(
        '════════════════ ${DateTime.now().toIso8601String()} [$origem] ════════════════',
      )
      ..writeln('Erro: ${details.exception.runtimeType}: ${details.exception}')
      ..writeln('Contexto: ${details.context?.toString() ?? '(sem contexto)'}')
      ..writeln('Biblioteca: ${details.library}');
    await logFile.writeAsString(buffer.toString(), mode: FileMode.append);
  } catch (_) {
    return;
  }

  // O que o Flutter sabe do erro (inclui o "error-causing widget", com arquivo
  // e linha — é o que aponta o culpado direto no nosso código).
  try {
    final informacoes =
        details.informationCollector?.call() ?? const <DiagnosticsNode>[];
    if (informacoes.isNotEmpty) {
      final buffer = StringBuffer();
      for (final info in informacoes) {
        buffer
          ..writeln('----')
          ..writeln(info.toStringDeep());
      }
      await logFile.writeAsString(buffer.toString(), mode: FileMode.append);
    }
  } catch (_) {}

  // Estouro de layout (RenderFlex overflow): o log do Flutter não diz QUAL
  // filho é o gigante. Este relatório anda na árvore de renderização e aponta
  // o widget culpado — é o que permite corrigir sem adivinhar.
  try {
    final estouro = DiagnosticoLayoutService.relatorioDeEstouro(details);
    if (estouro != null) {
      await logFile.writeAsString('$estouro\n', mode: FileMode.append);
    }
  } catch (_) {}

  try {
    await logFile.writeAsString(
      'Pilha:\n${details.stack?.toString() ?? '(sem pilha)'}\n\n',
      mode: FileMode.append,
    );
  } catch (_) {}

  debugPrint('>>>>> [ERRO GLOBAL] log gravado em ${logFile.path}');
}

void main() {
  runZonedGuarded<void>(
    () async => _main(),
    (Object error, StackTrace stack) {
      unawaited(
        AppLogService.registrar('$error\nPilha:\n$stack', nivel: 'UNHANDLED'),
      );
      unawaited(
        _logErroFramework(
          FlutterErrorDetails(exception: error, stack: stack),
          origem: 'UNHANDLED',
        ),
      );
    },
    zoneSpecification: ZoneSpecification(
      print: (self, parent, zone, line) {
        parent.print(zone, line);
        unawaited(AppLogService.registrar(line, nivel: 'PRINT'));
      },
    ),
  );
}

Future<void> _main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await AppLogService.inicializar();
  AppLogService.instalarHookDebugPrint();

  await _logBoot(
    'BOOT iniciando (versao ${AppUpdateService.currentAppVersion})',
  );

  // Carrega o `.env` EMPACOTADO no aplicativo (usado no celular, onde não há
  // `.env` no disco). No PC o `.env` do disco tem prioridade e é lido sozinho;
  // aqui garantimos que a configuração exista cedo, antes do login e do banco.
  await EnvConfig.carregarDoAsset();
  await _logBoot('Configuracao (.env) verificada');

  // No CELULAR o endereço do banco pode ter sido informado pelo usuário na
  // tela "Configurar servidor". Esses valores têm prioridade sobre o `.env`
  // empacotado — é o que permite o MESMO APK funcionar em qualquer loja.
  try {
    final configCelular = await ConfigServidorMobile.carregar();
    if (configCelular.isNotEmpty) {
      EnvConfig.aplicarOverrides(configCelular);
      await _logBoot(
        'Servidor do celular: ${configCelular['DB_HOST']}:${configCelular['DB_PORT']}',
      );
    }
  } catch (e) {
    await _logBoot('Falha ao ler configuracao do celular: $e');
  }

  // CAPTURAR ERROS GLOBAIS PARA DEBUG
  FlutterError.onError = (FlutterErrorDetails details) {
    // BUG CONHECIDO DO FLUTTER (nao e do nosso codigo):
    // 'referenceBox.attached' acontece quando o mouse esta sobre um InkWell
    // (efeito de toque) e o widget sai da tela/recebe rebuild no mesmo quadro
    // - tipico ao abrir/fechar um dialogo com o mouse em cima de um card.
    // E uma falha de pintura do framework; o app continua funcionando.
    // Ignoramos para nao derrubar a tela com o erro vermelho.
    final textoErro = details.exception.toString();
    if (textoErro.contains('referenceBox.attached')) {
      return;
    }
    FlutterError.presentError(details);
    debugPrint(
      '>>>>> [ERRO GLOBAL] ${details.exception.runtimeType}: ${details.exception}',
    );
    debugPrint('>>>>> Stack trace completo:');
    debugPrint(details.stack.toString());
    debugPrint('>>>>> FIM DO STACK TRACE');
    unawaited(_logErroFramework(details));
  };
  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    debugPrint('>>>>> [ERRO PLATFORM] $error');
    debugPrint('>>>>> Stack: $stack');
    unawaited(
      _logErroFramework(
        FlutterErrorDetails(exception: error, stack: stack),
        origem: 'PLATFORM',
      ),
    );
    return true;
  };

  // Corrigir arquivo corrompido de shared_preferences se houver
  await _corrigirSharedPreferencesCorrompido();
  await _logBoot('SharedPreferences verificado');

  // Inicialização do Supabase - COM TIMEOUT para nunca travar a abertura do app.
  // A inicializacao do Supabase faz uma chamada HTTP (busca OIDC). Em maquina
  // nova SEM acesso a nuvem, isso podia travar PARA SEMPRE antes do runApp(),
  // fazendo o app 'nao abrir / nao carregar'. Agora: se nao responder em 8s,
  // o app abre mesmo assim (offline) e a sincronizacao tenta depois.
  // NÃO bloqueia a abertura do app: o Supabase é a NUVEM (espelho assíncrono) e
  // o sistema roda local. Antes, aguardar aqui segurava o boot até 12s numa
  // máquina sem internet. Agora o app abre na hora e inicializa/verifica em
  // background; todo acesso à nuvem já se protege com isAvailable/erro.
  await _logBoot('Inicializando Supabase em background...');
  unawaited(
    SupabaseService.initialize()
        .timeout(const Duration(seconds: 15))
        .then((_) => _logBoot('Supabase inicializado'))
        .catchError((Object e) {
          debugPrint(
            '>>> [SISTEMA] ⚠️ Supabase timeout/erro (app segue offline): $e',
          );
          _logBoot('Supabase timeout/erro (offline): $e');
        }),
  );

  if (kIsWeb) {
    try {
      print('>>> [SISTEMA] Iniciando Boot em modo Web');
      await Hive.initFlutter();
      print('>>> ✓ Hive inicializado com sucesso no Web');
    } catch (e) {
      print('>>> [SISTEMA] Erro no Boot / Hive: $e');
    }
  } else {
    try {
      await Hive.initFlutter();
      await _logBoot('Hive inicializado');
    } catch (e) {
      debugPrint('>>> [SISTEMA] ⚠️ Erro ao inicializar Hive: $e');
      await _logBoot('ERRO Hive: $e');
    }
  }

  print(
    '>>> [APLICATIVO] Iniciando Versão ${AppUpdateService.currentAppVersion} (Fix: Cache & Sync)...',
  );

  if (kIsWeb) {
    // No Web, podemos tentar usar o pathUrlStrategy se necessário,
    // mas para evitar crash nativo, vamos apenas comentar ou remover
    // até que esteja corretamente isolado.
    // usePathUrlStrategy();
  }

  debugPrint('>>> [SISTEMA] Sistema inicializado com Supabase');

  // Inicializa os serviços
  final dataService = DataService();
  // Carrega o carimbo local antes de qualquer tela verificar a mensalidade.
  // Sem isso, uma instalação offline poderia iniciar com validação nula.
  await dataService.carregarLiberacaoProvisoria();
  final authService = AuthService();
  final clienteAuthService = ClienteAuthService();
  final carrinhoService = CarrinhoService();

  // Mantém a empresa do AuthService em sincronia quando o DataService persiste
  // mudanças de configuração (ex.: perfil tributário padrão). Evita que a
  // config antiga seja reaplicada ao reabrir/trocar a empresa.
  dataService.onEmpresaAtualizada = authService.sincronizarEmpresaEmMemoria;

  // Toda troca de empresa (inclusive pela tela "Empresas") precisa passar pelo
  // DataService: limpar a memória e recarregar somente os dados da empresa nova.
  // Antes, alguns fluxos chamavam só `setEmpresaAtual`, e funcionários/perfis da
  // empresa anterior continuavam visíveis e eram gravados na empresa errada.
  //
  // ORDEM IMPORTANTE: `definirEmpresaAtual` PRIMEIRO. Ele limpa a memória e
  // fixa `_currentEmpresaId` na empresa nova. Se `setEmpresaAtual` rodasse
  // antes, `setEmpresaAtual` recarregava as listas de configuração (perfis,
  // departamentos, estoques) da empresa nova enquanto `_currentEmpresaId` era
  // ainda a empresa ANTERIOR — e qualquer "Tomar principal"/edição de estoque
  // feite nessa janela gravava a lista da empresa nova no cache da empresa
  // antiga (`_getChaveComEmpresa` usa `_currentEmpresaId`). Era assim que o
  // estoque principal mudado numa empresa aparecia trocado na outra.
  authService.onEmpresaSelecionada = (empresa) async {
    await dataService.definirEmpresaAtual(empresa.id);
    dataService.setEmpresaAtual(empresa);
  };

  // Inicializa o serviço de contingência (nunca deve impedir o app de abrir)
  try {
    await NfceContingenciaService.instance.inicializar();
    await _logBoot('Contingência inicializada');
  } catch (e) {
    debugPrint('>>> [SISTEMA] ⚠️ Erro ao inicializar contingência: $e');
    await _logBoot('ERRO contingência: $e');
  }

  // Fila de upload de XML: quando a nuvem recusa/está fora na hora da
  // autorização, o XML fica em disco e é reenviado a cada 5 min — sem isso a
  // nota nunca aparecia no Portal do Contador.
  try {
    await NfceXmlLocalService.inicializar();
    await _logBoot('Fila de upload de XML inicializada');
  } catch (e) {
    debugPrint('>>> [SISTEMA] ⚠️ Erro ao inicializar a fila de XML: $e');
    await _logBoot('ERRO fila de XML: $e');
  }

  // Rejeição de NFC-e não descarta a venda: a nota fica salva como 'pendente'.
  // O emissor não tem acesso ao DataService, então registramos aqui o hook que
  // reconcilia a nota quando a retransmissão automática (a cada 30s) autoriza.
  NfceContingenciaService.onNotaAutorizada = (nfce, numero) async {
    final antigas = dataService.nfces
        .where(
          (n) =>
              n.numero == numero &&
              (n.status == 'pendente' || n.status == 'contingencia'),
        )
        .toList();
    for (final antiga in antigas) {
      await dataService.atualizarNFCe(
        antiga.copyWith(
          status: 'autorizada',
          numero: nfce.numero,
          vendaNumero: nfce.numero,
          serie: nfce.serie,
          chaveAcesso: nfce.chaveAcesso,
          protocolo: nfce.protocolo,
          xmlEnviado: nfce.xmlEnviado,
          qrCode: nfce.qrCode,
          updatedAt: DateTime.now(),
        ),
      );
      debugPrint(
        '>>> [SISTEMA] NFC-e ${antiga.numero} reconciliada: pendente -> autorizada',
      );
    }

    // Nota autorizada pelo reenvio automático da fila (timer de 30 s) ou pelos
    // botões "Reenviar" NÃO passa pela emissão direta — e era justamente ela
    // que ficava sem XML no disco e no bucket `xmls` do Portal do Contador.
    var empresaDaNota = authService.empresaAtual;
    final empresaIdNota = nfce.empresaId.trim();
    if (empresaIdNota.isNotEmpty && empresaDaNota?.id != empresaIdNota) {
      for (final empresa in authService.empresas) {
        if (empresa.id == empresaIdNota) {
          empresaDaNota = empresa;
          break;
        }
      }
    }
    if (empresaDaNota != null) {
      unawaited(
        NfceXmlLocalService.salvarXmlAposEmissao(
          nfce: nfce,
          empresa: empresaDaNota,
        ),
      );
    }
  };

  // Rejeição 539 sem número livre: a fila para de retransmitir (a entrada já
  // é removida pelo serviço), e o histórico também não pode seguir 'pendente'
  // — a nota original nunca vai ser autorizada com aquele número. Marca a
  // falha na nota e trava TODOS os números que a SEFAZ confirmou ocupados
  // para que a sequência nunca mais os sugira.
  NfceContingenciaService.onDuplicidadeSemNumero =
      (empresaId, serie, numeroOriginal, motivo, numerosDuplicados) async {
        for (final numero in numerosDuplicados) {
          await dataService.marcarNumeroNfceComoOcupado(
            numero: numero,
            serie: serie,
          );
        }
        final antigas = dataService.nfces
            .where(
              (n) =>
                  n.numero == numeroOriginal &&
                  (n.status == 'pendente' || n.status == 'contingencia'),
            )
            .toList();
        for (final antiga in antigas) {
          await dataService.atualizarNFCe(
            antiga.copyWith(
              status: 'rejeitada',
              xmlRetorno: motivo,
              updatedAt: DateTime.now(),
            ),
          );
          debugPrint(
            '>>> [SISTEMA] NFC-e ${antiga.numero} marcada como rejeitada: '
            'duplicidade 539 sem número livre na série $serie',
          );
        }
      };

  // Números que a SEFAZ apontou como ocupados (539) viram reserva de
  // numeração no histórico — usado pelo emissor na busca automática de
  // número menor.
  NfceContingenciaService.onMarcarNumeroOcupado = (numero, serie) =>
      dataService.marcarNumeroNfceComoOcupado(numero: numero, serie: serie);

  // Régua do MENOR número livre usada pela fila de reenvio ao renumerar nota
  // que bateu em duplicidade: sem ela a busca continuava para baixo do número
  // rejeitado e terminava autorizando a nota lá em cima.
  NfceContingenciaService.onProximoNumeroLivre = (serie, numeroInicial) =>
      dataService.getProximoNumeroNfce(
        serie: serie,
        numeroInicial: numeroInicial,
      );

  // Inicia verificação do relógio em background (não bloqueia a inicialização)
  Future.delayed(const Duration(seconds: 5), () {
    ClockCheckService().verificar();
  });

  await _logBoot('Executando runApp');
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: dataService),
        ChangeNotifierProvider.value(value: authService),
        ChangeNotifierProvider.value(value: clienteAuthService),
        ChangeNotifierProvider.value(value: carrinhoService),
        ChangeNotifierProvider.value(value: NfceContingenciaService.instance),
        ChangeNotifierProvider(create: (_) => ThemeService()),
        ChangeNotifierProvider.value(value: ClockCheckService()),
      ],
      child: const MyApp(),
    ),
  );
}

class AppRouter {
  static const internos = {
    'login',
    'home',
    'dashboard',
    'admin',
    'auth',
    'selecionar-empresa',
    'debug',
    'clientes',
    'produtos',
    'servicos',
    'servico',
    'pedidos',
    'venda-direta',
    'pdv',
    'entrada-mercadorias',
    'pedidos-compra',
    'pedidos_compra',
    'contas-pagar',
    'agenda-contas',
    'cozinha-bar',
    'mesas',
    'links-vendedores',
    'pedidos-cliente',
    'pedido',
    'vendedor-dashboard',
    'funcionarios',
    'personalizar-loja',
    'agenda-pet',
    'gerenciar-imagens',
    'caixa',
    'comissoes',
    'entregas',
    'historico-vendas',
    'historico-operacoes',
    'gerenciar-usuarios',
    'trocas-devolucoes',
    'configuracoes-agenda',
    'taxas-entrega',
    'empresas',
    'gerenciar-permissoes',
    'nfe',
    'portal-contador',
  };

  static Map<String, dynamic> analisarUrl() {
    if (!kIsWeb)
      return {
        'publico': false,
        'slug': null,
        'agenda': false,
        'loja': false,
        'interna': null,
      };

    try {
      final String href = html_helper.getWindowOrigin();
      final String pathOrig = html_helper.getWindowPathname();
      final String path = pathOrig.toLowerCase();
      final String hashOrig = ""; // Simplificado para Windows
      final String hash = "";

      debugPrint('>>> [AppRouter] ANÁLISE URL:');
      debugPrint('    href: $href');
      debugPrint('    path: $pathOrig');

      final List<String> segmentsOrig = [];
      segmentsOrig.addAll(pathOrig.split('/').where((s) => s.isNotEmpty));

      String cleanHashOrig = hashOrig.replaceAll(RegExp(r'^[#!/? ]+'), '');
      if (cleanHashOrig.isNotEmpty) {
        segmentsOrig.addAll(
          cleanHashOrig.split('/').where((s) => s.isNotEmpty),
        );
      }

      final List<String> segmentsLower = segmentsOrig
          .map((s) => s.toLowerCase())
          .toList();

      debugPrint('    segments: $segmentsOrig');

      if (segmentsOrig.isEmpty) {
        debugPrint('    RESULTADO: Home (sem segmentos)');
        return {
          'publico': false,
          'slug': null,
          'agenda': false,
          'loja': false,
          'interna': 'home',
          'href': href,
        };
      }

      // Acompanhamento do pedido pelo cliente: /pedido/<codigo>
      if (segmentsLower.contains('pedido')) {
        final idx = segmentsLower.indexOf('pedido');
        final codigo = (idx != -1 && idx + 1 < segmentsOrig.length)
            ? segmentsOrig[idx + 1]
            : '';
        debugPrint('    RESULTADO: Acompanhamento de Pedido | Codigo: $codigo');
        return {
          'publico': false,
          'slug': null,
          'agenda': false,
          'loja': false,
          'interna': 'pedido',
          'link': codigo,
          'href': href,
        };
      }

      // Detecção de Agendamento
      if (segmentsLower.contains('agendamento')) {
        int idx = segmentsLower.indexOf('agendamento');
        String? slug = (idx != -1 && idx + 1 < segmentsOrig.length)
            ? segmentsOrig[idx + 1]
            : null;
        debugPrint('    RESULTADO: Agendamento Público | Slug: $slug');
        return {
          'publico': true,
          'slug': slug,
          'agenda': true,
          'loja': false,
          'interna': null,
          'href': href,
        };
      }

      // Detecção de Loja
      if (segmentsLower.contains('loja') || segmentsLower.contains('shop')) {
        int idx = segmentsLower.indexOf('loja');
        if (idx == -1) idx = segmentsLower.indexOf('shop');
        String? slug = (idx != -1 && idx + 1 < segmentsOrig.length)
            ? segmentsOrig[idx + 1]
            : null;
        debugPrint('    RESULTADO: Loja Pública | Slug: $slug');
        return {
          'publico': true,
          'slug': slug,
          'agenda': false,
          'loja': true,
          'interna': null,
          'href': href,
        };
      }

      // Rota Interna
      final firstLower = segmentsLower[0];
      if (internos.contains(firstLower)) {
        debugPrint('    RESULTADO: Rota Interna | Rota: $firstLower');
        return {
          'publico': false,
          'slug': null,
          'agenda': false,
          'loja': false,
          'interna': firstLower,
          'href': href,
        };
      }

      // Fallback para Loja por Slug Direto (ex: /petshop)
      final firstOrig = segmentsOrig[0];
      debugPrint(
        '    RESULTADO: Loja Pública por Slug Direto | Slug: $firstOrig',
      );
      return {
        'publico': true,
        'slug': firstOrig,
        'agenda': false,
        'loja': true,
        'interna': null,
        'href': href,
      };
    } catch (e) {
      debugPrint('>>> [AppRouter] Erro ao analisar URL: $e');
      return {
        'publico': false,
        'slug': null,
        'agenda': false,
        'loja': false,
        'interna': null,
      };
    }
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  StreamSubscription? _hashChangeSubscription;
  StreamSubscription? _popStateSubscription;
  AppLifecycleListener? _lifecycleListener;

  // CACHE da análise de rota inicial - evita recalcular a cada rebuild do Consumer
  Map<String, dynamic>? _rotaInicialCache;

  @override
  void initState() {
    super.initState();

    // PERSISTÊNCIA GARANTIDA: ao fechar o app, força o salvamento de todas as
    // coleções pendentes no PostgreSQL local (nada fica só em memória).
    // O DataService é acessado via Provider no momento do evento (context ainda válido).
    if (!kIsWeb) {
      _lifecycleListener = AppLifecycleListener(
        onExitRequested: () async {
          debugPrint(
            '>>> [Lifecycle] App fechando — forçando persistência final...',
          );
          try {
            if (!mounted) return AppExitResponse.exit;
            final dataService = Provider.of<DataService>(
              context,
              listen: false,
            );
            await dataService.salvarDadosAgora();
          } catch (e) {
            debugPrint(
              '>>> [Lifecycle] ⚠️ Erro ao salvar dados no fechamento: $e',
            );
          }
          return AppExitResponse.exit;
        },
      );
    }

    // Analisar a rota APENAS UMA VEZ no início
    _rotaInicialCache = AppRouter.analisarUrl();
    debugPrint('>>> [MyApp] Rota inicial cacheada: $_rotaInicialCache');

    if (kIsWeb) {
      // 1. Ouvir mudanças no Hash (#)
      _hashChangeSubscription = html_helper.onWindowFocus.listen((event) {
        debugPrint('>>> [Routing] Navegação detectada');
        // Reanalisar a URL somente se a mudança veio de navegação real do browser
        _rotaInicialCache = AppRouter.analisarUrl();
        if (mounted) setState(() {});
      });

      // 2. Ouvir mudanças no Path (sem #) - Necessário para usePathUrlStrategy
      _popStateSubscription = html_helper.onWindowFocus.listen((event) {
        debugPrint('>>> [Routing] Navegação detectada');
        // Reanalisar a URL somente quando o usuário navega pelo browser (back/forward)
        _rotaInicialCache = AppRouter.analisarUrl();
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _hashChangeSubscription?.cancel();
    _popStateSubscription?.cancel();
    _lifecycleListener?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<AuthService, ThemeService>(
      builder: (context, authService, themeService, _) {
        // 1. USAR ROTA CACHEADA - Não recalcular a cada rebuild do Consumer!
        final rotaMap = _rotaInicialCache ?? AppRouter.analisarUrl();

        final bool mostrarPublico = rotaMap['publico'] ?? false;
        final String? slugEmpresa = rotaMap['slug'];
        final bool isAgendamentoRoute = rotaMap['agenda'] ?? false;
        final String? subRotaInterna = rotaMap['interna'];
        final String? codigoLink = null;

        // 2. CONFIGURAR TEMA (Baseado no ThemeService e empresa)
        final empresaCores = authService.empresaAtual;
        final config = themeService.getThemeConfig(
          AppTheme.getCoresEmpresa(
            empresaCores?.corPrimaria,
            empresaCores?.corSecundaria,
          )['primaria'],
          AppTheme.getCoresEmpresa(
            empresaCores?.corPrimaria,
            empresaCores?.corSecundaria,
          )['secundaria'],
        );

        // LOG DE DIAGNÓSTICO FINAL
        debugPrint('>>> [SISTEMA-ROTA] Montando MaterialApp (cache):');
        debugPrint('    Público: $mostrarPublico');
        debugPrint('    Slug: $slugEmpresa');
        debugPrint('    Agendamento: $isAgendamentoRoute');
        debugPrint('    Rota Interna: $subRotaInterna');

        return MaterialApp(
          title: isAgendamentoRoute ? 'Agendamento Online' : 'Exodo',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.getTheme(
            corPrimaria: config['primaria'],
            corSecundaria: config['secundaria'],
            corFundo: config['fundo'],
            brightness: config['brightness'] ?? Brightness.dark,
          ),
          darkTheme: AppTheme.darkTheme,
          themeMode: ThemeMode.system,
          home: mostrarPublico
              ? LojaPublicaWrapper(
                  codigoLink: codigoLink ?? '',
                  slugEmpresa: slugEmpresa,
                  forceAgendamento: isAgendamentoRoute,
                )
              : (subRotaInterna == 'portal-contador'
                    ? const PortalContadorPage()
                    : subRotaInterna == 'pedido'
                    ? pedidoClientePageBuilder(
                        (rotaMap['link'] ?? '').toString(),
                      )
                    : subRotaInterna == 'pedidos-cliente'
                    ? pedidoClientePageBuilder(subRotaInterna!)
                    : AuthWrapper(subRota: subRotaInterna)),
          builder: (context, child) {
            if (child == null)
              return const Center(child: CircularProgressIndicator());

            return MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.noScaling),
              child: _LicencaGate(child: child),
            );
          },
        );
      },
    );
  }
}

/// Mostra [child] dentro de uma Overlay própria.
///
/// O gate de licença substitui o `child` do `MaterialApp.builder`, e esse
/// `child` é o Navigator do app — ou seja, ao bloquear a tela o Overlay do
/// Navigator some. Sem Overlay, Tooltips, o menu de seleção de texto e os
/// SnackBars quebram com "No Overlay widget found". Esta camada devolve a
/// Overlay que os widgets Material esperam.
class _CamadaOverlay extends StatefulWidget {
  final Widget child;
  const _CamadaOverlay({required this.child});

  @override
  State<_CamadaOverlay> createState() => _CamadaOverlayState();
}

class _CamadaOverlayState extends State<_CamadaOverlay> {
  late final OverlayEntry _entrada;

  @override
  void initState() {
    super.initState();
    _entrada = OverlayEntry(builder: (_) => widget.child);
  }

  @override
  void didUpdateWidget(covariant _CamadaOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.child, widget.child)) {
      _entrada.markNeedsBuild();
    }
  }

  @override
  void dispose() {
    // A Overlay (filha) já foi desmontada antes daqui, então a entrada pode
    // estar desanexada — remover nesse caso lançaria asserção.
    if (_entrada.mounted) _entrada.remove();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Overlay(initialEntries: [_entrada]);
  }
}

/// Trava do sistema instalado: sem licença de instalação válida (30 dias,
/// amarrada a este computador) o app não passa daqui. Copiar o setup para
/// outro PC não libera a licença, porque ela é vinculada ao MachineGuid.
class _LicencaGate extends StatefulWidget {
  final Widget child;
  const _LicencaGate({required this.child});

  @override
  State<_LicencaGate> createState() => _LicencaGateState();
}

class _LicencaGateState extends State<_LicencaGate> {
  bool _carregando = true;
  ResultadoLicencaInstalacao? _resultado;

  @override
  void initState() {
    super.initState();
    _verificar();
  }

  Future<void> _verificar() async {
    if (kIsWeb || !Platform.isWindows) {
      if (mounted) setState(() => _carregando = false);
      return;
    }
    ResultadoLicencaInstalacao resultado;
    try {
      resultado = await LicencaInstalacaoService.verificar();
    } catch (e) {
      debugPrint('>>> [LicencaGate] Falha ao verificar licença: $e');
      resultado = ResultadoLicencaInstalacao(
        estado: EstadoLicencaInstalacao.invalida,
        mensagem:
            'Não foi possível verificar a licença deste computador.\n$e',
      );
    }
    if (!mounted) return;
    setState(() {
      _resultado = resultado;
      _carregando = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Web (loja/agendamento) e celular não usam a licença de instalação.
    if (kIsWeb || !Platform.isWindows) return widget.child;

    if (_carregando) {
      return _CamadaOverlay(
        child: AppTheme.appBackground(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                ExodoLogo(fontSize: 54, showSubtitle: true),
                SizedBox(height: 32),
                SizedBox(
                  width: 32,
                  height: 32,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Color(0xFFFF9800),
                    ),
                  ),
                ),
                SizedBox(height: 20),
                Text(
                  'Verificando licença deste computador...',
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final resultado = _resultado;
    if (resultado == null || !resultado.podeUsar) {
      return _CamadaOverlay(
        child: AtivacaoLicencaPage(
          resultado:
              resultado ??
              const ResultadoLicencaInstalacao(
                estado: EstadoLicencaInstalacao.ausente,
                mensagem: 'Este computador ainda não foi ativado.',
              ),
          aoLiberar: _verificar,
        ),
      );
    }

    return widget.child;
  }
}

class AuthWrapper extends StatefulWidget {
  final String? subRota;
  const AuthWrapper({super.key, this.subRota});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  bool _verificandoAtualizacao = false;
  bool _baixandoAtualizacao = false;
  double _progressoAtualizacao = 0.0;
  String _versaoRemota = '';
  String _erroAtualizacao = '';

  /// Detalhes da versão que está sendo baixada (), o que o suporte anotou ao
  /// publicar. Vem da nuvem em paralelo — não atrasa o download.
  String _notasAtualizacao = '';

  @override
  void initState() {
    super.initState();
    _checarAtualizacoes();
  }

  Future<void> _checarAtualizacoes() async {
    if (kIsWeb) return;
    if (!Platform.isWindows) return;

    setState(() {
      _verificandoAtualizacao =
          false; // Mudar para false: inicia o sistema local na hora
      _erroAtualizacao = '';
    });

    try {
      final auth = Provider.of<AuthService>(context, listen: false);
      final data = Provider.of<DataService>(context, listen: false);
      final emp = data.empresaAtual ?? auth.empresaAtual;

      final config = await AppUpdateService.verificarAtualizacao(
        empresaId: emp?.id,
        configsEmpresa: emp?.configuracoes,
      ).timeout(const Duration(seconds: 4));
      if (config != null) {
        final String downloadUrl = config['download_url'] ?? '';
        final String version = config['version'] ?? '';
        if (downloadUrl.isNotEmpty && version.isNotEmpty) {
          setState(() {
            _baixandoAtualizacao = true;
            _versaoRemota = version;
            _progressoAtualizacao = 0.0;
            _notasAtualizacao = '';
          });

          // Busca os detalhes em paralelo: se demorar, o download já começou.
          unawaited(
            AppUpdateService.buscarNotas(downloadUrl).then((texto) {
              if (mounted && texto != null && texto.isNotEmpty) {
                setState(() => _notasAtualizacao = texto);
              }
            }),
          );

          final (
            success,
            motivo,
          ) = await AppUpdateService.baixarEAplicarAtualizacao(
            downloadUrl,
            (progress) {
              if (mounted) {
                setState(() {
                  _progressoAtualizacao = progress;
                });
              }
            },
            // Marca da publicação: é o que libera uma nova tentativa quando o
            // suporte republica o pacote (a trava vale por publicação).
            publicadaEm: (config['publicada_em'] ?? '').toString(),
          );

          if (!success && mounted) {
            setState(() {
              _baixandoAtualizacao = false;
            });
            // O app continua funcionando na versão atual; dizer o motivo evita
            // a impressão de que "atualizou e não mudou nada".
            if (motivo.isNotEmpty) {
              showDialog<void>(
                context: context,
                builder: (context) => AlertDialog(
                  backgroundColor: const Color(0xFF1E1E2E),
                  title: const Text(
                    'Atualização não aplicada',
                    style: TextStyle(color: Colors.white),
                  ),
                  content: Text(
                    '$motivo\n\nVocê continua na versão atual. Avise o suporte.',
                    style: const TextStyle(color: Colors.white70),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('OK'),
                    ),
                  ],
                ),
              );
            }
          }
        }
      }
    } catch (e) {
      debugPrint('>>> [AuthWrapper] Erro no fluxo de atualizacao: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_verificandoAtualizacao) {
      return AppTheme.appBackground(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const ExodoLogo(
                fontSize: 60,
                showSubtitle: true,
                showPhoenix: true,
              ),
              const SizedBox(height: 48),
              SizedBox(
                width: 40,
                height: 40,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    Color(0xFFFF9800),
                  ),
                  backgroundColor: const Color(0xFFFF9800).withOpacity(0.15),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Buscando novas atualizações...',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_baixandoAtualizacao) {
      return AppTheme.appBackground(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const ExodoLogo(
                fontSize: 60,
                showSubtitle: true,
                showPhoenix: true,
              ),
              const SizedBox(height: 48),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF9800).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: const Color(0xFFFF9800).withOpacity(0.3),
                  ),
                ),
                child: Text(
                  'Nova Versão Disponível: $_versaoRemota',
                  style: const TextStyle(
                    color: Color(0xFFFF9800),
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Baixando atualização do sistema...',
                style: TextStyle(color: Colors.white70, fontSize: 15),
              ),
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 300,
                  height: 8,
                  child: LinearProgressIndicator(
                    value: _progressoAtualizacao,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      Color(0xFFFF9800),
                    ),
                    backgroundColor: Colors.white.withOpacity(0.1),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '${(_progressoAtualizacao * 100).toStringAsFixed(0)}% concluído',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              if (_notasAtualizacao.isNotEmpty) ...[
                const SizedBox(height: 20),
                Container(
                  width: 380,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'O que mudou nesta versão',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _notasAtualizacao,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 8),
              const Text(
                'O aplicativo será reiniciado automaticamente.',
                style: TextStyle(color: Colors.white30, fontSize: 12),
              ),
              const SizedBox(height: 32),
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    _baixandoAtualizacao = false;
                  });
                },
                icon: const Icon(Icons.close, color: Colors.white60, size: 16),
                label: const Text(
                  'Cancelar e Entrar',
                  style: TextStyle(color: Colors.white60, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_erroAtualizacao.isNotEmpty) {
      return AppTheme.appBackground(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  color: Color(0xFFFF9800),
                  size: 64,
                ),
                const SizedBox(height: 24),
                const Text(
                  'Ops! Não foi possível atualizar.',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _erroAtualizacao,
                  style: const TextStyle(color: Colors.white54, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 40),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF9800),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                      ),
                      onPressed: _checarAtualizacoes,
                      child: const Text('Tentar Novamente'),
                    ),
                    const SizedBox(width: 16),
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.white30),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                      ),
                      onPressed: () {
                        setState(() {
                          _erroAtualizacao = '';
                        });
                      },
                      child: const Text(
                        'Continuar sem Atualizar',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (kIsWeb) {
      final rotaMap = AppRouter.analisarUrl();
      if (rotaMap['publico'] == true) {
        return LojaPublicaWrapper(
          codigoLink: '',
          slugEmpresa: rotaMap['slug'],
          forceAgendamento: rotaMap['agenda'] == true,
        );
      }
    }

    final String? rotaInicial = widget.subRota;

    try {
      return Consumer2<AuthService, DataService>(
        builder: (context, authService, dataService, child) {
          try {
            // Se o AuthService está carregando dados iniciais, mostrar loading
            if (authService.isCarregandoDados == true) {
              return const ExodoLoading(
                mensagem: 'Carregando dados de autenticação...',
              );
            }

            // Se o DataService está carregando, mostrar loading
            if (dataService.isLoading == true) {
              return ExodoLoading(
                mensagem: dataService.mensagemLoading,
                progresso: dataService.progressoLoading,
              );
            }

            // Carga inicial da NUVEM: mantém a tela de carregando até os dados
            // chegarem, para o sistema não abrir com as telas vazias. Sai sozinho
            // quando terminar (ou no limite de segurança) e o botão "Continuar
            // sem esperar" libera caso a rede esteja lenta.
            if (dataService.sincronizandoInicial == true) {
              return ExodoLoading(
                mensagem: dataService.mensagemLoading,
                progresso: dataService.progressoLoading,
                segundosParaMostrarPular: 5,
                onPular: dataService.pularEsperaSincronizacaoInicial,
              );
            }

            // Se não está autenticado, mostra a página de login
            if (authService.isAuthenticated != true) {
              // Limpar empresa do DataService se não estiver autenticado
              if (dataService.currentEmpresaId != null) {
                Future.microtask(() => dataService.definirEmpresaAtual(null));
              }
              return const LoginPage();
            }

            // Se está autenticado mas não tem empresa selecionada, mostra seleção de empresa
            if (authService.temEmpresaSelecionada != true) {
              // Limpar empresa do DataService se não tiver empresa selecionada
              if (dataService.currentEmpresaId != null) {
                Future.microtask(() => dataService.definirEmpresaAtual(null));
              }
              // Importar SelecionarEmpresaPage aqui
              return const SelecionarEmpresaPage();
            }

            // Se está autenticado e tem empresa, definir empresa no DataService e mostrar home
            final empresaAtual = authService.empresaAtual;
            if (empresaAtual != null &&
                dataService.currentEmpresaId != empresaAtual.id) {
              // Só dispara o setup se realmente a empresa mudou
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (dataService.currentEmpresaId != empresaAtual.id) {
                  // Mesma ordem do onEmpresaSelecionada: trocar primeiro,
                  // instalar o objeto da empresa depois (evita o estado
                  // misto "empresa nova em memória + empresa antiga ativa").
                  unawaited(_migrarEmpresaBoot(dataService, empresaAtual));
                }
              });
              // Retornar loading enquanto o setup acontece (evita flash de tela)
              return const ExodoLoading(mensagem: 'Sincronizando empresa...');
            }

            // Garantir que a empresa está sincronizada sem disparar rebuild infinito
            if (empresaAtual != null &&
                dataService.empresaAtual?.id != empresaAtual.id) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                dataService.setEmpresaAtual(empresaAtual);
              });
            }

            // Liga este computador à empresa logada: é o que permite a nuvem
            // conferir a mensalidade certa quando a licença vencer.
            if (empresaAtual != null) {
              unawaited(
                LicencaInstalacaoService.vincularEmpresa(empresaAtual.id),
              );
            }

            // Sincronizar o usuário logado no DataService para auditoria
            if (authService.isAuthenticated &&
                authService.usuarioAtual != null) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                dataService.setUsuarioAtual(authService.usuarioAtual);
              });
            }

            // VALIDAR SE É O USUÁRIO MASTER / SUPORTE DO SISTEMA
            final usuario = authService.usuarioAtual;
            final email = usuario?.email.toLowerCase() ?? '';
            final isMaster =
                usuario != null &&
                (email == 'user' || email == 'admin' || email == 'suporte');

            // Usuário Master entra DIRETO no Portal Êxodo (SelecionarEmpresaPage)
            if (isMaster) {
              return const SelecionarEmpresaPage();
            }

            // Para os demais usuários (ex: Silvia):
            final empresaLocal = dataService.empresaAtual ?? empresaAtual;

            if (empresaLocal != null) {
              final motivo = empresaLocal.verificarMotivoBloqueio(
                ultimaValidacaoOnline: dataService.ultimaValidacaoOnline,
                ultimaDataExecucao: dataService.ultimaDataExecucao,
              );
              final licencaEmergencialDeContingencia =
                  motivo == MotivoBloqueioEmpresa.excessoDiasOffline &&
                  dataService.licencaEmergenciaValidaParaEmpresa(
                    empresaLocal.id,
                  );
              if (motivo != MotivoBloqueioEmpresa.nenhum &&
                  !dataService.liberacaoProvisoriaAtiva &&
                  !licencaEmergencialDeContingencia) {
                return BloqueioMensalidadePage(
                  configs: empresaLocal.configuracoes ?? {},
                  motivoBloqueio: motivo,
                );
              }
            }

            // SE ESTÁ TUDO OK, MOSTRA A HOME PAGE
            return HomePage(initialPage: rotaInicial);
          } catch (e, stackTrace) {
            print('>>> ⚠ Erro no AuthWrapper: $e');
            print('>>> StackTrace: $stackTrace');
            // Em caso de erro, mostra login
            return const LoginPage();
          }
        },
      );
    } catch (e, stackTrace) {
      print('>>> ⚠ ERRO CRÍTICO no AuthWrapper: $e');
      print('>>> StackTrace: $stackTrace');
      // Sempre mostra algo, nunca tela branca
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 64),
              const SizedBox(height: 24),
              const Text(
                'Erro ao carregar',
                style: TextStyle(color: Colors.white, fontSize: 18),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () {
                  // Tentar novamente - recarregar a página
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(
                      builder: (context) => const AuthWrapper(),
                    ),
                  );
                },
                child: const Text(
                  'Tentar Novamente',
                  style: TextStyle(color: Colors.blue),
                ),
              ),
            ],
          ),
        ),
      );
    }
  }
}
