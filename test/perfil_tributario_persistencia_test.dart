// IMPOSTOS — o que o usuário salva precisa continuar salvo.
//
// `salvarPerfilTributario` grava a lista na configuração da empresa e, logo em
// seguida, `atualizarDadosEmpresa` RECARREGA os perfis (`_carregarPerfis...`).
// Se o recarregamento reimplantar o código fiscal do sistema, a edição do
// usuário é desfeita dentro do próprio save — o sintoma "mudo o imposto, salvo
// e volta" (e a lista revertida ainda era regravada na configuração).
//
// Rodar: flutter test test/perfil_tributario_persistencia_test.dart

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistema_exodo_novo/models/empresa.dart';
import 'package:sistema_exodo_novo/models/perfil_tributario.dart';
import 'package:sistema_exodo_novo/services/data_service.dart';
import 'package:sistema_exodo_novo/services/neon_config.dart';

const empresaTeste = 'EMPRESA-PERFIL-PERSISTENCIA-TESTE';

PerfilTributario substituicaoSimples() => PerfilTributario(
  id: 'padrao_substituicao_simples',
  nome: 'Substituição Tributária (Simples Nacional)',
  cfop: '5405',
  csosn: '500',
);

PerfilTributario tributadoSimples() => PerfilTributario(
  id: 'padrao_tributado_simples',
  nome: 'Tributado (Simples Nacional)',
  cfop: '5102',
  csosn: '102',
  isDefault: true,
);

Empresa empresaComPerfis(List<PerfilTributario> perfis) => Empresa(
  id: empresaTeste,
  razaoSocial: 'Empresa Teste Persistencia',
  slug: 'empresa-teste-persistencia',
  crt: 1,
  createdAt: DateTime(2026, 11, 5),
  updatedAt: DateTime(2026, 11, 5),
  configuracoes: {
    'nuvem_ativa': false,
    'crt': 1,
    'perfis_tributarios': perfis.map((p) => p.toMap()).toList(),
  },
);

PerfilTributario? porId(Iterable<PerfilTributario> perfis, String id) {
  for (final p in perfis) {
    if (p.id == id) return p;
  }
  return null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});

    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final canal in const [
      'dev.fluttercommunity.plus/connectivity',
      'xyz.luan/audioplayers.global',
      'xyz.luan/audioplayers',
      'plugins.flutter.io/path_provider',
    ]) {
      messenger.setMockMethodCallHandler(
        MethodChannel(canal),
        (call) async => null,
      );
    }
    for (final canal in const [
      'dev.fluttercommunity.plus/connectivity_status',
      'xyz.luan/audioplayers.global/events',
    ]) {
      messenger.setMockStreamHandler(
        EventChannel(canal),
        MockStreamHandler.inline(onListen: (args, sink) {}),
      );
    }

    // Nuvem desligada: este teste olha só o estado local (o mesmo mapa que vai
    // para a configuração da empresa no PostgreSQL e para o Supabase).
    NeonConfig.aplicarOverrides({
      'NEON_DATA_API_URL': '',
      'NEON_DATA_API_BASE_URL': '',
      'NEON_DATABASE_URL': '',
      'DATABASE_URL': '',
      'NEON_DATABASE_URL_UNPOOLED': '',
      'DATABASE_URL_UNPOOLED': '',
      'NEON_AUTH_BASE_URL': '',
      'NEON_AUTH_JWKS_URL': '',
      'NEON_FUNCTION_HELLO_BASE_URL': '',
      'NEON_FUNCTIONS_URL': '',
      'NEON_AWS_ENDPOINT_URL_S3': '',
      'AWS_ENDPOINT_URL_S3': '',
    });
  });

  test('CSOSN do perfil padrão editado continua o do usuário', () async {
    final ds = DataService();
    addTearDown(ds.dispose);
    ds.setEmpresaIdParaTeste(empresaTeste);
    ds.setEmpresaAtual(empresaComPerfis([tributadoSimples()]));

    final original = porId(ds.perfisTributarios, 'padrao_tributado_simples');
    expect(original, isNotNull);

    await ds.salvarPerfilTributario(original!.copyWith(csosn: '900'));

    final salvo = porId(ds.perfisTributarios, 'padrao_tributado_simples');
    expect(
      salvo?.csosn,
      '900',
      reason: 'o carregamento não pode reimplantar o CSOSN do sistema',
    );

    final naEmpresa =
        ds.empresaAtual!.configuracoes!['perfis_tributarios'] as List;
    final daEmpresa = PerfilTributario.fromMap(
      Map<String, dynamic>.from(naEmpresa.first as Map),
    );
    expect(daEmpresa.csosn, '900');
  });

  test('CFOP do perfil padrão editado continua o do usuário', () async {
    final ds = DataService();
    addTearDown(ds.dispose);
    ds.setEmpresaIdParaTeste(empresaTeste);
    ds.setEmpresaAtual(empresaComPerfis([substituicaoSimples()]));

    final original = porId(ds.perfisTributarios, 'padrao_substituicao_simples');
    await ds.salvarPerfilTributario(original!.copyWith(cfop: '5403'));

    expect(
      porId(ds.perfisTributarios, 'padrao_substituicao_simples')?.cfop,
      '5403',
    );
  });

  test('alíquotas de IBS/CBS do usuário não voltam para o padrão', () async {
    final ds = DataService();
    addTearDown(ds.dispose);
    ds.setEmpresaIdParaTeste(empresaTeste);
    ds.setEmpresaAtual(empresaComPerfis([substituicaoSimples()]));

    final original = porId(ds.perfisTributarios, 'padrao_substituicao_simples');
    await ds.salvarPerfilTributario(
      original!.copyWith(aliquotaIbs: 0.05, aliquotaCbs: 0.25),
    );

    final salvo = porId(ds.perfisTributarios, 'padrao_substituicao_simples');
    expect(salvo?.aliquotaIbs, 0.05);
    expect(salvo?.aliquotaCbs, 0.25);
  });

  test('perfil COM perfil padrão vazio ainda é preenchido pelo sistema', () {
    final semCodigo = PerfilTributario(
      id: 'padrao_nao_tributado_simples',
      nome: 'Não Tributado (Simples Nacional)',
      cfop: '',
    );
    final ds = DataService();
    addTearDown(ds.dispose);
    ds.setEmpresaIdParaTeste(empresaTeste);
    ds.setEmpresaAtual(empresaComPerfis([semCodigo]));

    final carregado = porId(
      ds.perfisTributarios,
      'padrao_nao_tributado_simples',
    );
    expect(carregado?.cfop, '5102');
    expect(carregado?.csosn, '400');
  });
}
