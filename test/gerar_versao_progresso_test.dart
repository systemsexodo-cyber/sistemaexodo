// Testes da barra de progresso do assistente "Gerar versão".
//
// O `flutter build windows --release` não publica percentual nenhum, então a
// barra é montada com dois sinais: os marcos que o Flutter/MSBuild imprimem
// (que trocam a etapa) e o tempo decorrido na etapa (que faz a barra andar
// dentro da faixa dela). Estes testes travam o contrato dessa conta:
//  - a barra nunca anda para trás e nunca passa do teto da etapa;
//  - o tempo sozinho NUNCA chega a 100% (só o fim real do trabalho chega);
//  - o tempo sozinho sempre anda (mesmo estourando a estimativa);
//  - os marcos conhecidos caem na etapa certa.
//
// Rodar: flutter test test/gerar_versao_progresso_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_exodo_novo/services/app_update_service.dart';

void main() {
  group('percentual da barra', () {
    test('começa no início da faixa e nunca anda para trás', () {
      for (final etapa in EtapaGeracaoVersao.values) {
        expect(
          AppUpdateService.percentualDaEtapa(etapa, Duration.zero),
          etapa.inicio,
          reason: '${etapa.name} deve começar em ${etapa.inicio}',
        );

        var anterior = -1.0;
        for (final segundos in [0, 1, 5, 30, 60, 120, 300, 900, 3600]) {
          final atual = AppUpdateService.percentualDaEtapa(
            etapa,
            Duration(seconds: segundos),
          );
          expect(atual, greaterThanOrEqualTo(anterior),
              reason: '${etapa.name} recuou em ${segundos}s');
          anterior = atual;
        }
      }
    });

    test('o tempo sozinho nunca chega em 100% (nem no teto da etapa)', () {
      for (final etapa in EtapaGeracaoVersao.values) {
        final depoisDeMuito = AppUpdateService.percentualDaEtapa(
          etapa,
          const Duration(hours: 2),
        );
        expect(depoisDeMuito, lessThanOrEqualTo(etapa.teto));
        expect(depoisDeMuito, greaterThanOrEqualTo(etapa.inicio));
        if (etapa.fim < 1.0) {
          expect(depoisDeMuito, lessThan(etapa.fim),
              reason: '${etapa.name} não pode dar a etapa por concluída');
        }
      }
    });

    test('mas o tempo sozinho sempre anda, mesmo muito além do previsto', () {
      // O pecado que o usuário reclamava: rodinha parada. A barra precisa
      // mostrar progresso do começo ao fim, sem "chegar no fim" da faixa.
      for (final etapa in EtapaGeracaoVersao.values) {
        if (etapa.fim <= etapa.inicio) continue;
        final metadeDoTempo = AppUpdateService.percentualDaEtapa(
          etapa,
          etapa.estimativa * 0.5,
        );
        final noTempoPrevisto = AppUpdateService.percentualDaEtapa(
          etapa,
          etapa.estimativa,
        );
        final bemDepois = AppUpdateService.percentualDaEtapa(
          etapa,
          etapa.estimativa * 5,
        );
        expect(metadeDoTempo, greaterThan(etapa.inicio));
        expect(noTempoPrevisto, greaterThan(metadeDoTempo));
        expect(bemDepois, greaterThan(noTempoPrevisto));
      }
    });

    test('ficar mais tempo na etapa é sempre melhor que trocar de etapa cedo', () {
      // Ordem das etapas: cada uma começa onde a anterior termina (ou depois).
      for (var i = 1; i < EtapaGeracaoVersao.values.length; i++) {
        final anterior = EtapaGeracaoVersao.values[i - 1];
        final atual = EtapaGeracaoVersao.values[i];
        expect(atual.inicio, greaterThanOrEqualTo(anterior.fim),
            reason: 'buraco na barra entre ${anterior.name} e ${atual.name}');
      }
      expect(EtapaGeracaoVersao.values.first.inicio, 0.0);
      expect(EtapaGeracaoVersao.values.last.fim, 1.0);
    });

    test('a versão pronta é 100%', () {
      expect(
        AppUpdateService.percentualDaEtapa(
            EtapaGeracaoVersao.pronta, Duration.zero),
        1.0,
      );
      expect(
        AppUpdateService.percentualDaEtapa(
            EtapaGeracaoVersao.pronta, const Duration(hours: 1)),
        1.0,
      );
    });
  });

  group('marcos da saída do flutter build', () {
    test('reconhece o começo da compilação', () {
      for (final linha in [
        'Building Windows application...',
        'building windows application',
        'Running CMake...',
        'Running "cmake" ...',
      ]) {
        expect(
          AppUpdateService.etapaDaLinhaDeCompilacao(linha),
          EtapaGeracaoVersao.preparandoCompilacao,
          reason: 'não reconheci "$linha"',
        );
      }
    });

    test('reconhece o trabalho pesado (Dart AOT e MSBuild)', () {
      for (final linha in [
        'gen_snapshot ...',
        'Building AOT snapshot in release mode',
        'sistema_exodo_novo.vcxproj -> ...\\sistema_exodo_novo.exe',
        'Microsoft (R) Build Engine version 17.8.3',
        'Compiling C++ source...',
      ]) {
        expect(
          AppUpdateService.etapaDaLinhaDeCompilacao(linha),
          EtapaGeracaoVersao.compilando,
          reason: 'não reconheci "$linha"',
        );
      }
    });

    test('linha irrelevante não mexe na etapa', () {
      for (final linha in [
        '',
        '   ',
        'flutter: carregando produtos...',
        '✓ Built build\\windows\\x64\\runner\\Release\\sistema_exodo_novo.exe (12.3MB)',
      ]) {
        expect(AppUpdateService.etapaDaLinhaDeCompilacao(linha), isNull,
            reason: '"$linha" não deveria trocar a etapa');
      }
    });
  });

  group('avanço por tempo (quando o compilador fica mudo)', () {
    test('preparando vira compilando depois de um minuto', () {
      expect(
        AppUpdateService.proximaEtapaPorTempo(
            EtapaGeracaoVersao.preparandoCompilacao, const Duration(seconds: 59)),
        isNull,
      );
      expect(
        AppUpdateService.proximaEtapaPorTempo(
            EtapaGeracaoVersao.preparandoCompilacao, const Duration(seconds: 60)),
        EtapaGeracaoVersao.compilando,
      );
    });

    test('nunca inventa "montando o pacote" enquanto ainda compila', () {
      // Da compilação em diante quem manda é o fim real do passo: dizer que
      // está montando o pacote com a compilação em andamento seria mentira.
      for (final etapa in [
        EtapaGeracaoVersao.compilando,
        EtapaGeracaoVersao.empacotando,
        EtapaGeracaoVersao.gravandoCodigo,
      ]) {
        expect(
          AppUpdateService.proximaEtapaPorTempo(etapa, const Duration(hours: 1)),
          isNull,
          reason: '${etapa.name} não pode avançar sozinha por tempo',
        );
      }
    });
  });

  test('o rótulo de cada etapa é o que a tela mostra', () {
    expect(EtapaGeracaoVersao.totalDeTrabalho, 4);
    for (final etapa in EtapaGeracaoVersao.values) {
      expect(etapa.rotulo.trim(), isNotEmpty);
      expect(etapa.rotulo.endsWith('...') || etapa.fim >= 1.0, isTrue,
          reason: '${etapa.name} deveria indicar trabalho em andamento');
    }
    expect(EtapaGeracaoVersao.values.first.numero, 1);
    expect(EtapaGeracaoVersao.pronta.numero,
        greaterThan(EtapaGeracaoVersao.totalDeTrabalho),
        reason: '"pronta" não é uma etapa de trabalho');
  });
}
