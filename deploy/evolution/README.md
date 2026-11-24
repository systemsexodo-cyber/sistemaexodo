# Evolution API 2.3.7 — deploy na VM (`ubuntu-supabase`)

**Já está rodando.** Esta pasta é a origem do que foi instalado em
`/home/charles/evolution` na VM.

| Item | Valor |
| --- | --- |
| URL pública | `https://exodosystems.tail9b4943.ts.net/evolution` |
| API Key | `AUTHENTICATION_API_KEY` no arquivo `.env` desta pasta |
| Instância | você define no app (o app cria na API automaticamente) |
| Containers | `evo_api`, `evo_proxy`, `evo_postgres`, `evo_redis` |
| Versão | `v2.3.7` (fixa — nunca `latest`) |

A stack é isolada: banco e cache próprios, rede própria. **Nada** do Supabase
local (`~/supabase`), nem as rotas `443` (`/`, `/central-nuvem`,
`/central-servidor`), `8443` (realtime) e `10000` (Postgres) foi alterado.

---

## Como foi montado

```
navegador/celular
   │  https://exodosystems.tail9b4943.ts.net/evolution/...
   ▼
Tailscale Funnel  (/evolution)          Windows, porta 443
   ▼
127.0.0.1:8093  ── NAT VirtualBox ──▶  VM:8093   (nginx, container evo_proxy)
                                          │  remove o prefixo /evolution
                                          ▼
                                      api:8080  (container evo_api)
                                          ├──▶ postgres:5432  (evo_postgres)
                                          └──▶ redis:6379     (evo_redis)
```

- **Por que o prefixo `/evolution`:** as três portas HTTPS/TCP que o Tailscale
  Funnel oferece (`443`, `8443`, `10000`) já estão em uso pelo Supabase, pelo
  realtime e pelo Postgres. Em vez de mexer em qualquer uma, a API entra como
  um caminho novo no mesmo domínio.
- **`nginx.conf`** remove o prefixo antes de entregar na API (ela serve na raiz).
  Também aceita requisições sem prefixo, para não depender de como o Funnel
  repassa o caminho.
- **NAT 8093:** o Funnel roda no Windows e só enxerga `127.0.0.1`; a regra
  `evolution,tcp,127.0.0.1,8093,,8093` leva à VM. Ela **não** fica salva na
  configuração da VM (o VirtualBox recusa `modifyvm` com a VM ligada), então é
  recriada no boot por `INICIAR_EVOLUTION.bat`.

## Subir de novo / operar

```bash
ssh -i ~/.ssh/id_ed25519_vm -p 2222 charles@127.0.0.1
cd ~/evolution
docker compose ps                      # estado dos 4 containers
docker compose logs -f --tail=100 api  # log da API
docker compose restart api             # reiniciar só a API
docker compose up -d                   # aplicar mudança de .env
```

Atualizar a documentação local depois de mexer na VM:

```bash
# do Windows, na raiz do projeto
scp -i ~/.ssh/id_ed25519_vm -P 2222 deploy/evolution/{docker-compose.yaml,nginx.conf,.env} charles@127.0.0.1:~/evolution/
```

### Reboot do PC

1. `INICIAR_FUNNEL_SUPABASE.bat` sobe a VM.
2. `INICIAR_EVOLUTION.bat` (atalho em `shell:startup`) espera a VM, recria o NAT
   e reaplica o Funnel `/evolution`.
3. Os containers sobem sozinhos (`restart: unless-stopped` + Docker habilitado
   no boot). Log do script: `logs/evolution.log`.

## Backup

```bash
ssh -i ~/.ssh/id_ed25519_vm -p 2222 charles@127.0.0.1 \
  'docker exec evo_postgres pg_dump -U evolution evolution | gzip > ~/evolution/backup_$(date +%F).sql.gz'
```

O volume `evolution_instances` guarda a sessão do WhatsApp (as credenciais do
aparelho conectado). **Não** rode `docker compose down -v`: perde a sessão e
precisa escanear o QR Code de novo.

---

## Cadastrar no app Flutter

A configuração é **por empresa**, salva nos campos `whatsappApiUrl`,
`whatsappApiKey`, `whatsappInstanceName` e `whatsappTipo`.

### Onde preencher

**Tela WhatsApp → card "CONFIGURAÇÕES TÉCNICAS"** (`lib/pages/whatsapp_gerenciamento_page.dart`):

| Campo na tela | O que colocar |
| --- | --- |
| URL da API (Evolution API) | `https://exodosystems.tail9b4943.ts.net/evolution` |
| API Key / Secret Token | o `AUTHENTICATION_API_KEY` do `.env` |
| Nome da Instância | um nome curto e único por empresa, ex.: `exodo_vendas` |

O chip ao lado do título precisa estar **EVOLUTION** (verde). Se estiver
**TWILIO** (roxo), toque no ícone ⇄ "Mudar Tipo de Serviço" — com Twilio o app
usa outro endpoint e essa URL não funciona.

Clique em **SALVAR CONFIGURAÇÕES**. A tela verifica a conexão a cada 10s e, se a
instância ainda não existir, **cria sozinha** (`POST /instance/create` com
`integration: WHATSAPP-BAILEYS`).

### Conectar o aparelho

1. Depois de salvar, o QR Code aparece no card de status.
2. No celular: WhatsApp → **Aparelhos conectados** → **Conectar aparelho**.
3. Escaneie. O status deve virar **conectado** (`open`).
4. Clique em **ENVIAR MENSAGEM DE TESTE** para confirmar o envio de verdade.

### Também dá para preencher no cadastro da empresa

Em **Adicionar/Editar Empresa** existem os mesmos campos ("URL da Evolution
API", "API Key", "Nome da Instância"), com os chips *Evolution API
(Gratuito/Self-host)* e *Twilio Bridge*. Preencher lá já deixa a empresa pronta.

### Se o app for usado em várias empresas

Cada empresa tem sua própria instância e seu próprio QR Code, no mesmo servidor
e com a mesma API Key. O nome da instância é o que separa uma da outra — use
nomes estáveis (trocar o nome cria uma instância nova e exige novo QR).

---

## CORS

## Atendente virtual (IA local)

O servico `bot` (`bot/bot.py`, container `evo_bot`) recebe o webhook
`MESSAGES_UPSERT` da Evolution e responde usando o **Ollama da maquina
Windows** — nenhuma API paga e nenhum dado do cliente sai do computador da
loja.

```
WhatsApp -> Evolution (VM) -> evo_bot (rede evolution-net)
                                      |
                                      +-> Ollama 10.0.2.2:11434 (modelo `eobicho`)
                                      +-> banco exodo_db 10.0.2.2:5432 (somente leitura)
                                      +-> Evolution /message/sendText
```

- `10.0.2.2` e o loopback do host dentro do NAT do VirtualBox: o Ollama fica
  escutando so em `127.0.0.1` e mesmo assim a VM o alcanca.
- O modelo `eobicho` (base `llama3.2:3b`) usa `num_gpu 0` (a GTX 1050 tem so 2 GB
  de VRAM; com offload o modelo cai para 2,4 tok/s), `temperature 0.1`, `seed 42`,
  `top_p 0.8`, `top_k 20`, `repeat_penalty 1.15`, `num_predict 90`, `num_ctx 3072`
  e `keep_alive 24h`. O modelo nao é fine-tunado: ele apenas redige, usando dados
  reais trazidos do banco/arquivo.
- Warmup: um ping a cada `BOT_WARMUP_INTERVAL` s mantém o modelo carregado (cold
  start custa 20–30 s).
- O bot **nao responde** grupo, status, broadcast, nem mensagem sem texto
  (audio/imagem), ignora `fromMe` e limita respostas por contato por hora.

```bash
# logs
docker compose -f ~/evolution/docker-compose.yaml logs -f --tail=50 bot

# ligar/desligar o atendimento automatico (sem parar a API)
curl -s -X POST "http://127.0.0.1:8093/webhook/set/e-o-bicho-petshop"   -H "apikey: $AUTHENTICATION_API_KEY" -H "Content-Type: application/json"   -d '{"webhook":{"enabled":false}}'

# conferir a configuracao atual
curl -s "http://127.0.0.1:8093/webhook/find/e-o-bicho-petshop" -H "apikey: $AUTHENTICATION_API_KEY"
```

Onde o bot tira cada informação (ordem de decisao):

1. **Bloqueios** (gatilho → resposta pronta): o que a loja **não** faz, ex. "venda de
   animais" → resposta direta, sem IA.
2. **Pedido novo** ("quero fazer um pedido") → texto do campo `pedido_novo`.
3. **Status/pedido** ("meu pedido PED-1177", "quanto ficou meu pedido?") → consulta
   ao banco da loja (`BOT_PEDIDOS_DSN`); responde o status real, o valor e a data
   do último pedido do telefone que mandou a mensagem.
4. **Catálogo** ("o que vocês têm?", "ração para gato", "meu gato está com pulga") →
   busca real na tabela `produtos` da empresa configurada (`BOT_EMPRESA_ID`), filtra
   pela espécie citada (não devolve ração de peixe a quem pediu de cachorro) e
   responde com nomes, preços e estoque de verdade.
5. **Dados oficiais** (`negocio.json`, sem IA): endereço, horário, formas de
   pagamento, serviços, entrega, horário de funcionamento, nota fiscal.
6. **Modelo** (Ollama, apenas para o que não cabe nas regras acima) → a resposta passa
   por filtros: preços só passam se forem exatamente do catálogo, e qualquer assunto
   bloqueado/inventado vira o fallback ("vou confirmar com a equipe").
7. **Alimentação/cuidados** ("pode comer todo dia?", "quanto de ração?", "como cuidar?")
   → nunca o modelo opina; a equipe confirma.

### Reutilizar o bot para outra empresa

O codigo e o modelo **nao tem nome nem prompt de loja**: o modelo `eobicho` e a
base neutra (`llama3.2:3b` + parametros) e todo o texto do atendente vem do
ambiente. Para atender outra empresa:

1. Crie a instancia dela na Evolution (o app Flutter faz isso sozinho) e conecte o
   QR Code.
2. Copie a pasta do compose para outro diretorio (ou suba outro projeto) e no
   `.env` dela mude apenas:

```
BOT_EMPRESA_NOME=Outra Loja
BOT_EMPRESA_ID=<id da empresa no banco>
BOT_INSTANCE=outra-loja
BOT_PEDIDOS_DSN=...   # banco de pedidos (somente leitura)
BOT_CATALOGO_DSN=...  # banco de produtos (somente leitura; pode ser o mesmo)
AUTHENTICATION_API_KEY=<a mesma chave da API>
BOT_PROMPT_FILE=      # ou BOT_PROMPT=... para um tom proprio
BOT_NUM_CTX=3072
BOT_NUM_PREDICT=90
BOT_NUM_GPU=0
BOT_TEMPERATURE=0.1
BOT_KEEP_ALIVE=24h
BOT_WARMUP=1
```

3. `docker compose up -d bot` e aponte o webhook da instancia para o container:

```bash
curl -s -X POST "http://127.0.0.1:8093/webhook/set/outra-loja"   -H "apikey: $AUTHENTICATION_API_KEY" -H "Content-Type: application/json"   -d '{"webhook":{"enabled":true,"url":"http://evo_bot:8096/webhook","events":["MESSAGES_UPSERT","SEND_MESSAGE"]}}'
```

O bot ignora payload de instancia diferente de `BOT_INSTANCE`, entao dois bots
podem compartilhar a mesma Evolution sem responder pela instancia errada.
Confira com `GET /health` (`empresa`, `catalogo_itens`, `pedidos_consulta`, `instance`).

### Dados basicos da loja (`negocio.json`) — a barreira contra alucinacao

`deploy/evolution/bot/negocio.json` (montado em `/config/negocio.json`, editavel
na VM) e a fonte de verdade. O que estiver nele e respondido **direto, sem passar
pelo modelo** — logo, nao ha como a IA inventar horario ou endereco. Campos
vazios significam "o bot nao afirma nada sobre aquilo".

```json
{
  "nome": "E o Bicho Pet Shop",
  "endereco": "Rua São Jerônimo, 177 - Jardim São Judas Tadeu, São José dos Campos/SP",
  "telefone": "(12) 99643-5372",
  "horario": { "texto": "Atendemos todos os dias, das 08:00 à meia-noite" },
  "formas_pagamento": ["pix", "dinheiro", "cartão de débito", "cartão de crédito", "VR (vale refeição)"],
  "servicos": ["banho e tosa", "vacinação", "taxi dog"],
  "entrega": "Fazemos entrega. Para confirmar a taxa e o prazo do seu endereço, a equipe te responde por aqui.",
  "pedido": "Vou confirmar o seu pedido com a equipe e já te respondo por aqui.",
  "pedido_novo": "Claro! Me diz o que você precisa que eu já vejo o preço e a disponibilidade pra você.",
  "saude": "Sinto muito! Sobre a saúde do pet eu prefiro confirmar com a equipe antes de indicar qualquer coisa.",
  "conselho": "Sobre a quantidade e a rotina de alimentação, prefiro confirmar com a equipe: cada pet tem uma necessidade diferente.",
  "cuidado": "Essa é uma dúvida que eu prefiro confirmar com a equipe antes de orientar.",
  "respostas": { "nota fiscal": "Emitimos nota fiscal em todas as vendas." },
  "catalogo": {
    "resumo": "Trabalhamos com ração para cães e gatos, petiscos, medicamentos, areia, brinquedos, acessórios, estética e higiene, aquarismo, aves e roedores, além de pesca e camping. Quer que eu procure algum item específico?",
    "categorias": { "RACAO CAES E GATOS": "ração para cães e gatos", ... }
  },
  "foco": {
    "assuntos": ["banho e tosa", "vacinação", "ração e petiscos", "acessórios", "entrega", ...],
    "bloqueios": { "venda de animais": "Não trabalhamos com venda de animais..." },
    "fora_do_tema": "Por aqui eu ajudo com produtos e serviços para o seu pet. Sobre isso, quem pode te responder é a equipe."
  }
}
```

- `catalogo.resumo` é a resposta de "o que vocês têm?"; `categorias` mapeia os
  grupos reais do banco para termos amigáveis.
- `entrega`, `saude`, `conselho` e `cuidado` vêm do banco da loja (frete, horários,
  zonas de entrega) quando preenchidos; caso contrário o bot avisa que a equipe
  responde.

Como funciona:

- pergunta com gatilho conhecido (horario, endereco, pagamento, servicos, entrega)
  recebe o texto montado do arquivo, **sem IA**;
- pedido de preco (`quanto custa`, `valor`, `R$`) recebe o aviso padrao direto,
  sem IA — nao existe tabela de precos fixa;
- pergunta sobre **pedido/status** consulta a tabela `pedidos` do banco (somente
  leitura) e responde o status real;
- pergunta sobre **produto** consulta a tabela `produtos` do banco e responde nomes,
  preços e estoque de verdade;
- `foco.assuntos` e o **escopo do nicho**: mensagem que nao fala de nenhum desses
  assuntos nem chega no modelo (foi assim que ele ofereceu "venda de animais");
- `foco.bloqueios` (gatilho -> resposta) responde sem IA o que a loja **nao** faz;
- tema da loja que ainda nao tem dado no arquivo responde "vou confirmar com a
  equipe" — nunca chuta;
- `BOT_STRICT=1` desliga o modelo de vez: o bot so responde o que estiver no arquivo;
- `respostas` aceita gatilho -> texto livre para o que for especifico da loja;
- o arquivo e relido a cada mensagem: salve na VM e ja vale, sem reiniciar.

Editar na VM:

```bash
ssh -i ~/.ssh/id_ed25519_vm -p 2222 charles@127.0.0.1 'nano ~/evolution/bot/negocio.json'
curl -s http://127.0.0.1:8096/health   # dentro do container: config_facts mostra quantas regras ativas
```
### Pausar o bot e conversar com ele pelo app

O bot expoe tres rotas, publicadas em `127.0.0.1:8097` **do Windows** (regra de NAT
`bot` do VirtualBox, criada pelo `INICIAR_EVOLUTION.bat`). A VM esta em NAT, entao
essa porta nao e alcancavel pela rede local nem pela internet.

| Rota | Efeito |
| --- | --- |
| `GET /health` | estado: `paused`, `empresa`, `config_facts`, `paused_contacts`... |
| `GET /admin/perguntas?only=falhas&limit=100` | histórico das perguntas reais + como o bot respondeu |
| `POST /admin/pause` `{"minutes": N}` | pausa tudo. `N > 0` = por N minutos; `N = 0` = ate retomar |
| `POST /admin/resume` | volta a responder |
| `POST /chat` `{"text": "..."}` | mesma logica do WhatsApp, mas **nao envia nada**; devolve `reply`, `source`, `rule`, `ms` |

Rotas de `POST` exigem o header `x-bot-token` com o `BOT_ADMIN_TOKEN` do `.env`:

```bash
TOKEN=$(ssh -i ~/.ssh/id_ed25519_vm -p 2222 charles@127.0.0.1 'grep ^BOT_ADMIN_TOKEN= ~/evolution/.env | cut -d= -f2')
curl -s -X POST http://127.0.0.1:8097/chat -H "x-bot-token: $TOKEN" \
  -H 'Content-Type: application/json' -d '{"text":"Que horas voces abrem?"}'
# {"reply":"Atendemos todos os dias, das 08:00 a meia-noite.","source":"config",...}
```

No app: **Gerenciamento WhatsApp → ícone do robô** (canto superior direito). A tela
mostra o status, os botoes Pausar / Pausar 1h / Retomar e um chat de teste. A etiqueta
de cada resposta diz de onde ela veio:

- `Cadastro` — saiu do `negocio.json`, sem IA (o caminho mais confiavel);
- `IA` — texto livre do modelo;
- `Bloqueio: preco` / `Bloqueio: dado inventado` — o filtro barrou a resposta;
- `Pedido` — pergunta de pedido/rastreio: resposta fixa do `negocio.json`, e ainda
  assim aparece na lista de perguntas para voce revisar.

O que voce escrever ali **nao vai para o WhatsApp de nenhum cliente**. A pausa vale
para todos os contatos e sobrevive a restart do container (fica em `state.json`).

### Consulta de pedidos do WhatsApp

Com `BOT_PEDIDOS_DSN` preenchido (DSN do banco da loja, usado **somente para
leitura**), pergunta com "pedido" nao cai mais em "vou confirmar": o bot procura na
tabela `pedidos` os ultimos pedidos do **telefone que mandou a mensagem** (compara os
8 ultimos digitos) e responde o status real.

- `meu pedido chegou?` → "Achei aqui: seu pedido PED-1177 está pendente…";
- `meu pedido PED-1177` → filtra pelo numero citado, sempre do proprio telefone;
- mais de um pedido → lista no maximo `BOT_PEDIDOS_MAX` (padrao 2);
- sem DSN, banco fora do ar ou telefone sem pedido → texto do campo `pedido` do
  `negocio.json`; o atendimento nunca trava (`BOT_PEDIDOS_TIMEOUT`, padrao 6s).

Teste sem mandar mensagem a ninguem (a rota `/chat` aceita `telefone`):

```bash
curl -s -X POST -H "Content-Type: application/json" -H "x-bot-token: $TOKEN" \
  -d '{"text":"qual o status do meu pedido?","telefone":"5512999999999"}' \
  http://127.0.0.1:8097/chat
```

### Historico de perguntas (onde o bot nao soube)

Cada mensagem de cliente que o bot atende vira uma linha em
`/data/perguntas.jsonl` (volume `bot_state`, `BOT_QUESTIONS_FILE` para mudar,
`BOT_QUESTIONS_MAX` = 2000 linhas): pergunta, resposta, `origem`, `regra`,
contato, horario. Teste pelo app nao entra nesse arquivo.

`GET /admin/perguntas` devolve as mais recentes, com `counts` por origem:

```bash
TOKEN=$(ssh -i ~/.ssh/id_ed25519_vm -p 2222 charles@127.0.0.1 'grep ^BOT_ADMIN_TOKEN= ~/evolution/.env | cut -d= -f2')
curl -s "http://127.0.0.1:8097/admin/perguntas?only=falhas" -H "x-bot-token: $TOKEN" | head -c 400
```

`only=falhas` (padrao) traz `fallback_*`, `erro_ollama`, `vazio` e `handoff`;
`only=todas` traz tudo. No app: **Conversar com o bot -> icone de conversas**
(ou `BotPerguntasPage`). Cada item abre um detalhe com a pergunta, a resposta e um
botao para testar de novo no chat.

### Regras configuraveis

| Variavel (`.env`) | Padrao | Efeito |
| --- | --- | --- |
| `BOT_HUMAN_MUTE_MIN` | `30` | Cala o bot nesse contato depois que alguem da loja responde pelo celular. `0` desliga. |
| `BOT_HANDOFF_MUTE_MIN` | `120` | Pausa maior depois que o cliente pede atendente ou ameaca reclamar. |
| `BOT_ACTIVE_HOURS` | vazio (24 h) | Janela em que o bot pode responder, ex.: 18:00-08:00. |
| `BOT_KEYWORDS` | vazio (todas) | Se preenchido, so responde mensagens com uma dessas palavras. |
| `BOT_EXTRA_INFO` | vazio | UNICO lugar de onde o modelo pode tirar horario, endereco, pagamento e servicos. |
| `BOT_FALLBACK` | "Vou confirmar..." | O que o cliente recebe quando o dado nao existe. |
| `BOT_INTRO` | frase de assistente | Aviso junto da primeira resposta de cada contato (a cada 12 h). |

### Por que existe bloqueio no codigo

O modelo `llama3.2:3b` **inventa preco e horario mesmo com o prompt proibindo**
(testado: respondeu "R$ 25,00" e "aberto das 9h as 18h" sem esses dados existirem).
Por isso o `bot.py` filtra a resposta antes de enviar:

- qualquer valor ou preco (`R$`, "reais", "custa") vira `BOT_FALLBACK`;
- horario, endereco, prazo e estoque ficam bloqueados enquanto `BOT_EXTRA_INFO`
  estiver vazio.

Para o bot poder informar horario e endereco, cadastre em `BOT_EXTRA_INFO`, por
exemplo: Horario: seg a sex 8h as 18h; sabado 8h as 12h. Endereco: Rua X, 123.

### Pausa por resposta humana

O webhook escuta `SEND_MESSAGE` **e** `MESSAGES_UPSERT`. Quando chega uma mensagem
da loja (`fromMe`), o contato fica em pausa por `BOT_HUMAN_MUTE_MIN`. Os envios do
proprio bot sao reconhecidos pelo `key.id` devolvido por `sendText` e **nao**
pausam o contato (sem isso o bot se calava sozinho depois da primeira resposta).

### Pausas sobrevivem a restart (volume `bot_state`)

As pausas ficam em `/data/state.json`, dentro do volume nomeado `bot_state`
(declarado no `docker-compose.yaml`). Sem esse volume, reiniciar o container ou a
VM faria o bot voltar a responder conversas que um humano ja tinha assumido.

- gravacao atomica (`state.json.tmp` + `os.replace`) a cada pausa;
- no boot o bot recarrega o arquivo e descarta o que ja expirou;
- `GET /health` mostra `paused_contacts` e `state_file`.

Conferir o conteudo:

```bash
ssh -i ~/.ssh/id_ed25519_vm -p 2222 charles@127.0.0.1 \
  'docker exec evo_bot cat /data/state.json'
```

O arquivo pertence ao root dentro do container, então use `docker exec` (que já
roda como root) em vez de editar pelo host:

```bash
# liberar UM contato (troque o jid)
docker exec evo_bot python3 -c "import json;p='/data/state.json';d=json.load(open(p));d['muted_until'].pop('5511999999999@s.whatsapp.net',None);json.dump(d,open(p,'w'))"
docker compose restart bot

# liberar TODOS os contatos
docker exec evo_bot sh -c 'printf "{\"saved_at\":\"reset\",\"muted_until\":{}}" > /data/state.json'
docker compose restart bot
```

`CORS_ORIGIN=*` **de propósito**. O middleware do Evolution rejeita a requisição
quando o `Origin` não está na lista, e o app Flutter no celular/desktop usa o
package `http`, que não envia esse header — uma lista restrita derrubaria o app
com `Not allowed by CORS`. O controle de acesso real é a API Key (toda rota
responde `401` sem ela). O navegador continua recebendo o `Origin` refletido,
que é o necessário para o app web.

## Diagnóstico

| Sintoma | Causa provável |
| --- | --- |
| `401 Unauthorized` | API Key diferente da do `.env` (ou espaço sobrando no campo) |
| `Não foi possível criar a instância` | URL sem `/evolution`, chip em TWILIO, ou API fora do ar |
| QR nunca aparece | instância criada mas não conectada: confira os logs da API |
| Funciona na loja e não fora | Funnel/NAT caíram após reboot: veja `logs/evolution.log` |
| `Not allowed by CORS` | `CORS_ORIGIN` foi trocado de `*` para uma lista |

Teste rápido de fora da rede:

```bash
curl -s https://exodosystems.tail9b4943.ts.net/evolution/
# {"status":200,"message":"Welcome to the Evolution API, it is working!", ...}

curl -s -H "apikey: SUA_CHAVE" \
  https://exodosystems.tail9b4943.ts.net/evolution/instance/fetchInstances
# []  (ou as instâncias já criadas)
```

## Segurança

A `AUTHENTICATION_API_KEY` dá acesso total a todas as instâncias do servidor.
Ela está em `deploy/evolution/.env` (ignorado pelo git) e em
`~/evolution/.env` na VM (permissão `600`). Se vazar, troque nos dois lugares,
faça `docker compose up -d` e atualize a chave em cada empresa no app.
