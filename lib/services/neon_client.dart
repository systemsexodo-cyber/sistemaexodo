// Dart puro (sem Flutter) para poder ser exercitado por `dart run`.
// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:postgrest/postgrest.dart';

import 'neon_config.dart';
import 'neon_storage.dart';

/// Cliente da nuvem do Neon: substitui o `SupabaseClient` do SDK do Supabase.
///
/// O Neon não tem PostgREST próprio como serviço gerenciado, mas oferece a
/// **Data API** (PostgREST) por branch. Como ela fala o mesmo protocolo, o
/// cliente Dart `postgrest` (o mesmo que o `supabase_flutter` usava por baixo)
/// continua servindo — só muda a origem e o token.
///
/// O que este cliente entrega, na mesma forma que o app já usava:
///   * `from(tabela)` / `rpc(funcao)`  → Data API (PostgREST) do Neon;
///   * `storage`         → Object Storage do Neon (S3 assinado com SigV4);
///   * `auth`            → token do Neon Auth (a Data API exige um JWT).
///
/// Sobre a AUTENTICAÇÃO: a Data API do Neon só aceita requisições com um JWT
/// emitido pelo Neon Auth. O app tem login próprio (tabela `usuarios`, com
/// fallback offline), então usamos o token **anônimo** do Neon Auth — que dá o
/// papel `anonymous` do Postgres, com GRANT nas tabelas de `public`. É o mesmo
/// modelo que o app já tinha no Supabase: uma credencial de serviço que
/// atravessa o RLS (lá era a `service_role`).
class NeonClient {
  NeonClient._();

  static final NeonClient instance = NeonClient._();

  /// Cliente PostgREST apontando para a Data API do Neon.
  ///
  /// Criado uma única vez: `PostgrestClient.headers` é mutável, então o token
  /// é trocado no lugar (o `YAJsonIsolate` interno também é reaproveitado).
  late final PostgrestClient _postgrest = PostgrestClient(
    NeonConfig.dataApiUrl,
    headers: {
      // O gateway do Supabase (Kong) recusa sem `apikey` válido (401); o Neon
      // não usa essa chave, então só enviamos quando ela existe.
      if (NeonConfig.dataApiKeyDisponivel) 'apikey': NeonConfig.dataApiKey,
      'Authorization': 'Bearer ${NeonAuth.instance.tokenAtual}',
    },
  );

  NeonStorage get storage => NeonStorage.instance;

  NeonAuth get auth => NeonAuth.instance;

  /// Mesma assinatura do `SupabaseClient.from`.
  PostgrestQueryBuilder<void> from(String table) {
    _sincronizarToken();
    return _postgrest.from(table);
  }

  /// Mesma assinatura do `SupabaseClient.rpc`.
  PostgrestFilterBuilder<T> rpc<T>(
    String fn, {
    Map<String, dynamic>? params,
    bool get = false,
  }) {
    _sincronizarToken();
    return _postgrest.rpc<T>(fn, params: params, get: get);
  }

  /// Um cliente por schema (não usado hoje, mantido por completude).
  PostgrestClient schema(String schema) {
    _sincronizarToken();
    return _postgrest.schema(schema);
  }

  /// Requisição crua assinada (usada pela detecção de colunas/health check).
  Map<String, String> get headers => {
        // Com a chave estática (Supabase local) ela vai como `apikey`; sem ela,
        // mantém o valor antigo (o Neon ignora esse cabeçalho).
        'apikey': NeonConfig.dataApiKeyDisponivel
            ? NeonConfig.dataApiKey
            : NeonConfig.dataApiUrl,
        'Authorization': 'Bearer ${NeonAuth.instance.tokenAtual}',
        'Accept': 'application/json',
      };

  void _sincronizarToken() {
    final token = NeonAuth.instance.tokenAtual;
    if (token.isEmpty) {
      // Sem token ainda (boot): busca em segundo plano e a próxima chamada já
      // usa. Enquanto isso a requisição sai sem Authorization e o PostgREST
      // responde 401 — o app trata como nuvem indisponível.
      unawaited(NeonAuth.instance.garantirToken());
      return;
    }
    _postgrest.headers['Authorization'] = 'Bearer $token';
  }

  /// Aquece o cliente: garante o token e inicia a renovação periódica.
  Future<void> inicializar() => NeonAuth.instance.iniciar();
}

/// Autenticação do Neon: emissão e renovação do token da Data API.
///
/// [tokenAtual] é síncrono de propósito (o cliente PostgREST precisa do valor
/// na hora de montar a requisição). A renovação acontece em segundo plano e
/// também sob demanda em [garantirToken].
class NeonAuth {
  NeonAuth._();

  static final NeonAuth instance = NeonAuth._();

  static const Duration _margemExpiracao = Duration(minutes: 2);

  /// Pausa quando a nuvem responde 402 (cota de dados do Neon estourada).
  /// Durante o bloqueio NENHUMA chamada de rede é feita: cada nova tentativa
  /// só gera log — e a resposta 402 também trafega, piorando o problema.
  static const Duration _bloqueioQuota = Duration(minutes: 15);

  /// Pausa para 401/403 (configuração do domínio/credencial). Menor que a de
  /// quota: pode ser transitório, mas insistir a cada 2s também não resolve.
  static const Duration _bloqueioAuth = Duration(minutes: 5);

  String _token = '';
  DateTime? _expiraEm;
  DateTime? _bloqueadoAte;
  Timer? _renovacao;
  Future<void>? _emAndamento;

  /// Token anônimo atual ('' quando ainda não obtido).
  String get tokenAtual => _token;

  bool get disponivel => _token.isNotEmpty;

  /// Inicia a renovação periódica do token (chamado no boot do app).
  Future<void> iniciar() async {
    await garantirToken();
    _renovacao ??= Timer.periodic(
      const Duration(minutes: 5),
      // catchError: uma falha de cota/configuração NÃO pode virar erro não
      // tratado a cada 5 min — vira log curto e o bloqueio cuida do resto.
      (_) => unawaited(
        garantirToken().catchError(
          (e) => print('>>> [Neon Auth] ⚠️ Renovação adiada: $e'),
        ),
      ),
    );
  }

  /// Garante que exista um token válido. Em caso de falha de rede mantém o
  /// token antigo (se ainda não venceu) e propaga o erro.
  ///
  /// Se a nuvem está bloqueada (quota 402 / auth 401-403), lança o erro na
  /// hora SEM bater na rede — o bloqueio espelha o `BLOQUEIO_*` do
  /// sincronizador Python, que já pausava 30 min nesses status.
  Future<void> garantirToken() async {
    // Modo chave estática (Supabase local atrás do Funnel): a chave do projeto
    // É o token — nenhuma chamada de rede, nenhuma ida ao Neon Auth. Aplica a
    // cada chamada para acompanhar troca de chave sem reiniciar o app.
    if (NeonConfig.dataApiKeyDisponivel) {
      final chave = NeonConfig.dataApiKey;
      if (_token != chave || _bloqueadoAte != null) {
        _token = chave;
        _expiraEm = _expiracaoDoJwt(chave) ??
            DateTime.now().add(const Duration(days: 365));
        _bloqueadoAte = null;
        print(
          '>>> [Neon Auth] 🔑 Chave estática da Data API '
          '(Supabase local) — sem ida ao Neon Auth.',
        );
      }
      return;
    }
    if (_token.isNotEmpty &&
        _expiraEm != null &&
        _expiraEm!.isAfter(DateTime.now().add(_margemExpiracao))) {
      return Future.value();
    }
    final bloqueadoAte = _bloqueadoAte;
    if (bloqueadoAte != null && bloqueadoAte.isAfter(DateTime.now())) {
      final faltam = bloqueadoAte.difference(DateTime.now()).inMinutes + 1;
      throw StateError(
        'Neon Auth: nuvem bloqueada (HTTP 402/quota ou 401/403) — nova '
        'tentativa automática em ~$faltam min. Sem chamada de rede durante '
        'o bloqueio.',
      );
    }
    final emAndamento = _emAndamento;
    if (emAndamento != null) return emAndamento;
    final futuro = _buscarToken();
    _emAndamento = futuro;
    return futuro.whenComplete(() => _emAndamento = null);
  }

  Future<void> _buscarToken() async {
    final base = NeonConfig.authBaseUrl;
    if (base.isEmpty) {
      throw StateError(
        'Neon Auth: NEON_AUTH_BASE_URL ausente em ${NeonConfig.nomeArquivo}.',
      );
    }
    final resp = await http
        .get(Uri.parse('${base.replaceAll(RegExp(r'/+$'), '')}/token/anonymous'))
        .timeout(const Duration(seconds: 20));
    if (resp.statusCode != 200) {
      // 402 (quota de egress estourada), 401/403 (domínio/credencial): erro
      // persistente — insister a cada 2s só enche o log e gasta cota. Ativa o
      // bloqueio e propaga a mensagem (o `isErroInfraestrutura` do app
      // reconhece "http 402"/"quota" e também abre o disjuntor lá).
      final duracao = (resp.statusCode == 402)
          ? _bloqueioQuota
          : _bloqueioAuth;
      _bloqueadoAte = DateTime.now().add(duracao);
      final corpo = resp.body.length > 300
          ? '${resp.body.substring(0, 300)}…'
          : resp.body;
      throw Exception(
        'Neon Auth: falha ao obter token anônimo (HTTP ${resp.statusCode}) '
        '— nova tentativa em ${duracao.inMinutes} min. Corpo: $corpo',
      );
    }
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    final token = (json['token'] ?? '').toString();
    if (token.isEmpty) {
      throw Exception('Neon Auth: resposta sem token: ${resp.body}');
    }
    _token = token;
    _bloqueadoAte = null;
    _expiraEm = _expiracaoDoJwt(token) ?? DateTime.now().add(const Duration(minutes: 50));
    print(
      '>>> [Neon Auth] 🔐 Token renovado (expira em ${_expiraEm!.toIso8601String()}).',
    );
  }

  /// Lê a claim `exp` do JWT (sem validar assinatura: a validação é do
  /// servidor; aqui só serve para renovar antes de vencer).
  static DateTime? _expiracaoDoJwt(String token) {
    try {
      final partes = token.split('.');
      if (partes.length != 3) return null;
      var payload = partes[1].replaceAll('-', '+').replaceAll('_', '/');
      payload = payload.padRight((payload.length + 3) & ~3, '=');
      final json = jsonDecode(utf8.decode(base64Decode(payload)));
      if (json is Map && json['exp'] is num) {
        return DateTime.fromMillisecondsSinceEpoch(
          (json['exp'] as num).toInt() * 1000,
          isUtc: true,
        );
      }
    } catch (_) {}
    return null;
  }

  /// Encerra a renovação periódica (encerramento do app/testes).
  void parar() {
    _renovacao?.cancel();
    _renovacao = null;
  }

  // --------------------------------------------------------------------------
  // Superfície equivalente a `client.auth` do SDK antigo.
  //
  // O app tem identidade PRÓPRIA (tabela `usuarios`, com senha em texto e
  // validação offline). Não há usuário de nuvem, então `currentUser` é sempre
  // nulo e as operações de perfil/senha do provedor antigo viram no-op.
  // --------------------------------------------------------------------------

  /// Sempre nulo: a credencial da nuvem é o token anônimo, não um usuário.
  AuthUser? get currentUser => null;

  /// Sem sessão de usuário para encerrar — o token da Data API continua
  /// valendo (senão o app perderia o acesso à nuvem).
  Future<void> signOut() async {
    print(
      '>>> [Neon Auth] signOut ignorado: a credencial é o token anônimo da '
      'Data API e continua em uso.',
    );
  }

  /// Compatibilidade: no provedor antigo isto atualizava e-mail/senha/metadados
  /// do usuário de nuvem. Aqui não há usuário de nuvem.
  Future<void> updateUser(Object attributes) async {
    print(
      '>>> [Neon Auth] updateUser ignorado (identidade do app vive na tabela '
      '"usuarios").',
    );
  }

  /// Compatibilidade: não há sessão de nuvem para renovar; o token é renovado
  /// pelo timer de [iniciar].
  Future<void> refreshSession() async {
    await garantirToken();
  }

  /// Compatibilidade com o antigo cadastro de conta no provedor.
  ///
  /// Não cadastra: o Neon Auth exige domínios confiáveis configurados
  /// (`neon.ts`) e a senha do app vive em `usuarios`. Registramos para ficar
  /// explícito, em vez de disparar uma chamada que seria recusada.
  Future<void> signUp({required String email, required String password}) async {
    print(
      '>>> [Neon Auth] signUp ignorado para "$email": a identidade do app é '
      'local (tabela "usuarios"). Veja o README de migração.',
    );
  }
}

/// Usuário da nuvem (equivalente ao `User` do SDK antigo — só o `id` é usado).
class AuthUser {
  const AuthUser({required this.id, this.email = ''});

  final String id;
  final String email;
}
