# Portal do Contador (download de XMLs)

Área web onde o **contador/escritório de contabilidade** entra com **CNPJ + senha**
e baixa os XMLs das notas da empresa, **separados por tipo**:

| Aba | Origem | Tabela |
|-----|--------|--------|
| NFC-e Emitidas | NFC-e autorizadas pela empresa (modelo 65) | `nfces` |
| NF-e Emitidas | NF-e emitidas pela empresa (modelo 55) | `nfes` |
| NF-e Recebidas | NF-e de entrada (fornecedores) | `notas_entrada` |

Endereço do portal: **https://exodosystems-1541d.web.app/portal-contador**

Cada aba permite baixar um XML individual e todos os XMLs da aba em ZIP.

Na barra de período ficam os botões de download:

| Botão | O que entrega |
|-------|----------------|
| **BAIXAR XMLs (ZIP)** | Todos os XMLs do período, em pastas separadas por tipo |
| **RELATÓRIO FISCAL (PDF)** | Relatório agrupado por CFOP/CSOSN (faturamento fiscal × sem emissão) |
| **DETALHADO (EXCEL)** | Planilha item a item de cada NFC-e + aba "Resumo Faturamento" |
| **PACOTE CONTÁBIL (ZIP)** | Tudo junto: XMLs + PDF + Excel + `LEIA-ME.txt` |

Esses relatórios são **exatamente os que o app já gera** no botão "Exportar
pacote mensal para o contador": os dois lados usam o mesmo
`PacoteContabilService`, então o resultado é idêntico (mesmos nomes de arquivo,
mesmas colunas, mesmo resumo).

---

## Passo 1 — Criar a estrutura na nuvem

Rode os **dois** scripts abaixo no Supabase Dashboard → **SQL Editor** → New query
(clique em **RUN** em cada um). Ambos são idempotentes:

1. `CRIAR_PORTAL_CONTADOR_SUPABASE.sql` — cria a tabela `portal_contador_acessos`
   e garante que as colunas de XML existam em `nfces`, `nfes` e `notas_entrada`.
2. `CRIAR_BUCKET_XMLS_SUPABASE.sql` — cria o bucket **`xmls`** (privado) onde
   ficam os arquivos que o contador baixa, com as políticas de acesso.

## Passo 2 — Cadastrar o acesso do contador

Com o `.env` preenchido (`SUPABASE_URL` e `SUPABASE_ANON_KEY`):

```powershell
# Criar/atualizar o acesso (com senha própria)
.venv\Scripts\python.exe criar_acesso_portal_contador.py --cnpj 04.829.400/0001-65 --senha "MinhaSenha123" --nome "Escritorio Contabil ABC"

# Criar usando a SENHA PADRAO (quando --senha nao e informado)
.venv\Scripts\python.exe criar_acesso_portal_contador.py --cnpj 04829400000165 --nome "Contador Joao"

# Conferir quem já tem acesso
.venv\Scripts\python.exe criar_acesso_portal_contador.py --listar

# Bloquear um acesso (o contador para de conseguir entrar)
.venv\Scripts\python.exe criar_acesso_portal_contador.py --cnpj 04829400000165 --desativar
```

> **Senha padrão: `Exodo@2026`** — usada automaticamente quando você não passa
> `--senha`. Serve só para o primeiro acesso/teste: troque depois rodando o
> script de novo com `--cnpj` + `--senha` (ele atualiza o mesmo acesso, sem
> duplicar). Não há senha "de fábrica" gravada no app — ela só existe depois
> que você cadastra o acesso.

O `cnpj` informado é o **login** do contador e também a empresa cujas notas ele
enxerga (o CNPJ é comparado ignorando pontos e traços). Para um escritório que
atende vários clientes, crie **um acesso por CNPJ** — assim cada contador vê
somente as notas daquela empresa.

> A senha nunca é gravada em texto puro: o banco guarda apenas
> `sha256(salt + senha)`, o mesmo cálculo feito pelo app.

## Passo 3 — Enviar os XMLs para a nuvem

⚠️ **Importante:** o app **não** gravava o XML no banco (nem local nem nuvem) —
ele só salvava o arquivo em `C:\ExodoNFCe\<CNPJ>\<AAAA-MM>\`. Por isso o portal
precisa do bucket `xmls` populado.

**Envio em massa (backfill)** — pega todos os XMLs que já existem no disco:

```powershell
# Conferir o que seria enviado, sem enviar
.venv\Scripts\python.exe enviar_xmls_storage.py --simular

# Enviar (pula o que já está na nuvem)
.venv\Scripts\python.exe enviar_xmls_storage.py
```

O script mapeia `C:\ExodoNFCe\<CNPJ>\...\<CHAVE>-nfe.xml` para
`xmls/<empresa_id>/<CHAVE>.xml`. Ele descobre a empresa pelo CNPJ da pasta e,
quando a pasta não tem CNPJ (caso das cópias em `Pacotes\...`), pelo CNPJ que
está dentro da própria chave de acesso. É seguro rodar várias vezes.

**Daqui pra frente é automático:** ao autorizar uma NFC-e, o app salva o arquivo
local e envia o XML para o bucket `xmls` (em `NfceXmlLocalService`). Mesmo
assim, vale rodar o backfill de vez em quando em máquinas antigas, porque ele
recupera notas que foram emitidas antes desta alteração.

> **Cobertura atual desta máquina:** 47 XMLs únicos enviados, cobrindo 46 das 62
> notas (41 NFC-e de 54 e 5 NF-e de 7). As 15 restantes (11 NFC-e de 2026-07,
> 2 NFC-e e 2 NF-e de 2026-08) **não existem em disco**, então aparecem no portal
> como "XML não disponível". Se elas estiverem em backup ou no Google Drive,
> rode o script apontando para a pasta correta:
> `.venv\Scripts\python.exe enviar_xmls_storage.py --pasta "D:\Backup\XMLs"`

## Passo 4 — Publicar no Firebase Hosting

O Firebase CLI **não está logado** nesta máquina. Rode primeiro:

```bash
npx firebase login
```

Depois, o pacote já está pronto (`build/web` gerado). Para republicar:

```bash
# 1) Gerar o build web
flutter build web --release --no-wasm-dry-run

# 2) Enviar para o Firebase
npx firebase deploy --only hosting --project exodosystems-1541d
```

Ou use os scripts prontos (já usam a flag correta):

- `EXECUTAR_DEPLOY_FIREBASE.bat` → `deploy_firebase_automatico.ps1`

### ⚠️ Por que `--no-wasm-dry-run`

O `flutter build web` puro falha com:

```
Error: Dart library 'dart:ffi' is not available on this platform.
```

Isso acontece porque o `dart:ffi` (usado pelo app **desktop** para abrir
processos sem janela de CMD) é verificado pelo *dry-run* do Wasm. O helper
`win32_process_helper.dart` agora usa import condicional
(`win32_process_helper_stub.dart` no Web / `win32_process_helper_io.dart` no
desktop), mas o dry-run do Wasm ainda reprova os pacotes transitivos `ffi` e
`win32`. A flag `--no-wasm-dry-run` compila só JavaScript e resolve.

---

## Como o contador usa

1. Acessa `https://exodosystems-1541d.web.app/portal-contador`
2. Informa o **CNPJ** (com máscara, é formatado automaticamente) e a **senha**
3. Escolhe o período (**De** / **Até**) — por padrão, o mês atual
4. Navega entre as abas e baixa:
   - o XML de uma nota específica (ícone de download na linha), ou
   - todos os XMLs da aba (`Baixar XMLs desta aba`), ou
   - **BAIXAR TUDO (ZIP)** com todas as notas em pastas separadas por tipo

Notas sem XML na nuvem aparecem com o ícone ☁ desabilitado e são listadas no
`LEIA-ME.txt` do ZIP (o app desktop mantém uma cópia local em
`C:\ExodoNFCe\<CNPJ>\<AAAA-MM>\`).

---

## Arquivos envolvidos

| Arquivo | Função |
|---------|--------|
| `CRIAR_PORTAL_CONTADOR_SUPABASE.sql` | Tabela de acessos + colunas de XML |
| `CRIAR_BUCKET_XMLS_SUPABASE.sql` | Bucket `xmls` + políticas do Storage |
| `criar_acesso_portal_contador.py` | Cadastra/lista/desativa acessos |
| `enviar_xmls_storage.py` | Envia os XMLs do disco para o bucket `xmls` |
| `lib/services/portal_contador_service.dart` | Login por CNPJ+senha e leitura dos XMLs |
| `lib/pages/portal_contador_page.dart` | Tela do portal (login, abas, XMLs e relatórios) |
| `lib/widgets/historico_nfce_pdv_dialog.dart` | Botão "Exportar pacote mensal para o contador" (usa o mesmo serviço) |
| `lib/main.dart` | Rota `/portal-contador` (fora do login do sistema) |
| `lib/services/pacote_contabil_service.dart` | Gera o PDF fiscal, o Excel e o ZIP do pacote contábil (usado pelo app **e** pelo portal) |
| `lib/services/nfce_xml_local_service.dart` | Salva o XML local e envia para o bucket `xmls` |
| `lib/services/win32_process_helper*.dart` | Facade FFI/stub para o build web |
| `DEPLOY_FIREBASE_AGORA.bat` | Login + build + deploy em um clique |

## Detalhes técnicos que valem saber

- **Os relatórios são gerados na hora**, no navegador, a partir das tabelas
  `nfces`, `vendas_balcao` e `produtos` do Supabase — não dependem do app estar
  aberto.
- As consultas são **paginadas em 1000 linhas** (limite padrão do PostgREST).
  Sem isso, uma empresa com mais de 1000 vendas no mês receberia um resumo de
  faturamento incompleto.
- O pacote contábil é baseado nas **NFC-e** (igual ao do app). NF-e de entrada
  ou NF-e emitidas não entram no PDF/Excel — aparecem apenas como XML para
  download nas abas correspondentes.

## De onde vem o XML que o portal baixa

O portal tenta, nesta ordem:

1. A coluna XML da própria tabela (`xml_autorizado`, `xml_enviado`, `xmlOriginal`…)
2. O bucket `xmls`, em `xmls/<empresa_id>/<chave>.xml` — **na prática é a fonte real**

Ao abrir o portal, uma única chamada lista o bucket e já marca quais notas têm
arquivo disponível (ícone ☁ ligado/desligado). O download só acontece no clique,
e o XML fica em cache na sessão para não baixar duas vezes no ZIP.

## Observações de segurança

- O portal é uma rota **pública** no mesmo site do sistema, com login próprio
  (não usa o login de usuários do app).
- A leitura das notas usa a chave `service_role` embutida no app web — mesma
  abordagem já usada pelo restante do sistema. Quem tiver o link do portal
  ainda precisa do CNPJ cadastrado + senha para ver qualquer XML.
- Desative um acesso com `--desativar` assim que o contador deixar de atender a
  empresa.
