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
DB_CLOUD_HOST=desktop-86ut1r1.tail9b4943.ts.net   endereço público fixo
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
10000 é válido para `desktop-86ut1r1.tail9b4943.ts.net`.

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
