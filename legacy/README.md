# legacy/

Código arquivado em 24/10/2026 porque **não compila mais** e **não é importado por
ninguém**. Nada aqui participa do build, do `flutter analyze` nem do `flutter test`
(a pasta está excluída em `analysis_options.yaml`).

Nada foi apagado — tudo está preservado aqui e continua no histórico do git.
Para restaurar um arquivo, basta movê-lo de volta para o caminho original.

## `legacy/lib/` — 7 arquivos órfãos

Verificado: nenhum arquivo em `lib/` os importa.

| Arquivo | Por que saiu |
|---|---|
| `home_page.dart` | Versão antiga. A tela em uso é `lib/pages/home_page.dart`. Declarava um `class ExodoLogo` falso que sobrescrevia o widget real de `lib/widgets/exodo_logo.dart`. |
| `lancamento_servico_form.dart` | Substituído por `lib/pages/lancar_servico_page.dart`. Importa `package:sistema_exodo_novo/produto.dart` e `servico.dart`, que não existem mais (hoje são `lib/models/`). |
| `pages/adicionar_ordem_servico_page.dart` | Importa `../produto.dart` (inexistente). |
| `pages/notas_entrada_page.dart` | Usa getters que não existem mais em `ItemNotaEntrada`. |
| `pages/gerenciar_grupos_page.dart` | Passa `int` onde `GrupoService.atualizarEstoquePorGrupo` espera `double`. |
| `services/image_upload_service.dart` | Chama `uploadFile(onProgress:)`, parâmetro que não existe. Dependia do Storage do Supabase, removido. |
| `services/teste_homologacao_service.dart` | Usa a API antiga de emissão de NFC-e (`produtos`/`quantidades`/`pagamentos`). |

## `legacy/test/` — 21 testes do Supabase

Importam `package:supabase_flutter/supabase_flutter.dart` e
`package:sistema_exodo_novo/supabase_config.dart`, **ambos removidos** do
`pubspec.yaml` na migração para Neon/PostgREST. Não compilam e derrubavam o
`flutter analyze` com 130 erros.

Se o Supabase voltar a ser suportado, estes testes precisam ser reescritos para a
API atual de `lib/services/supabase_service.dart` (que hoje usa `http` puro, não
o SDK do Supabase) — não basta mover de volta.

## `legacy/test/widget_test.dart`

Template padrão do `flutter create` ("Counter increments smoke test"): procura os
textos `0` e `1` e o ícone `+` de um contador que este app nunca teve. Falhava
sempre (`Found 0 widgets with text "0"`). O app é o Sistema Exodo, não um
contador — não havia o que consertar.

## `legacy/diagnostics/load_cache_test.dart`

Não é teste: tem **zero `expect()`**. É um script de diagnóstico que conecta no
Postgres local e fica em loop tentando carregar as listas — por isso o
`flutter test` nunca terminava. Use como script manual se precisar.

## `legacy/VERIFICAR_CERTIFICADO_SUPABASE.dart`

Script avulso na raiz do projeto, usava `Supabase` sem import.
