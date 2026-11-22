# Sistema Êxodo no Android (APK)

Este documento registra como o APK foi habilitado e o que foi melhorado
para o uso no celular.

## 1. Ferramentas instaladas nesta máquina

Para compilar APK eram necessários o JDK e o Android SDK (antes **não havia**
nenhum dos dois). Foram instalados:

| Ferramenta | Versão | Caminho |
|-----------|--------|---------|
| Microsoft OpenJDK | 17.0.20 | `C:\Program Files\Microsoft\jdk-17.0.20.101-hotspot` |
| Android SDK (command-line tools) | latest | `C:\Android\Sdk` |
| platform-tools | 36 | `C:\Android\Sdk\platform-tools` |
| platforms;android-36 | 36 | `C:\Android\Sdk\platforms\android-36` |
| build-tools | 36.0.0 | `C:\Android\Sdk\build-tools\36.0.0` |

O Flutter foi apontado para o SDK com:

```
flutter config --android-sdk "C:\Android\Sdk"
```

`flutter doctor` agora mostra **Android toolchain ✔**.

## 2. Como gerar o APK

Use o script na raiz do projeto:

```
GERAR_APK.bat            -> APK de TESTE (debug)
GERAR_APK.bat release    -> APK de PRODUÇÃO (release)
```

O APK sai em `build\app\outputs\flutter-apk\`.
- Debug: `app-debug.apk`
- Release: `app-release.apk`

> **Release x Debug:** o `release` hoje assina com a chave de *debug*
> (padrão do projeto). Para publicar em loja é preciso criar um keystore e
> configurar a assinatura em `android/app/build.gradle.kts`.

Instalar no celular: copie o `.apk` e toque nele (habilite
"Instalar apps de fontes desconhecidas"). Ou via cabo:
`adb install -r build\app\outputs\flutter-apk\app-debug.apk`.

## 3. Melhorias de botões e experiência no celular

Todas as mudanças são **só para telas estreitas** (largura < 700 px).
No desktop/Web nada muda.

Arquivos alterados:
- `lib/pages/home_page.dart`
- `lib/pages/login_page.dart`

O que foi feito:

1. **Botões do menu maiores e mais fáceis de tocar** — ícones, fonte e
   espaçamento maiores no celular, com altura mínima de 100 px por botão.
2. **Feedback visual ao toque** — o botão encolhe levemente ao ser
   pressionado, além do efeito de "onda" (ripple) na cor do botão.
3. **Barra de navegação inferior** — atalhos fixos no rodapé:
   *Início · Painel · PDV · Clientes · Mais*. O "Mais" abre uma folha com
   **todos** os itens do menu (respeitando as permissões/travas de tela).
4. **Topo (AppBar) organizado** — no celular os ícones que não cabiam foram
   recolhidos num menu "⋮" (Início, Painel, caixa, agenda, contas a pagar,
   configurações da empresa, permissões, personalizar layout, tema, sair).
   Os botões de teste do suporte (Limpar Local, Puxar Nuvem, etc.) ficam
   **apenas no desktop**, para não poluir a tela do cliente.
5. **Layout responsivo** — menos margem lateral no celular e ajuste do
   card de login para telas pequenas.

## 4. Banco de dados no celular (IMPLEMENTADO)

O sistema usa **PostgreSQL**. O celular não tem esse banco, então ele se
conecta ao **PostgreSQL do PC que roda o sistema**, pela rede Wi‑Fi da loja.

Para isso foi implementado:

1. **`.env` empacotado no app** — o arquivo `assets/app.env` vai dentro do
   APK e é lido automaticamente no celular (`EnvConfig.carregarDoAsset()`,
   chamado no `main()`). No PC nada muda: o `.env` do disco continua tendo
   prioridade.
2. **Apontado para este PC** — `assets/app.env` vem com
   `DB_HOST=DESKTOP-86UT1R1` (nome do PC) e `DB_HOST_FALLBACK=192.168.0.107`
   (IP): o Android não resolve nome sem DNS local, então quando o nome falha o
   app cai no IP sozinho. Confirmado que o PostgreSQL deste PC escuta em
   `0.0.0.0:5432` e que o firewall tem a regra *Exodo PostgreSQL (LAN)*
   liberando a porta 5432.
3. **Permissão de internet** — já existe no `AndroidManifest.xml`.

### O que o celular precisa

- Estar na **mesma rede Wi‑Fi** do PC.
- O PC ligado, com o sistema/PostgreSQL rodando.

### Se o IP do PC mudar

O IP `192.168.0.107` pode mudar se o PC pegar outro endereço no roteador.
Se acontecer:

1. Descubra o novo IP do PC (no PC: `ipconfig`), **ou** reserve um IP fixo
   para o PC no roteador (recomendado).
2. Edite `assets/app.env` e troque `DB_HOST_FALLBACK=...` (o IP) — o
   `DB_HOST` continua sendo o nome do PC.
3. Gere o APK de novo: `GERAR_APK.bat`.

Arquivos envolvidos:
- `assets/app.env` — configuração usada pelo celular
- `lib/services/env_config.dart` — passa a ler o `.env` empacotado
- `lib/main.dart` — carrega o `.env` empacotado no boot
- `pubspec.yaml` — declara `assets/app.env` como asset

### Acesso pela internet (sem Wi‑Fi da loja) — CONFIGURADO com Tailscale Funnel

Quando o celular está fora da loja, as duas primeiras tentativas falham e o app
cai no terceiro destino, o bloco `DB_CLOUD_*` do `assets/app.env`:

```
DB_CLOUD_HOST=exodosystems.tail9b4943.ts.net   endereço público fixo
DB_CLOUD_PORT=10000                                porta do Funnel
DB_CLOUD_NAME=postgres
DB_CLOUD_USER=postgres.your-tenant-id
DB_CLOUD_SSL=true                                  TLS direto (sem SSLRequest)
```

Caminho dos dados: celular → internet → edge do Tailscale (TLS 1.3,
certificado Let's Encrypt) → este PC → `127.0.0.1:5434` → Postgres da VM
`Ubuntu-Supabase` (Supabase local). O driver `postgres` de `third_party/` ganhou
a opção `directTls` justamente porque o Funnel espera o TLS como primeiros bytes;
com `directTls=false` a conexão é derrubada no handshake.

O que precisa estar ligado para o celular fora da loja conseguir:

1. este PC ligado (o Funnel morre junto com ele);
2. a VM `Ubuntu-Supabase` rodando — já sobe sozinha no logon (entrada
   `SupabaseVM` no Registro, executável oculto);
3. Tailscale conectado — o serviço está em *Automático* e o Funnel é
   reaplicado por [INICIAR_FUNNEL_SUPABASE.bat](INICIAR_FUNNEL_SUPABASE.bat),
   que está como atalho na pasta Inicializar (`shell:startup`). Log dele em
   `logs\funnel_supabase.log`.

Teste rápido (usa as mesmas credenciais do APK):

```
dart run tool/teste_funnel.dart
```

Resultado na última verificação: `OK em ~200 ms | produtos=7233 clientes=13`
(mesmos números do `exodo_db` local), e o certificado apresentado na porta
10000 é válido para `exodosystems.tail9b4943.ts.net`.

> ⚠️ **Segurança:** a senha do banco vai embutida no APK e a porta 10000 fica
> aberta para a internet. Não distribua o APK fora das lojas. A senha atual é o
> valor padrão de instalação do Supabase local — trocá-la em
> `F:\supabase-local\supabase\docker\.env` (e refazer o APK) é a pendência
> registrada; quem pegar o endereço público hoje consegue conectar.

## 5. Coisas que não funcionam no celular (por natureza)

Recursos específicos de Windows não têm equivalente no Android:
emissão NFC-e via Bridge local, Sincronizador de bandeja, impressão
térmica local, balança serial, etc. O foco do app no celular fica no
"miolo" de gestão: vendas/PDV, clientes, produtos, pedidos, caixa, painel.

## 6. Melhorias de toque e de tela (versão 1.0.82)

Continuação do item 3, agora com as melhorias aplicadas de forma global
(só valem no celular; no PC o comportamento é o mesmo de antes).

Arquivo novo: `lib/utils/mobile_ux.dart` — reúne o que era repetido:

| Item | O que faz |
|------|-----------|
| `kLarguraCelular` / `ehCelular()` | um único limite de 700 px para todas as telas |
| `ExodoScrollBehavior` | rolagem com física elástica e sem o brilho de overscroll do Android |
| `toqueHaptico()` | vibração curta ao tocar em botão de menu e atalho da barra inferior |
| `ToqueForaFechaTeclado` | tocar na área vazia fecha o teclado |

O que mudou na prática:

1. **Tela cheia (edge-to-edge)** — `main.dart` desenha atrás das barras de
   status e de navegação do Android, com as duas transparentes. O conteúdo
   ganha a altura toda e cada página usa `SafeArea` para o recorte.
2. **Barra inferior acima da barra de gestos** — a navegação da Home ganhou
   `SafeArea`, então os atalhos não ficam mais embaixo do risquinho do Android.
3. **Botões da Home em bloco** — no celular cada botão mostra o ícone grande
   em cima e o nome embaixo (bloco quadrado), em vez da linha apertada do
   desktop. Espaçamento menor entre eles e altura mínima de 124 px.
4. **Títulos que não estouram** — o nome do menu ocupa até 2 linhas com
   reticências; subtítulos ficam em 1 linha. Sem listras de overflow.
5. **Vibração de confirmação** — ao abrir um módulo pelo menu e ao trocar de
   atalho na barra inferior.
6. **Teclado** — o login fecha o teclado ao arrastar a tela e ao tocar em
   área vazia (fora de campos), e o botão ACESSAR já fecha antes de entrar.
   Vale para o sistema inteiro: tocar fora de um campo fecha o teclado.
7. **Login menor no celular** — logo e card de acesso ajustados para o botão
   de entrar caber na tela sem rolar, e ícones claros na barra de status
   (antes o relógio do celular sumia no fundo escuro).

Versão: `1.0.82+82` (`pubspec.yaml` e `AppUpdateService.currentAppVersion`).

### Build de release e memória da máquina

O build de release é o R8 (minificação) e é ele que consome memória. Nesta
máquina (16 GB, com PostgreSQL e Windows abertos) ficou assim em
`android/gradle.properties`:

| Configuração | Valor | Por quê |
|---|---|---|
| `org.gradle.jvmargs` | `-Xmx2048m` | com 1 GB o R8 estourava (`java_pidXXXX.hprof`); com 4 GB o Windows ficava sem memória de commit e matava o daemon |
| `org.gradle.workers.max` | `2` | menos compilação em paralelo, menos pico de RAM |
| `android.enableR8.fullMode` | `false` | reduz o pico e o tempo do R8 |

Se a máquina estiver mais livre, dá para subir o `-Xmx` de novo. O APK de
release leva ~9 minutos nesta configuração (com cache quente, ~5 min).

## 7. Correção do "não abre / fica no splash" (versão 1.0.83)

O APK 1.0.82 abria e ficava parado no splash branco do Android, sem
carregar nada. Causa provável: o `main()` chamava
`SystemChrome.setEnabledSystemUIMode()` **antes** do `runApp()`. Toda a
abertura roda dentro de `runZonedGuarded`, então uma exceção (ou demora)
nova ali morria só no log e o `runApp` nunca acontecia — resultado: splash
eterno, nenhuma mensagem na tela.

O que mudou:

1. **`SystemChrome` saiu de antes do `runApp`** — o estilo das barras agora é
   aplicado no primeiro quadro (`addPostFrameCallback`), dentro de
   `try/catch`. No Android 15+ o edge-to-edge já é o padrão, então não é
   preciso mexer no `SystemUiMode` para ficar em tela cheia.
2. **Tela de progresso imediata** (`lib/widgets/boot_screens.dart`): o app
   desenha na hora um “Preparando o sistema…” com a etapa atual. Se algo
   demorar, dá para ver exatamente onde parou.
3. **Tela de falha visível**: qualquer erro na abertura agora mostra
   “O sistema não conseguiu abrir” com a mensagem e a pilha em texto
   selecionável (print/cola no suporte). Antes o app ficava mudo.

Se o app parar de novo, o nome da etapa na tela (ou o texto da tela de erro)
diz onde está o problema — não precisa mais adivinhar pelo splash.

### 7.1 A causa real: Impeller no celular (versão 1.0.84)

O APK 1.0.83 abria **no emulador (MuMu)** e **travava no celular**. Isso é o
sintoma clássico do **Impeller**, o renderizador Vulkan que o Flutter usa por
padrão no Android a partir da API 29: no emulador o driver é do PC e funciona;
em vários aparelhos reais (Samsung A51, Oppo Reno, Huawei nova, Redmi Note) o
driver Vulkan trava no primeiro quadro e o app fica parado no splash.

Correção aplicada em `android/app/src/main/AndroidManifest.xml`
(dentro de `<application>`):

```xml
<meta-data
    android:name="io.flutter.embedding.android.EnableImpeller"
    android:value="false" />
```

Com isso o app volta a desenhar pelo Skia/OpenGL, que funciona em praticamente
qualquer aparelho. O custo é desempenho gráfico um pouco menor; quando o Flutter
corrigir o problema nos drivers afetados, basta remover essas linhas para
voltar ao Impeller.

## 8. Abertura rápida no celular (versão 1.0.85)

Com o app já abrindo, a queixa passou a ser a **demora para carregar** na
abertura (tela "carregando dados"). Causa: o celular não tem PostgreSQL
próprio, então ele tenta o banco do PC na rede, depois o IP reserva e depois
a nuvem — 4 s + 4 s + 15 s. Pior: quando tudo falhava, o código **repetia a
leitura inteira** (o retry foi feito para o PC, onde o serviço PostgreSQL pode
estar subindo), somando outra rodada de timeouts antes de baixar a nuvem.

Ajustes em `lib/services/data_service.dart`:

1. **Sem leitura repetida no celular** (`_semBancoLocalProprio`): se o banco do
   PC não respondeu agora, repetir 400 ms depois só faz o cliente esperar.
   No computador o retry continua igual.
2. **Limite de espera da abertura**: 8 s no celular (era 15 s). Se a nuvem ainda
   não terminou, o sistema abre e **continua carregando em segundo plano**, com
   os contadores da tela subindo (Produtos, Clientes, Pedidos...).

O que ainda dá para acelerar de verdade (depende da rede):

- se o celular está **fora da loja**, o caminho é a nuvem (Funnel/Neon) e o
  tempo depende do 4G do aparelho;
- se está **na loja**, o ideal é que o Wi-Fi alcance o PostgreSQL do PC — nesse
  caso a abertura é quase imediata (a tela libera assim que o banco responde).

Se mesmo assim algum aparelho ficar com tela preta depois do splash, o próximo
passo é adicionar também:

```xml
<meta-data
    android:name="io.flutter.embedding.android.DisableSurfaceControl"
    android:value="true" />
```

## 9. Não loga / travava na abertura (versão 1.0.86)

O APK 1.0.85 abriu mas o APK gerado depois ficou parado em
"Carregando módulos do sistema..." e o login nunca chegava. Causa: o boot
chamava `DataService().carregarLiberacaoProvisoria()` — que faz 5–6 leituras/
gravacoes de configuração no PostgreSQL. Cada leitura, no celular sem banco
próprio, tentava **nome do PC (4 s) → IP reserva (4 s) → nuvem (15 s)**, e,
quando todos falhavam, o retry de conexão repedia o ciclo inteiro em cada
operacao. O boot levava minutos; o login, que grava `usuario_atual` antes de
entrar, jamais terminava.

Correções aplicadas:

1. **Timeout de 12 s em `main.dart`** em torno de `carregarLiberacaoProvisoria()` — se o banco não responde, o boot segue pelo espelho de emergência (comportamento offline já existente) e a leitura continua em segundo plano.
2. **Timeout de 5 s** nas inicializações de `NfceContingenciaService` e `NfceXmlLocalService`.
3. **Disjuntor em `DatabaseService.connection`**: quando a última tentativa completa falha no celular, as próximas leituras/gravacoes (nos próximos 10 s) falham na hora e caem no cache de emergência, em vez de repagarem 4 s + 4 s + 15 s cada. A janela expira e a próxima tentativa completa é feita normalmente.
4. **`LocalStorageService` com espelho local em mãos** (`_carregarConfigComFallback` / `_salvarConfigComFallback`): no celular, uma leitura/gravação de configuração aguarda no máximo 2 s pelo PostgreSQL; se não responder, devolve/grava o espelho local (chave `pendente`) e a tela não trava — login, por exemplo, grava `usuario_atual` e entra mesmo com o banco da loja fora.
   No PC nada mudou: o PostgreSQL local responde em milissegundos.

O que ficou igual (intencional):
- No PC a abertura continua esperando o banco local responder (o serviço pode estar subindo); o retry existe exatamente para isso.
- O login local continua exigindo usuário/senha cadastrados no banco local; sem eles o app avisa "Usuário ou senha inválidos" em vez de ficar parado.

Versão: `1.0.86+86` (`pubspec.yaml` e `AppUpdateService.currentAppVersion`).
Instalador: `Instalador_Exodo_Completo.iss` agora com `MyAppVersion "1.0.86"`.
