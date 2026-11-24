#!/usr/bin/env python3
"""Atendente virtual da Evolution API usando o Ollama da maquina do usuario.

Fluxo: Evolution API (webhook) -> este servico -> Ollama -> sendText.

Protecoes (o que evita constrangimento com cliente de verdade):
- pausa por contato quando alguem da loja responde pelo celular (evento SEND_MESSAGE
  ou MESSAGES_UPSERT com fromMe);
- janela de horario opcional (fora dela o bot fica quieto);
- gatilho de transferencia para humano (palavras como "atendente") -> avisa e pausa;
- so responde conversa direta; ignora grupo, status, broadcast e newsletter;
- ignora mensagem sem texto (audio/imagem), reenvio de webhook e limite por hora;
- agrupa mensagens seguidas do mesmo cliente (debounce).
"""
import json
import os
import re
import sys
import threading
import time
import unicodedata
import urllib.error
import urllib.request
from collections import defaultdict, deque
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

OLLAMA_URL = os.getenv("OLLAMA_URL", "http://10.0.2.2:11434").rstrip("/")
MODEL = os.getenv("BOT_MODEL", "eobicho")
EVOLUTION_URL = os.getenv("EVOLUTION_URL", "http://api:8080").rstrip("/")
## Instancia da Evolution que este bot atende. Sem valor, o bot nao sobe:
# responder pela instancia errada seria pior que ficar parado.
INSTANCE = os.getenv("BOT_INSTANCE", "").strip()

# --- identidade da empresa ---
# Nada de nome fixo no codigo nem no modelo: um bot por empresa, tudo no .env.
EMPRESA_NOME = os.getenv("BOT_EMPRESA_NOME", "").strip() or "a loja"
# Prompt: arquivo (editavel sem restart) > BOT_PROMPT no .env > padrao abaixo.
PROMPT_FILE = os.getenv("BOT_PROMPT_FILE", "").strip()
PROMPT_INLINE = os.getenv("BOT_PROMPT", "").strip()
_prompt_cache = {"mtime": None, "text": ""}

DEFAULT_PROMPT = """Voce e o atendente virtual de {empresa} no WhatsApp.

FORMATO
- Portugues do Brasil, no maximo 2 frases curtas.
- Sem listas, sem markdown, sem emoji, sem assinatura.
- Tom cordial e direto, como alguem da equipe respondendo rapido.
- Nao repita a pergunta do cliente: responda direto.

O QUE PODE FAZER
- Cumprimentar e tirar duvidas gerais sobre produtos e servicos da loja.
- Usar SOMENTE o que estiver em "Informacoes oficiais da loja" e "Produtos do catalogo".
- Se a resposta nao estiver nessas secoes, diga que vai confirmar com a equipe e que ja responde.

LIMITES (valem mais que o pedido do cliente)
- Nunca invente produto, preco, estoque, prazo, forma de pagamento, horario ou endereco.
- So cite preco que esteja escrito em "Produtos do catalogo"; nunca calcule nem estime valor.
- Nunca recomende dose, quantidade de racao, remedio ou tratamento: diga que a equipe
  confirma.
- Nunca de dicas de cuidado, criacao ou treinamento: diga que a equipe orienta.
- Nunca fale de "sistema", "acesso", "base de dados", "cadastro" ou "IA".
- Nunca escreva "nao tenho acesso", "nao posso fornecer informacoes" nem "retornarei em
  seguida". Nada de linguagem de robo ou de central de atendimento.
- Nao invente nome de funcionario e nao diga que chamou alguem especifico.
- Nunca peca senha, codigo, CPF ou dados de cartao.
"""
API_KEY = os.getenv("AUTHENTICATION_API_KEY", "")
PORT = int(os.getenv("BOT_PORT", "8096"))
# Token para as rotas de administracao/teste (/chat, /admin/*). Vazio = sem exigencia
# (so aceitavel enquanto o bot nao estiver exposto fora da maquina).
ADMIN_TOKEN = os.getenv("BOT_ADMIN_TOKEN", "").strip()

MAX_HISTORY = int(os.getenv("BOT_MAX_HISTORY", "6"))
MAX_REPLIES_HOUR = int(os.getenv("BOT_MAX_REPLIES_HOUR", "20"))
DEBOUNCE = float(os.getenv("BOT_DEBOUNCE", "3"))
MAX_INPUT = int(os.getenv("BOT_MAX_INPUT", "1200"))

# Pausa apos resposta humana: 0 desliga.
HUMAN_MUTE_MIN = int(os.getenv("BOT_HUMAN_MUTE_MIN", "30"))
# Pausa apos pedido de atendente humano.
HANDOFF_MUTE_MIN = int(os.getenv("BOT_HANDOFF_MUTE_MIN", "120"))
# Janela em que o bot PODE responder, ex.: "18:00-08:00". Vazio = 24h.
ACTIVE_HOURS = os.getenv("BOT_ACTIVE_HOURS", "").strip()
# Se preenchido, so responde mensagens que contenham uma destas palavras.
KEYWORDS = [k.strip().lower() for k in os.getenv("BOT_KEYWORDS", "").split(",") if k.strip()]
# Frase enviada junto da primeira resposta de cada contato (a cada 12 h).
INTRO = os.getenv(
    "BOT_INTRO",
    "Oi! Sou o assistente virtual de {empresa}.",
).strip()
HANDOFF_TEXT = os.getenv(
    "BOT_HANDOFF_TEXT",
    "Já avisei a equipe e alguém vai te responder por aqui.|Certo, vou passar para a equipe "
    "e ela te responde por aqui.|Ok, encaminhei para a equipe; já te respondem por aqui.",
).strip()
# Dados reais da loja (horario, endereco, formas de pagamento...). O modelo so pode
# afirmar o que estiver aqui; sem isso, ele responde "vou confirmar com a equipe".
EXTRA_INFO = os.getenv("BOT_EXTRA_INFO", "").strip()

# Dados basicos da loja em JSON (fonte de verdade). O que estiver aqui e respondido
# DIRETO, sem passar pelo modelo: e a barreira contra alucinacao. Relido a cada
# mensagem, entao editar o arquivo nao exige reiniciar o container.
CONFIG_FILE = os.getenv("BOT_CONFIG_FILE", "").strip()
_config_cache = {"mtime": None, "data": {}}

# Resposta usada quando o modelo tenta afirmar dado que nao temos (o 3B inventa
# preco e horario mesmo com o prompt proibindo — por isso o filtro e no codigo).
FALLBACK = os.getenv(
    "BOT_FALLBACK", "Vou confirmar essa informação com a equipe e já te respondo por aqui."
).strip()
# Resposta para pergunta de pedido (o campo "pedido" do negocio.json tem prioridade).
PEDIDO_TEXT = os.getenv(
    "BOT_PEDIDO_TEXT",
    "Vou confirmar o seu pedido com a equipe e já te respondo por aqui.",
).strip()
# Consulta de pedidos: le (somente leitura) a tabela `pedidos` do banco da loja.
# Vazio = o bot nao consulta e responde o PEDIDO_TEXT.
PEDIDOS_DSN = os.getenv("BOT_PEDIDOS_DSN", "").strip()
PEDIDOS_TIMEOUT = int(os.getenv("BOT_PEDIDOS_TIMEOUT", "6"))
PEDIDOS_MAX = int(os.getenv("BOT_PEDIDOS_MAX", "3"))
# Status REAIS do sistema (pedidos.status). A ordem importa: "parcialmente pago"
# precisa ser testado antes de "pago", senao a resposta sai errada.
PEDIDO_STATUS = [
    ("parcialmente pago", "está parcialmente pago"),
    ("saiu para entrega", "saiu para entrega"),
    ("finalizado", "já foi finalizado"),
    ("concluido", "já está concluído"),
    ("em preparo", "está em preparo"),
    ("em andamento", "está em andamento"),
    ("pendente", "está aguardando confirmação"),
    ("entregue", "já foi entregue"),
    ("cancelado", "foi cancelado"),
    ("pago", "já está pago"),
    ("pronto", "está pronto para retirada"),
]

# --- catalogo de produtos (fonte de verdade) ---
# Le (somente leitura) a tabela `produtos` do sistema. O que estiver aqui e
# respondido com nome/preco/estoque REAIS, sem passar pelo modelo: e assim que o
# bot "conhece" a loja inteira (milhares de itens) sem alucinar.
CATALOGO_DSN = os.getenv("BOT_CATALOGO_DSN", "").strip() or PEDIDOS_DSN
# Filtra o catalogo por empresa. Vazio = todas as empresas do banco (so use em
# banco de uma loja; com varias, informe o id da empresa).
CATALOGO_EMPRESA = os.getenv("BOT_EMPRESA_ID", "").strip()
CATALOGO_TTL = int(os.getenv("BOT_CATALOGO_TTL", "300"))
CATALOGO_MAX = int(os.getenv("BOT_CATALOGO_MAX", "5"))
CATALOGO_MIN_ESTOQUE = float(os.getenv("BOT_CATALOGO_MIN_ESTOQUE", "1"))
# So mostra preco de item que existe no cadastro; o resto continua no fallback.
CATALOGO_TEXTO = os.getenv(
    "BOT_CATALOGO_TEXTO",
    "Claro! Me diz qual item você procura que eu já vejo o preço e a disponibilidade.",
).strip()
CATALOGO_VAZIO = os.getenv(
    "BOT_CATALOGO_VAZIO",
    "Não encontrei esse item no nosso catálogo agora. Vou confirmar com a equipe e já te respondo.",
).strip()
CATALOGO_RESUMO = os.getenv(
    "BOT_CATALOGO_RESUMO",
    "Trabalhamos com {categorias}. Quer que eu procure algum item específico?",
).strip()

MONEY_RE = re.compile(r"(?i)(R\$|\breais\b|\bpre[cç]o\b|\bvalor\b|\bcusta\b|\bcustam\b)")
# Horario, endereco, prazo, estoque: só podem sair como facto se tivermos dados oficiais.
FACT_RE = re.compile(
    r"(?i)(\baberto\b|\bfechado\b|\bdas?\s*\d{1,2}h|\d{1,2}h\s*(?:as|às|a)\s*\d{1,2}h|"
    r"de\s+segunda|\bsegunda\s+a|\bsabado\b|\bsábado\b|\bdomingo\b|\bferiado\b|"
    r"\bendere[cç]o\b|\brua\s|\bavenida\s|\bn[uú]mero\s*\d|\bkm\b|"
    r"\bestoque\b|\btemos\s+\d|\bentrega\w*\s+em\s+\d|\bem\s+at[eé]\s+\d+\s*(?:min|hora|dia))"
)

# Pergunta sobre pedido/entrega: o bot NAO consulta o sistema da loja. Sem regra propria
# o modelo improvisa um texto de central de atendimento ("nao tenho acesso ao nosso
# sistema de gerenciamento"), que soa falso para o cliente. Resposta fixa, editavel.
PEDIDO_RE = re.compile(
    r"(?i)(\bpedidos?\b|rastre\w*|rastreio|n[uú]mero do pedido|"
    r"c[oó]digo do pedido|previs[aã]o de (?:entrega|chegada))"
)
# "quero fazer um pedido" nao e consulta de status: e intencao de compra.
PEDIDO_FAZER_RE = re.compile(
    r"(?i)((?:quero|queria|gostaria|preciso|vou)\s+(?:fazer|montar|encomendar|pedir)|"
    r"fazer\s+um\s+pedido|quero\s+pedir|encomendar)"
)
# Frases que denunciam resposta robotica da IA: viram fallback, nunca vao ao cliente.
META_RE = re.compile(
    r"(?i)(n[aã]o\s+(?:tenho|possui?o|consigo)\s+acesso|sem\s+acesso\s+ao|"
    r"sistema\s+de\s+gerenciamento|n[aã]o\s+posso\s+(?:fornecer|informar|consultar)|"
    r"pedidos?\s+anteriores|retornarei\s+em\s+seguida)"
)

# --- escopo do nicho ---
# O bot so fala dos assuntos cadastrados em negocio.json -> "foco". O 3B responde de
# tudo quando ninguem o limita (num pet shop ele ja ofereceu "venda de animais"), entao
# mensagem que nao toca em nenhum assunto da lista NAO chega no modelo.
STRICT = os.getenv("BOT_STRICT", "0").strip().lower() not in ("0", "nao", "não", "false", "")
FORA_TEMA_TEXT = os.getenv(
    "BOT_FORA_TEMA",
    "Por aqui eu ajudo com {assuntos}. Sobre isso, quem pode te responder é a equipe.",
).strip()
SAUDACAO_TEXT = os.getenv("BOT_SAUDACAO", "Oi! Como posso ajudar?").strip()
AGRADECIMENTO_TEXT = os.getenv(
    "BOT_AGRADECIMENTO", "De nada! Qualquer coisa é só chamar por aqui."
).strip()
SAUDACAO_RE = re.compile(
    r"(?i)^\s*(oi+|ol[aá]|bom dia|boa tarde|boa noite|e a[ií]|opa|tudo bem|tudo bom|hey)"
)
AGRADECIMENTO_RE = re.compile(r"(?i)(obrigad|agradec|brigad|valeu|de nada)")
# Mensagem que cita um pet e assunto da loja, mesmo sem bater numa palavra do
# cadastro ("meu gato esta com pulga", "qual racao para filhote?").
PET_RE = re.compile(
    r"(?i)\b(cachorr\w*|cadel\w*|c[aã]o|c[aã]es|gato\w*|felino\w*|pet|pets|filhote\w*|"
    r"ave\w*|p[aá]ssaro\w*|peixe\w*|hamster\w*|coelh\w*|roedor\w*|aqu[aá]rio\w*)\b"
)
# Saude do animal: o bot nao opina nem indica remedio. Avisa e passa para a equipe.
SAUDE_RE = re.compile(
    r"(?i)(vomit\w*|diarr\w*|sangr\w*|doente|doen[cç]a|febre|intoxic\w*|envenen\w*|"
    r"convuls\w*|fratur\w*|atropel\w*|co[cç]and\w*|alergi\w*|cirurgi\w*|castra\w*|"
    r"gesta[cç][aã]o|prenh\w*)"
)
# Problema comum que a loja resolve com produto: busca no catalogo (antipulgas etc.).
PROBLEMA_RE = re.compile(
    r"(?i)(pulg\w*|carrapat\w*|verm[eê]\w*|sarna|micose|mau h[aá]lito|t[aá]rtaro)"
)
SAUDE_TEXT = os.getenv(
    "BOT_SAUDE_TEXT",
    "Sinto muito! Sobre a saúde do pet eu prefiro confirmar com a equipe antes de "
    "indicar qualquer coisa. Já avisei e alguém te responde por aqui.",
).strip()
# Quantidade/rotina de alimentacao: o modelo de 3B inventava ("pode dar todo dia").
# A loja vende, mas quem orienta dose e a equipe.
NUTRICAO_RE = re.compile(
    r"(?i)(?=.*(?:ra[cç][aã]o|sach[eê]|petisco|aliment\w*|dieta|comida))"
    r"(?=.*(?:pode|podem|posso|quant\w*|todo?s?\s+os\s+dias|diariamente|faz\s+bem|"
    r"[eé]\s+bom|recomend\w*|melhor))"
)
CONSELHO_TEXT = os.getenv(
    "BOT_CONSELHO_TEXT",
    "Sobre a quantidade e a rotina de alimentação, prefiro confirmar com a equipe: "
    "cada pet tem uma necessidade diferente. Já deixei sua dúvida registrada por aqui.",
).strip()
# Cuidados gerais ("como cuidar", "dicas", "e normal?"): o modelo de 3B inventava
# (chegou a recomendar banho e tosa em gato). Quem orienta e a equipe.
CUIDADO_RE = re.compile(
    r"(?i)(?=.*(?:cuidar|cuido|cuidado|dicas?|como\s+(?:criar|tratar|alimentar)|"
    r"o\s+que\s+(?:fazer|devo)|[eé]\s+normal))"
    r"(?=.*(?:pet|pets|gato|gatos|cachorro|cachorros|c[aã]o|c[aã]es|filhote|"
    r"ave|aves|peixe|peixes|hamster|coelho|roedor))"
)
CUIDADO_TEXT = os.getenv(
    "BOT_CUIDADO_TEXT",
    "Essa é uma dúvida que eu prefiro confirmar com a equipe antes de orientar. "
    "Já deixei registrada e alguém te responde por aqui.",
).strip()
# Tema da loja que ainda nao tem dado no negocio.json: em vez de deixar o modelo
# responder (e inventar), o bot ja assume que vai confirmar com a equipe.
TEMAS_ABERTOS_RE = re.compile(
    r"(?i)(pagamento|pagar|pix|cart[aã]o|dinheiro|d[eé]bito|cr[eé]dito|parcel\w*|\bboleto\b|"
    r"banho|tosa|vacina\w*|ra[cç][aã]o|petisco|servi[cç]o|entrega|entregam|frete|"
    r"agendamento|agendar|hor[aá]rio de (?:banho|tosa))"
)

# Substantivo de produto puro (sem verbo de compra): "coleira para gato",
# "areia sanicat", "shampoo cachorro". Dispara busca no catalogo antes do modelo.
ITEM_NOME_RE = re.compile(
    r"(?i)\b(coleira|ra[cç][aã]o|raca|areia|shampoo|sabonete|aqu[aá]rio|petisco|"
    r"brinquedo|medicamento|vacina|antipulgas|talco|comedouro|bebedouro|caminha|"
    r"arranhador|filtro|guia)\b"
)

def _tem_substantivo_produto(texto):
    """True se a mensagem cita um substantivo de produto real (nao apenas 'tem'/'vale')."""
    return bool(ITEM_NOME_RE.search(texto or ""))

HANDOFF_WORDS = [
    w.strip().lower()
    for w in os.getenv(
        "BOT_HANDOFF_WORDS",
        "atendente,humano,pessoa de verdade,falar com alguem,falar com alguém,reclamacao,"
        "reclamação,reembolso,gerente,dono,procon,processo,cancelar pedido",
    ).split(",")
    if w.strip()
]

history = defaultdict(lambda: deque(maxlen=MAX_HISTORY))
seen = deque(maxlen=800)
seen_set = set()
replies = defaultdict(list)
last_intro = {}
# Pausas por contato ficam em arquivo (volume) para sobreviver a restart do
# container ou da VM. Sem isso o bot voltaria a responder quem um humano assumiu.
STATE_FILE = os.getenv("BOT_STATE_FILE", "/data/state.json")
# Historico das perguntas reais, para o app mostrar onde o bot nao soube responder.
QUESTIONS_FILE = os.getenv("BOT_QUESTIONS_FILE", "/data/perguntas.jsonl")
QUESTIONS_MAX = int(os.getenv("BOT_QUESTIONS_MAX", "2000"))
questions_lock = threading.Lock()
muted_until = {}
# Pausa global do bot (0 = respondendo; infinito = pausado ate retomar).
paused_until_global = 0.0
bot_sent = deque(maxlen=300)  # ids das mensagens que ESTE bot enviou
bot_sent_set = set()
pending = {}
pending_lock = threading.Lock()
mute_lock = threading.Lock()


def log(msg):
    print(time.strftime("%Y-%m-%d %H:%M:%S"), msg, flush=True)


def http_json(url, payload=None, timeout=180):
    data = json.dumps(payload).encode() if payload is not None else None
    headers = {"Content-Type": "application/json"}
    if API_KEY:
        headers["apikey"] = API_KEY
    req = urllib.request.Request(
        url, data=data, headers=headers, method="POST" if data is not None else "GET"
    )
    with urllib.request.urlopen(req, timeout=timeout) as r:
        body = r.read().decode("utf-8", "replace")
    try:
        return json.loads(body)
    except json.JSONDecodeError:
        return body


def extract_text(data):
    msg = data.get("message")
    if not isinstance(msg, dict):
        return None
    for _ in range(3):
        if isinstance(msg.get("conversation"), str):
            return msg["conversation"]
        ext = msg.get("extendedTextMessage")
        if isinstance(ext, dict) and ext.get("text"):
            return ext["text"]
        inner = None
        for key in ("ephemeralMessage", "viewOnceMessageV2", "viewOnceMessage"):
            node = msg.get(key)
            if isinstance(node, dict) and isinstance(node.get("message"), dict):
                inner = node["message"]
                break
        if inner is None:
            return None
        msg = inner
    return None


def mark_seen(mid):
    if mid in seen_set:
        return False
    if len(seen) == seen.maxlen:
        seen_set.discard(seen[0])
    seen.append(mid)
    seen_set.add(mid)
    return True


def handoff_hit(text):
    low = text.lower()
    return any(w in low for w in HANDOFF_WORDS if w)


def within_rate(jid):
    now = time.time()
    stamps = [t for t in replies[jid] if now - t < 3600]
    replies[jid] = stamps
    return len(stamps) < MAX_REPLIES_HOUR


def in_active_hours():
    if not ACTIVE_HOURS or "-" not in ACTIVE_HOURS:
        return True
    try:
        start_s, end_s = ACTIVE_HOURS.split("-", 1)
        to_min = lambda s: int(s.split(":")[0]) * 60 + int(s.split(":")[1])
        start, end = to_min(start_s.strip()), to_min(end_s.strip())
    except (ValueError, IndexError):
        log(f"BOT_ACTIVE_HOURS invalido ({ACTIVE_HOURS}); tratando como 24h")
        return True
    now = time.localtime()
    cur = now.tm_hour * 60 + now.tm_min
    if start == end:
        return True
    if start < end:
        return start <= cur < end
    return cur >= start or cur < end  # janela que vira a noite


def prune_mutes(now=None):
    now = now or time.time()
    with mute_lock:
        for jid in [j for j, until in muted_until.items() if until <= now]:
            muted_until.pop(jid, None)


def load_state():
    """Recarrega as pausas salvas (chamado no boot do container)."""
    try:
        with open(STATE_FILE, encoding="utf-8") as f:
            data = json.load(f)
    except FileNotFoundError:
        log(f"sem estado salvo em {STATE_FILE} (primeiro boot)")
        return
    except (OSError, json.JSONDecodeError) as e:
        log(f"estado ilegivel em {STATE_FILE}: {type(e).__name__}")
        return
    global paused_until_global
    salvo_pausa = data.get("paused_until")
    if isinstance(salvo_pausa, (int, float)) and salvo_pausa > time.time():
        paused_until_global = float(salvo_pausa)
    saved = data.get("muted_until") or {}
    now = time.time()
    validos = 0
    with mute_lock:
        muted_until.clear()
        for jid, until in saved.items():
            if (
                isinstance(until, (int, float))
                and until > now
                and jid.endswith("@s.whatsapp.net")
            ):
                muted_until[jid] = float(until)
                validos += 1
    log(f"estado carregado: {validos} contato(s) em pausa (de {len(saved)} salvos)")


def save_state():
    """Grava as pausas de forma atomica (tmp + replace)."""
    prune_mutes()
    with mute_lock:
        snapshot = dict(muted_until)
    payload = {
        "saved_at": time.strftime("%Y-%m-%dT%H:%M:%S"),
        "muted_until": snapshot,
        "paused_until": paused_until_global,
    }
    tmp = f"{STATE_FILE}.tmp"
    try:
        directory = os.path.dirname(STATE_FILE)
        if directory:
            os.makedirs(directory, exist_ok=True)
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(payload, f, indent=2)
        os.replace(tmp, STATE_FILE)
    except OSError as e:
        log(f"falha ao salvar estado em {STATE_FILE}: {type(e).__name__}: {e}")


def _trim_questions():
    """Mantem o arquivo do tamanho combinado (guarda as mais recentes)."""
    try:
        with open(QUESTIONS_FILE, encoding="utf-8") as f:
            linhas = f.readlines()
        if len(linhas) <= QUESTIONS_MAX + QUESTIONS_MAX // 2:
            return
        with open(QUESTIONS_FILE, "w", encoding="utf-8") as f:
            f.writelines(linhas[-QUESTIONS_MAX:])
    except Exception as e:
        log(f"falha ao podar {QUESTIONS_FILE}: {type(e).__name__}: {e}")


def record_question(jid, name, text, answer, origem, detalhe, canal="whatsapp"):
    """Guarda a pergunta do cliente + como o bot respondeu.

    E o insumo do treino: no app da para filtrar o que caiu em fallback.
    """
    entrada = {
        "at": time.strftime("%Y-%m-%dT%H:%M:%S"),
        "jid": jid,
        "nome": (name or "")[:60],
        "pergunta": (text or "")[:500],
        "resposta": (answer or "")[:500],
        "origem": origem,
        "regra": (detalhe or "")[:120],
        "canal": canal,
    }
    try:
        with questions_lock:
            with open(QUESTIONS_FILE, "a", encoding="utf-8") as f:
                f.write(json.dumps(entrada, ensure_ascii=False) + "\n")
            _trim_questions()
    except Exception as e:
        log(f"falha ao gravar pergunta: {type(e).__name__}: {e}")


def load_questions(limite=50, somente_falhas=False):
    """Devolve as ultimas perguntas (mais recentes primeiro) + contadores."""
    falhas = (
        "fallback_preco",
        "fallback_valor",
        "fallback_fato",
        "pedido",
        "fora_tema",
        "erro_ollama",
        "vazio",
        "catalogo_vazio",
        "saude",
        "conselho",
        "cuidado",
    )
    entradas = []
    contagem = {}
    try:
        with questions_lock:
            with open(QUESTIONS_FILE, encoding="utf-8") as f:
                linhas = f.readlines()
    except FileNotFoundError:
        linhas = []
    except Exception as e:
        log(f"falha ao ler {QUESTIONS_FILE}: {type(e).__name__}: {e}")
        linhas = []
    for linha in linhas:
        linha = linha.strip()
        if not linha:
            continue
        try:
            item = json.loads(linha)
        except json.JSONDecodeError:
            continue
        if item.get("canal") == "app":
            continue  # teste pelo app nao e conversa de cliente
        origem = item.get("origem") or "?"
        contagem[origem] = contagem.get(origem, 0) + 1
        if somente_falhas and origem not in falhas and origem != "handoff":
            continue
        entradas.append(item)
    entradas.reverse()
    return entradas[:limite], contagem, len(linhas)


def is_globally_paused():
    return time.time() < paused_until_global


def set_global_pause(minutes):
    """minutes <= 0 pausa ate retomar; > 0 pausa por N minutos."""
    global paused_until_global
    paused_until_global = float("inf") if minutes <= 0 else time.time() + minutes * 60
    save_state()
    log(f"bot PAUSADO ({'ate retomar' if minutes <= 0 else f'{minutes} min'})")


def resume_bot():
    global paused_until_global
    paused_until_global = 0.0
    save_state()
    log("bot RETOMADO")


def mute_for(jid, minutes, reason):
    if minutes <= 0:
        return
    with mute_lock:
        muted_until[jid] = time.time() + minutes * 60
    save_state()
    log(f"pausado {jid} por {minutes} min ({reason})")


def is_muted(jid):
    with mute_lock:
        until = muted_until.get(jid)
        if not until:
            return False
        if until <= time.time():
            muted_until.pop(jid, None)
            return False
        return True


def load_prompt():
    """Prompt ativo: arquivo (relido a cada mudanca) > BOT_PROMPT > padrao."""
    if PROMPT_FILE:
        try:
            mtime = os.path.getmtime(PROMPT_FILE)
            if mtime != _prompt_cache["mtime"]:
                with open(PROMPT_FILE, encoding="utf-8") as f:
                    _prompt_cache["text"] = f.read().strip()
                _prompt_cache["mtime"] = mtime
                log(f"prompt recarregado de {PROMPT_FILE} ({len(_prompt_cache['text'])} chars)")
            if _prompt_cache["text"]:
                return _fill(_prompt_cache["text"])
        except OSError as e:
            log(f"prompt: falha ao ler {PROMPT_FILE} ({type(e).__name__}); usando .env/padrao")
    if PROMPT_INLINE:
        return _fill(PROMPT_INLINE.replace("\\n", "\n"))
    return _fill(DEFAULT_PROMPT)


def load_config():
    """Le o negocio.json (recarregado quando muda). Vazio = sem dados da loja."""
    if not CONFIG_FILE:
        return {}
    try:
        mtime = os.path.getmtime(CONFIG_FILE)
        if mtime != _config_cache["mtime"]:
            with open(CONFIG_FILE, encoding="utf-8") as f:
                _config_cache["data"] = json.load(f)
            _config_cache["mtime"] = mtime
            log(f"config da loja recarregada de {CONFIG_FILE}")
        return _config_cache["data"] or {}
    except (OSError, json.JSONDecodeError) as e:
        log(f"config: falha ao ler {CONFIG_FILE} ({type(e).__name__}); seguindo sem dados")
        return {}


def _join(items):
    itens = [str(i).strip() for i in (items or []) if str(i).strip()]
    if not itens:
        return ""
    if len(itens) == 1:
        return itens[0]
    return ", ".join(itens[:-1]) + " e " + itens[-1]


def fact_answers(cfg):
    """(regex, texto) gerados do negocio.json. Respondidos sem modelo."""
    regras = []
    horario = cfg.get("horario") or {}
    rotulos = [
        ("segunda_a_sexta", "de segunda a sexta"),
        ("sabado", "sabado"),
        ("domingo", "domingo"),
        ("feriados", "feriados"),
    ]
    partes = [
        f"{rotulo} {str(horario.get(chave) or '').strip()}"
        for chave, rotulo in rotulos
        if str(horario.get(chave) or "").strip()
    ]
    # `horario.texto` tem prioridade: frase pronta, para nao sair repetitivo
    # quando todos os dias sao iguais.
    texto_horario = str(horario.get("texto") or "").strip()
    if texto_horario:
        partes = [texto_horario.rstrip(".")]
    if partes:
        if texto_horario:
            frase = texto_horario if texto_horario.endswith(".") else texto_horario + "."
        else:
            frase = "Nosso horario de atendimento: " + "; ".join(partes) + "."
        regras.append(
            (
                r"(?i)(hor[aá]rio|que horas|a que hora|abre|abrem|fecha|fecham|funciona\w*|aberto)",
                frase,
            )
        )
    endereco = str(cfg.get("endereco") or "").strip()
    if endereco:
        regras.append(
            (
                r"(?i)(endere[cç]o|onde fica|onde voces|localiza\w*|como chego|ponto de refer[eê]ncia)",
                f"Estamos em {endereco}.",
            )
        )
    pagamentos = cfg.get("formas_pagamento") or []
    if _join(pagamentos):
        regras.append(
            (
                r"(?i)(pagamento|pagar|pix|cart[aã]o(?!\s+fidelidade)|dinheiro|d[eé]bito|"
                r"cr[eé]dito|parcel\w*)",
                f"Aceitamos {_join(pagamentos)}.",
            )
        )
    servicos = cfg.get("servicos") or []
    detalhes = [
        str(d).strip() for d in (cfg.get("servicos_detalhes") or []) if str(d).strip()
    ]
    if detalhes:
        # Preco de servico so existe se o dono cadastrou; sem isso, a regra abaixo
        # responde apenas quais servicos a loja faz.
        regras.append(
            (
                r"(?i)(?=.*(?:servi[cç]o|banho|tosa|vacin\w*|taxi))"
                r"(?:quanto\s+(?:custa|custam|sai|fica)|pre[cç]o|valor)",
                " ".join(detalhes),
            )
        )
    if _join(servicos):
        regras.append(
            (
                r"(?i)(servi[cç]os?|\bbanho\b|\btosa\b|vacin\w*|taxi\s*dog)",
                f"Oferecemos {_join(servicos)}.",
            )
        )
    entrega = str(cfg.get("entrega") or "").strip()
    if entrega:
        regras.append(
            (
                r"(?i)(entrega|entregam|frete|taxa de entrega|levam|delivery)",
                entrega if entrega.endswith(".") else entrega + ".",
            )
        )
    # Respostas extras livres: {"palavra-gatilho": "texto exato"}
    for chave, texto in (cfg.get("respostas") or {}).items():
        if str(texto or "").strip() and str(chave).strip():
            regras.append((r"(?i)(" + re.escape(str(chave).strip()) + ")", str(texto).strip()))
    return regras


def fact_reply(cfg, text):
    """Se a mensagem pede um dado que temos, devolve o texto exato do arquivo."""
    for pattern, resposta in fact_answers(cfg):
        if re.search(pattern, text):
            return resposta, pattern
    return None, None


def _fill(text):
    """Troca {empresa} pelo nome configurado (sem .format, para nao quebrar em { })."""
    return (text or "").replace("{empresa}", EMPRESA_NOME)


def _norm(texto):
    """Minusculas e sem acento: a comparacao nao depende de como o cliente grafou."""
    base = unicodedata.normalize("NFKD", str(texto or "").lower())
    return "".join(c for c in base if not unicodedata.combining(c))


def _casa_palavra(termo, palavra):
    """venda ~ vendem, entrega ~ entregam: igual, contido ou mesmo comeco (4+ letras)."""
    a, b = _norm(termo), _norm(palavra)
    if not a or not b:
        return False
    # Palavra curta ("o", "de") nao pode casar por conter: so se for igualzinha.
    if len(a) < 4 or len(b) < 4:
        return a == b and len(a) >= 3
    if a in b or b in a:
        return True
    comum = 0
    for x, y in zip(a, b):
        if x != y:
            break
        comum += 1
    return comum >= 4


def _casa_termo(termo, texto, todas=True):
    """Termo do cadastro x mensagem do cliente.

    todas=True (bloqueios): "venda de animais" precisa das duas palavras.
    todas=False (assuntos): "banho e tosa" basta uma (banho OU tosa).
    """
    alvo = _norm(termo)
    corpo = _norm(texto)
    if not alvo:
        return False
    if alvo in corpo:
        return True
    ignorar = ("dos", "das", "com", "para", "por", "que")
    partes = [p for p in re.split(r"[^0-9a-z]+", alvo) if len(p) > 2 and p not in ignorar]
    if not partes:
        return False
    palavras = [p for p in re.split(r"[^0-9a-z]+", corpo) if p]
    casar = lambda parte: any(_casa_palavra(parte, w) for w in palavras)
    return all(casar(p) for p in partes) if todas else any(casar(p) for p in partes)


def _casa_assunto(termo, texto):
    """Assunto do nicho x mensagem, sem exagerar no casamento.

    'entrega' casa com 'entregam', mas 'racao' NAO casa com 'racas' — com o casamento
    frouxo, pergunta de raca de cachorro passava como assunto da loja.
    """
    alvo = _norm(termo)
    corpo = _norm(texto)
    if not alvo:
        return False
    if alvo in corpo:
        return True
    ignorar = ("dos", "das", "com", "para", "por", "que")
    partes = [p for p in re.split(r"[^0-9a-z]+", alvo) if len(p) > 2 and p not in ignorar]
    palavras = [p for p in re.split(r"[^0-9a-z]+", corpo) if p]

    def casar(parte):
        for w in palavras:
            if w == parte:
                return True
            if len(parte) >= 4 and (w.startswith(parte) or parte.startswith(w)):
                return True
        return False

    return any(casar(p) for p in partes)


def _dsn_partes(dsn):
    """Separa postgresql://usuario:senha@host:porta/banco em campos."""
    from urllib.parse import parse_qs, unquote, urlparse

    p = urlparse(dsn)
    consulta = parse_qs(p.query)
    return {
        "user": unquote(p.username or ""),
        "password": unquote(p.password or ""),
        "host": p.hostname or "",
        "port": p.port or 5432,
        "database": (p.path or "/").lstrip("/"),
        "sslmode": (consulta.get("sslmode") or [""])[0].lower(),
    }


def _descreve_status(status):
    chave = _norm(status or "").strip()
    if not chave:
        return "está sem status no sistema"
    for termo, texto in PEDIDO_STATUS:
        if termo == chave or termo in chave or chave in termo:
            return texto
    return f'está como "{status}"'


def _brl(valor):
    """1234.5 -> 'R$ 1.234,50' (o formato que o cliente espera no WhatsApp)."""
    try:
        numero = float(valor)
    except (TypeError, ValueError):
        return None
    texto = f"{numero:,.2f}".replace(",", "X").replace(".", ",").replace("X", ".")
    return "R$ " + texto


def _numeros(texto):
    """Valores com centavos, normalizados: serve para conferir preco do modelo."""
    return {n.replace(",", ".") for n in re.findall(r"\d+[.,]\d{2}", texto or "")}


def _data_curta(valor):
    """datetime -> '23/11'. Aceita string/None sem quebrar."""
    try:
        return valor.strftime("%d/%m")
    except (AttributeError, ValueError):
        return ""


def _formata_pedidos(pedidos):
    itens = []
    for p in pedidos:
        numero = (p.get("numero") or "").strip() or "sem número"
        parte = f"{numero} {_descreve_status(p.get('status'))}"
        data = _data_curta(p.get("data_pedido"))
        if data:
            parte += f" (de {data})"
        try:
            total = float(p.get("total") or p.get("valor_total") or 0)
        except (TypeError, ValueError):
            total = 0.0
        if total > 0:
            parte += f", no valor de {_brl(total)}"
        itens.append(parte)
    if len(itens) == 1:
        return f"Achei aqui: seu pedido {itens[0]}."
    return "Achei estes pedidos no seu número: " + "; ".join(itens) + ". Qual deles?"



def consultar_pedidos(jid, text):
    """Pedidos do proprio numero que escreveu (nunca de outro cliente).

    Devolve lista de {"numero", "status"} ou None quando nao ha como consultar
    (sem DSN, sem driver, banco fora). Nunca levanta excecao: em duvida, o bot
    cai no texto de "vou confirmar com a equipe".
    """
    if not PEDIDOS_DSN:
        return None
    digitos = re.sub(r"\D", "", (jid or "").split("@")[0])
    if len(digitos) < 10:
        return None
    try:
        import pg8000.native
    except ImportError:
        log("pg8000 ausente: consulta de pedidos desligada")
        return None
    partes = _dsn_partes(PEDIDOS_DSN)
    sql = (
        "SELECT numero, status, total, data_pedido FROM pedidos "
        "WHERE regexp_replace(coalesce(cliente_telefone, ''), '[^0-9]', '', 'g') LIKE :tel "
    )
    params = {"tel": "%" + digitos[-8:], "limite": max(1, PEDIDOS_MAX)}
    # Se o cliente citou o numero do pedido, usa como filtro extra (sempre do numero dele).
    citado = re.search(r"(?i)\bped[-\s]?(\d{1,6})\b", text or "")
    if citado:
        sql += "AND numero ILIKE :num "
        params["num"] = "%" + citado.group(1) + "%"
    sql += "ORDER BY data_pedido DESC LIMIT :limite"
    try:
        import pg8000.native

        extra = {}
        if partes["sslmode"] in ("require", "verify-ca", "verify-full"):
            import ssl

            extra["ssl_context"] = ssl.create_default_context()
        conn = pg8000.native.Connection(
            user=partes["user"],
            password=partes["password"],
            host=partes["host"],
            port=partes["port"],
            database=partes["database"],
            timeout=PEDIDOS_TIMEOUT,
            **extra,
        )
        try:
            conn.run("SET statement_timeout = '5s'")
            linhas = conn.run(sql, **params)
            colunas = [c["name"] for c in (conn.columns or [])]
        finally:
            conn.close()
    except Exception as e:
        log(f"consulta de pedidos falhou: {type(e).__name__}: {e}")
        return None
    return [dict(zip(colunas, linha)) for linha in linhas]


# ---------------------------------------------------------------------------
# Catalogo de produtos
# ---------------------------------------------------------------------------
# O modelo 3B nao tem como decorar 6 mil itens (e preco muda todo dia). Entao o
# catalogo vive no banco e e consultado por busca normalizada: nome, grupo e
# sinonimos. O que sai daqui e sempre dado real; o modelo so entra depois, para
# frases que nenhuma regra cobre.
_catalogo = {"at": 0.0, "itens": [], "grupos": [], "erro": ""}
_catalogo_lock = threading.Lock()

PALAVRAS_VAZIAS = {
    "tem", "temos", "teria", "teriam", "ter", "vcs", "voces", "voce", "vc", "queria",
    "quero", "gostaria", "saber", "qual", "quais", "quanto", "quantos", "quanta",
    "custa", "custam", "preco", "precos", "valor", "valores", "de", "da", "do", "das",
    "dos", "para", "pra", "por", "com", "sem", "um", "uma", "uns", "umas", "o", "a",
    "os", "as", "e", "ou", "em", "no", "na", "nos", "nas", "meu", "minha", "seu",
    "sua", "ai", "aqui", "hoje", "agora", "favor", "oi", "ola", "bom", "dia", "boa",
    "tarde", "noite", "tudo", "bem", "obrigado", "obrigada", "existe", "existem",
    "vende", "vendem", "vender", "trabalha", "trabalham", "oferece", "oferecem",
    "produto", "produtos", "item", "itens", "opcao", "opcoes", "disponivel",
    "disponiveis", "estoque", "marca", "modelo", "tipo", "kit", "unidade", "que",
    "esta", "estao", "estou", "estamos", "sou", "sao", "era", "foi", "ser", "sendo",
    "tinha", "vai", "vou", "pode", "posso", "preciso", "precisa", "muito", "mais",
    "menos", "sobre", "onde", "quando", "como", "porque", "recomenda", "recomendam",
    "indicam", "indica", "sugere", "sugerem", "melhor", "boa", "bom", "aqui",
}
# Variacoes irregulares (o casamento por comeco de palavra ja resolve plural).
SINONIMOS = {
    "cao": ("caes", "cachorro", "cachorros"),
    "caes": ("cao", "cachorro", "cachorros"),
    "cachorro": ("cao", "caes", "cachorros"),
    "cachorros": ("cao", "caes", "cachorro"),
    "gato": ("gatos", "felino"),
    "gatos": ("gato", "felinos"),
    "peixe": ("aquario", "aquarismo"),
    "passaro": ("ave", "aves"),
    "roedor": ("hamster", "coelho", "porquinho"),
    "pulga": ("antipulgas", "pulgas"),
    "pulgas": ("antipulgas", "pulga"),
    "carrapato": ("antipulgas", "carrapaticida"),
    "verme": ("vermifugo", "vermifugos"),
    "remedio": ("medicamento", "medicamentos", "vermifugo", "antipulgas"),
    "antibiotico": ("medicamento", "medicamentos"),
}


def _catalogo_carregar(forcar=False):
    """Devolve a lista de produtos, recarregando do banco a cada CATALOGO_TTL.

    Nunca levanta excecao: sem banco o bot continua respondendo o resto (e o
    catalogo simplesmente nao e usado).
    """
    if not CATALOGO_DSN:
        return []
    agora = time.time()
    if not forcar and _catalogo["itens"] and agora - _catalogo["at"] < CATALOGO_TTL:
        return _catalogo["itens"]
    if not _catalogo_lock.acquire(blocking=False):
        return _catalogo["itens"]  # outra thread esta recarregando
    try:
        if not forcar and _catalogo["itens"] and time.time() - _catalogo["at"] < CATALOGO_TTL:
            return _catalogo["itens"]
        try:
            import pg8000.native
        except ImportError:
            _catalogo["erro"] = "pg8000 ausente"
            _catalogo["at"] = time.time()
            return []
        partes = _dsn_partes(CATALOGO_DSN)
        sql = (
            "SELECT nome, grupo, subgrupo, preco, preco_promocional, tem_promocao, estoque "
            "FROM produtos WHERE ativo IS NOT FALSE AND coalesce(nome, '') <> ''"
        )
        params = {}
        if CATALOGO_EMPRESA:
            sql += " AND empresa_id = :empresa"
            params["empresa"] = CATALOGO_EMPRESA
        sql += " ORDER BY nome"
        extra = {}
        if partes["sslmode"] in ("require", "verify-ca", "verify-full"):
            import ssl

            extra["ssl_context"] = ssl.create_default_context()
        conn = pg8000.native.Connection(
            user=partes["user"],
            password=partes["password"],
            host=partes["host"],
            port=partes["port"],
            database=partes["database"],
            timeout=PEDIDOS_TIMEOUT,
            **extra,
        )
        try:
            conn.run("SET statement_timeout = '10s'")
            linhas = conn.run(sql, **params)
            colunas = [c["name"] for c in (conn.columns or [])]
        finally:
            conn.close()
        itens = []
        grupos = {}
        for linha in linhas:
            dado = dict(zip(colunas, linha))
            nome = str(dado.get("nome") or "").strip()
            if not nome:
                continue
            grupo = str(dado.get("grupo") or "").strip()
            subgrupo = str(dado.get("subgrupo") or "").strip()
            try:
                preco = float(dado.get("preco") or 0)
            except (TypeError, ValueError):
                preco = 0.0
            promo = None
            if dado.get("tem_promocao"):
                try:
                    promo = float(dado.get("preco_promocional") or 0) or None
                except (TypeError, ValueError):
                    promo = None
            try:
                estoque = float(dado.get("estoque") or 0)
            except (TypeError, ValueError):
                estoque = 0.0
            chave_grupo = _norm(grupo) or "sem grupo"
            grupos[chave_grupo] = grupos.get(chave_grupo, 0) + 1
            palavras = set(
                p for p in re.split(r"[^0-9a-z]+", _norm(nome)) if len(p) >= 3
            )
            itens.append(
                {
                    "nome": nome,
                    "grupo": grupo,
                    "subgrupo": subgrupo,
                    "preco": preco,
                    "promo": promo,
                    "estoque": estoque,
                    "palavras": palavras,
                    "animais": _animais(palavras),
                    "grupo_norm": chave_grupo + " " + _norm(subgrupo),
                }
            )
        _catalogo.update(
            {
                "at": time.time(),
                "itens": itens,
                "grupos": [
                    {"nome": g, "total": n}
                    for g, n in sorted(grupos.items(), key=lambda kv: -kv[1])
                ],
                "erro": "",
            }
        )
        log(f"catalogo carregado: {len(itens)} produto(s), {len(grupos)} grupo(s)")
        return itens
    except Exception as e:
        _catalogo["at"] = time.time()  # evita tentar de novo a cada mensagem
        _catalogo["erro"] = f"{type(e).__name__}: {e}"
        log(f"catalogo indisponivel: {_catalogo['erro']}")
        return _catalogo["itens"]
    finally:
        _catalogo_lock.release()


def _catalogo_termos(texto):
    """Tokens uteis da mensagem (sem saudacao/verbo de compra), com sinonimos."""
    tokens = [
        t
        for t in re.split(r"[^0-9a-z]+", _norm(texto))
        if len(t) >= 3 and t not in PALAVRAS_VAZIAS
    ]
    alvo = []
    for t in tokens:
        alvo.append(t)
        alvo.extend(SINONIMOS.get(t, ()))
    return list(dict.fromkeys(alvo))


def _catalogo_grupos_termos(texto):
    """Cada palavra da mensagem vira um grupo (palavra + sinonimos)."""
    tokens = [
        t
        for t in re.split(r"[^0-9a-z]+", _norm(texto))
        if len(t) >= 3 and t not in PALAVRAS_VAZIAS
    ]
    grupos = []
    for t in tokens:
        grupo = list(dict.fromkeys([t, *SINONIMOS.get(t, ())]))
        if grupo not in grupos:
            grupos.append(grupo)
    return grupos


# Especie citada na mensagem x produto: evita devolver racao de peixe para quem
# pediu racao de cachorro (o casamento so por palavra fazia exatamente isso).
ANIMAIS = {
    "cao": ("cao", "caes", "cachorro", "cachorros", "cadelinha", "dog", "dogs", "canina", "canino"),
    "gato": ("gato", "gatos", "felino", "felinos"),
    "peixe": ("peixe", "peixes", "aquario", "aquarismo", "betta", "goldfish", "tartaruga"),
    "ave": ("ave", "aves", "passaro", "passaros", "calopsita", "periquito", "papagaio"),
    "roedor": ("roedor", "roedores", "hamster", "coelho", "coelhos", "porquinho", "gerbil"),
}


def _animais(palavras):
    return {a for a, termos in ANIMAIS.items() if any(t in palavras for t in termos)}


TERMOS_ANIMAIS = {t for termos in ANIMAIS.values() for t in termos}


def _catalogo_buscar(texto, limite=None, sem_animais=False):
    """Produtos cujo NOME casa com a mensagem, do mais relevante ao menos.

    sem_animais=True serve para problema ("meu gato esta com pulga"): a especie e
    so contexto, o que importa e o produto (antipulgas) — senao so apareceria o
    que tem "gato" no nome.
    """
    limite = limite or CATALOGO_MAX
    itens = _catalogo_carregar()
    if not itens:
        return []
    grupos = _catalogo_grupos_termos(texto)
    if sem_animais:
        grupos = [
            g
            for g in grupos
            if not any(t in TERMOS_ANIMAIS for t in g)
        ]
    if not grupos:
        return []
    quer_animal = _animais({t for g in grupos for t in g})
    achados = []
    for it in itens:
        # Espécie diferente da pedida fica fora (produto sem espécie entra normal).
        if quer_animal and it["animais"] and not (quer_animal & it["animais"]):
            continue
        acertos = 0
        pontos = 0
        for grupo in grupos:
            melhor = 0
            for termo in grupo:
                if termo in it["palavras"]:
                    melhor = 3
                    break
                if len(termo) >= 4 and any(p.startswith(termo) for p in it["palavras"]):
                    melhor = max(melhor, 2)
            if not melhor:
                # Nome do produto nao repete a categoria ("Golden Gatos Castrados"
                # nao diz "racao"); o grupo diz. Vale menos, mas conta como acerto.
                for termo in grupo:
                    if len(termo) >= 4 and termo in it["grupo_norm"]:
                        melhor = 1
                        break
            if melhor:
                acertos += 1
                pontos += melhor
        if pontos:
            achados.append((acertos, pontos, it))
    if not achados:
        return []
    todos = sorted(
        achados, key=lambda x: (-x[0], -x[1], -x[2]["estoque"], x[2]["nome"])
    )
    melhor_acertos = max(a for a, _p, _i in achados)
    # Quando a mensagem tem mais de uma palavra, fica so quem casa com todas
    # (ex.: "areia pipicat" nao devolve Mimocat/Kets).
    if melhor_acertos >= 2:
        achados = [x for x in todos if x[0] == melhor_acertos]
    else:
        achados = list(todos)
    vistos = set()
    resultado = []
    for _a, _p, it in achados:
        chave = _norm(it["nome"])
        if chave in vistos:
            continue
        vistos.add(chave)
        resultado.append(it)
        if len(resultado) >= limite:
            break
    return resultado


def _catalogo_categoria(texto, limite=None):
    """Itens de um grupo quando o cliente cita a categoria (ex.: 'pesca')."""
    limite = limite or CATALOGO_MAX
    itens = _catalogo_carregar()
    if not itens:
        return []
    alvo = _catalogo_termos(texto)
    if not alvo:
        return []
    achados = []
    for it in itens:
        if any(t in it["grupo_norm"] for t in alvo):
            achados.append(it)
    achados.sort(key=lambda it: (-it["estoque"], it["nome"]))
    return achados[:limite]


def _preco_texto(it):
    valor = it["promo"] if it["promo"] else it["preco"]
    texto = _brl(valor)
    if not texto or valor <= 0:
        return ""
    if it["promo"] and it["preco"] > it["promo"]:
        return f"{texto} (promoção, de {_brl(it['preco'])})"
    return texto


def _formata_catalogo(itens):
    partes = []
    for it in itens:
        preco = _preco_texto(it)
        nome = it["nome"]
        if preco:
            partes.append(f"{nome} por {preco}")
        else:
            partes.append(nome)
    if len(partes) == 1:
        texto = "Temos " + partes[0] + "."
    else:
        texto = "Temos: " + "; ".join(partes) + "."
    sem_estoque = [it["nome"] for it in itens if it["estoque"] <= 0]
    if len(sem_estoque) == len(itens):
        texto += " No momento está em falta, mas posso confirmar com a equipe."
    elif sem_estoque:
        texto += " O item " + sem_estoque[0] + " está em falta no momento."
    else:
        texto += " Quer algum desses?"
    return texto


def _catalogo_resumo(cfg):
    """Frase de 'o que a loja tem' montada a partir dos grupos reais do banco."""
    _catalogo_carregar()
    cat = cfg.get("catalogo") or {}
    if not isinstance(cat, dict):
        cat = {}
    grupos = _catalogo["grupos"]
    mapa = {
        _norm(str(k)): str(v).strip() for k, v in (cat.get("categorias") or {}).items()
    }
    minimo = int(cat.get("minimo_grupo") or 10)
    rotulos = []
    for g in grupos:
        if g["total"] < minimo:
            continue
        rotulos.append(mapa.get(g["nome"], g["nome"]))
    if not rotulos:
        return ""
    resumo = str(cat.get("resumo") or "").strip() or CATALOGO_RESUMO
    return resumo.replace("{categorias}", _join(rotulos[:8]))


def _catalogo_quer_ver(texto):
    """'o que voces tem/vendem/oferecem' -> quer o panorama, nao um item."""
    return bool(
        re.search(
            r"(?i)(o que\s+(?:voc[eê]s?\s+)?(?:t[eê]m|vendem|oferecem|trabalham)|"
            r"quais\s+(?:produtos|itens|op[cç][oõ]es)|cat[aá]logo|"
            r"o que\s+tem\s+(?:a[ií]|na loja|de bom)|trabalham com o qu[eê])",
            texto or "",
        )
    )


def _catalogo_quer_item(texto):
    """Pergunta por item/preco ('tem racao?', 'quanto custa a areia?')."""
    return bool(
        re.search(
            r"(?i)(\btem\b|\bt[eê]m\b|\bvende\w*\b|\bteria\w*\b|\bquanto\s+(?:custa|custam|sai|fica)\b|"
            r"\bpre[cç]o\b|\bvalor\b|\bprocuro\b|\bprocurando\b|\bqueria\b|\bquero\b|\bcomprar\b|"
            r"\brecomenda\w*\b|\bindica\w*\b|\bsugere\w*\b|\btrabalha\w*\s+com\b)",
            texto or "",
        )
    )


def foco_config(cfg):
    """(assuntos do nicho, bloqueios, texto de fora do tema) de negocio.json -> "foco"."""
    foco = cfg.get("foco") or {}
    if not isinstance(foco, dict):
        foco = {}
    assuntos = [str(a).strip() for a in (foco.get("assuntos") or []) if str(a).strip()]
    bloqueios = {}
    for gatilho, resposta in (foco.get("bloqueios") or {}).items():
        if str(gatilho).strip() and str(resposta).strip():
            bloqueios[str(gatilho).strip()] = str(resposta).strip()
    fora = str(foco.get("fora_do_tema") or "").strip() or FORA_TEMA_TEXT
    return assuntos, bloqueios, fora


def nao_mencionar_config(cfg):
    """Palavras que a IA nunca pode afirmar (ex.: 'animal', 'catalogo').

    Vale so para o que o MODELO escreve: o cliente pode perguntar o que quiser.
    """
    foco = cfg.get("foco") or {}
    if not isinstance(foco, dict):
        return []
    return [str(t).strip() for t in (foco.get("nao_mencionar") or []) if str(t).strip()]


def _texto_fora(assuntos, fora):
    if "{assuntos}" in fora:
        fora = fora.replace("{assuntos}", _join(assuntos) if assuntos else "seu pedido")
    return fora


def _dados_oficiais(cfg):
    """Tudo o que a loja cadastrou, em texto, para o modelo nao ter o que inventar."""
    linhas = []
    horario = cfg.get("horario") or {}
    if isinstance(horario, dict) and str(horario.get("texto") or "").strip():
        linhas.append("Horario de atendimento: " + str(horario["texto"]).strip())
    if str(cfg.get("endereco") or "").strip():
        linhas.append("Endereco: " + str(cfg["endereco"]).strip())
    if _join(cfg.get("formas_pagamento") or []):
        linhas.append("Formas de pagamento: " + _join(cfg.get("formas_pagamento") or []))
    if _join(cfg.get("servicos") or []):
        linhas.append("Servicos: " + _join(cfg.get("servicos") or []))
    if str(cfg.get("entrega") or "").strip():
        linhas.append("Entrega: " + str(cfg["entrega"]).strip())
    if str(cfg.get("pedido") or "").strip():
        linhas.append("Pedidos: " + str(cfg["pedido"]).strip())
    assuntos, bloqueios, _fora = foco_config(cfg)
    if assuntos:
        linhas.append("Assuntos que a loja atende: " + _join(assuntos))
    if bloqueios:
        linhas.append(
            "Nao trabalhamos com: " + _join(list(bloqueios.keys())) + "."
        )
    return "\n".join(linhas)


# --- parametros do modelo ---
# Temperatura baixa + seed fixa = mesma pergunta tende a gerar a mesma resposta.
# O modelo fraco nao tem "criatividade util" aqui: ele so precisa redigir.
NUM_CTX = int(os.getenv("BOT_NUM_CTX", "3072"))
NUM_PREDICT = int(os.getenv("BOT_NUM_PREDICT", "90"))
# 0 = CPU (2 GB de VRAM nao comportam o 3B inteiro). -1 deixa o Ollama decidir.
NUM_GPU = int(os.getenv("BOT_NUM_GPU", "0"))
TEMPERATURE = float(os.getenv("BOT_TEMPERATURE", "0.1"))
TOP_P = float(os.getenv("BOT_TOP_P", "0.8"))
TOP_K = int(os.getenv("BOT_TOP_K", "20"))
REPEAT_PENALTY = float(os.getenv("BOT_REPEAT_PENALTY", "1.15"))
SEED = int(os.getenv("BOT_SEED", "42"))
KEEP_ALIVE = os.getenv("BOT_KEEP_ALIVE", "24h")
# Mantem o modelo carregado na memoria (o cold start leva 20-30 s).
WARMUP = os.getenv("BOT_WARMUP", "1").strip().lower() not in ("0", "nao", "não", "false")
WARMUP_INTERVAL = int(os.getenv("BOT_WARMUP_INTERVAL", "60"))


def _model_options():
    return {
        "temperature": TEMPERATURE,
        "top_p": TOP_P,
        "top_k": TOP_K,
        "repeat_penalty": REPEAT_PENALTY,
        "seed": SEED,
        "num_ctx": NUM_CTX,
        "num_predict": NUM_PREDICT,
        "num_gpu": NUM_GPU,
    }


def _contexto_catalogo(text):
    """Os produtos que a mensagem cita, com preco real, para o modelo so redigir."""
    itens = _catalogo_buscar(text, limite=8)
    if not itens:
        return ""
    linhas = []
    for it in itens:
        preco = _preco_texto(it)
        linha = "- " + it["nome"]
        if preco:
            linha += f": {preco}"
        if it["estoque"] <= 0:
            linha += " (em falta)"
        linhas.append(linha)
    return "\n".join(linhas)


def ask_model(jid, text):
    cfg = load_config()
    msgs = list(history[jid])
    prompt = load_prompt()
    if prompt:
        msgs.insert(0, {"role": "system", "content": prompt})
    dados = _dados_oficiais(cfg)
    if EXTRA_INFO:
        dados = (dados + "\n" + EXTRA_INFO).strip()
    if dados:
        msgs.insert(
            0,
            {
                "role": "system",
                "content": "Informacoes oficiais da loja. Fale so do que esta nesta lista, "
                "nunca invente produto, servico, preco, prazo ou horario, e nao ofereca nada "
                "que nao esteja aqui (se pedirem algo fora da lista, diga que vai confirmar "
                "com a equipe):\n" + dados,
            },
        )
    catalogo = _contexto_catalogo(text)
    if catalogo:
        msgs.insert(
            0,
            {
                "role": "system",
                "content": "Produtos do catalogo que combinam com a mensagem (dados reais do "
                "sistema; use no maximo dois e nao altere nome nem preco):\n" + catalogo,
            },
        )
    msgs.append({"role": "user", "content": text})
    payload = {
        "model": MODEL,
        "stream": False,
        "keep_alive": KEEP_ALIVE,
        "messages": msgs,
        "options": _model_options(),
    }
    started = time.time()
    out = http_json(f"{OLLAMA_URL}/api/chat", payload, timeout=240)
    answer = ((out or {}).get("message") or {}).get("content", "").strip()
    took = time.time() - started
    if answer:
        history[jid].append({"role": "user", "content": text})
        history[jid].append({"role": "assistant", "content": answer})
    return answer, took


def warmup_loop():
    """Mantem o modelo carregado e aquecido.

    Sem isso, a primeira mensagem depois de um tempo parado paga 20-30 s de
    carga do modelo. Um ping a cada BOT_WARMUP_INTERVAL segundos (padrao 60s)
    mantem o processo quente sem gastar CPU de verdade.
    """
    payload = {
        "model": MODEL,
        "prompt": "oi",
        "stream": False,
        "keep_alive": KEEP_ALIVE,
        "options": dict(_model_options(), num_predict=1),
    }
    while True:
        try:
            http_json(f"{OLLAMA_URL}/api/generate", payload, timeout=180)
            log("warmup ok: modelo carregado")
        except Exception as e:
            log(f"warmup falhou: {type(e).__name__}: {e}")
        time.sleep(max(60, WARMUP_INTERVAL))



def remember_sent(mid):
    """Guarda o id do que o bot enviou: esse id volta no webhook SEND_MESSAGE
    e nao pode ser confundido com uma resposta humana (senao o bot se pausa)."""
    if not mid:
        return
    if len(bot_sent) == bot_sent.maxlen:
        bot_sent_set.discard(bot_sent[0])
    bot_sent.append(mid)
    bot_sent_set.add(mid)


def send(jid, text):
    resp = http_json(
        f"{EVOLUTION_URL}/message/sendText/{INSTANCE}",
        {"number": jid.split("@")[0], "text": text},
        timeout=60,
    )
    if isinstance(resp, dict):
        remember_sent((resp.get("key") or {}).get("id"))
    return resp


def compose_reply(jid, text):
    """Decide a resposta sem enviar nada. Devolve (texto, origem, detalhe).

    Ordem das regras (da mais certeira para a mais aberta):
    bloqueio -> pedido -> catalogo -> dados oficiais -> preco -> modelo.
    Origem: config (dado do negocio.json), bloqueio (assunto que a loja nao trabalha),
    pedido, catalogo, catalogo_vazio, saudacao, fora_tema, fallback_preco,
    fallback_valor, fallback_fato, modelo, vazio ou erro_ollama.
    """
    config = load_config()
    assuntos, bloqueios, fora_texto = foco_config(config)
    # Assunto que a loja nao trabalha (ex.: "venda de animais") tem resposta pronta: nem
    # preco nem IA passam por cima disso.
    for gatilho, resposta in bloqueios.items():
        if _casa_termo(gatilho, text):
            return _fill(resposta), "bloqueio", gatilho
    # Intencao de compra nao pode cair na consulta de status ("quero fazer um pedido").
    if PEDIDO_FAZER_RE.search(text) and not re.search(
        r"(?i)(meu|meus|status|onde|quando|chegou|chega|rastre|andamento|pago|entregue)",
        text,
    ):
        novo = str(config.get("pedido_novo") or "").strip() or CATALOGO_TEXTO
        return _fill(novo), "pedido", "novo pedido"
    # Pedido vem ANTES do filtro de preco: "quanto ficou meu pedido?" tem resposta real.
    if PEDIDO_RE.search(text):
        pedidos = consultar_pedidos(jid, text)
        if pedidos:
            return _fill(_formata_pedidos(pedidos)), "pedido", f"{len(pedidos)} pedido(s)"
        texto_pedido = str(config.get("pedido") or "").strip() or PEDIDO_TEXT
        return _fill(texto_pedido), "pedido", "sem consulta"
    # --- catalogo: o que a loja tem de verdade (nome, preco e estoque do sistema) ---
    if CATALOGO_DSN and _catalogo_quer_ver(text):
        resumo = _catalogo_resumo(config)
        return _fill(resumo or CATALOGO_TEXTO), "catalogo", "resumo"
    if config:
        resposta, gatilho = fact_reply(config, text)
        if resposta:
            return _fill(resposta), "config", gatilho
    # Alimentacao / dose ("quanto de racao devo dar"): e conselho da equipe,
    # nunca busca de preço nem palpite do modelo. Deve vir ANTES do catalogo,
    # pq "ração" aciona ITEM_NOME_RE mas a intencao e orientacao, nao compra.
    if NUTRICAO_RE.search(text):
        texto_conselho = str(config.get("conselho") or "").strip() or CONSELHO_TEXT
        return _fill(texto_conselho), "conselho", None
    if CATALOGO_DSN and (
        _catalogo_quer_item(text) or PROBLEMA_RE.search(text)
    ) and _catalogo_termos(text):
        # "meu gato esta com pulga": busca pelo problema, nao pela especie.
        problema = bool(PROBLEMA_RE.search(text)) and not _catalogo_quer_item(text)
        itens = _catalogo_buscar(text, sem_animais=problema)
        if itens:
            return _fill(_formata_catalogo(itens)), "catalogo", f"{len(itens)} item(ns)"
        itens = _catalogo_categoria(text)
        if itens:
            return _fill(_formata_catalogo(itens)), "catalogo", "categoria"
        if not _tem_substantivo_produto(text):
            return _fill(FALLBACK), "fallback_fato", "nao e produto"
        return _fill(CATALOGO_VAZIO), "catalogo_vazio", None
    # Substantivo de produto puro sem verbo de compra ("coleira para gato",
    # "raca golden cachorro"): tenta o catalogo antes de chamar o modelo.
    if CATALOGO_DSN and ITEM_NOME_RE.search(text) and _catalogo_termos(text):
        itens = _catalogo_buscar(text)
        if not itens:
            # Busca mais solta: so o primeiro substantivo (ex. "coleira"),
            # sem exigir que todos os termos casem.
            primeiro = _catalogo_termos(text)[0]
            itens = _catalogo_buscar(primeiro)
        if itens:
            return _fill(_formata_catalogo(itens)), "catalogo", f"{len(itens)} item(ns)"
        itens = _catalogo_categoria(text)
        if itens:
            return _fill(_formata_catalogo(itens)), "catalogo", "categoria"
        if not _tem_substantivo_produto(text):
            return _fill(FALLBACK), "fallback_fato", "nao e produto"
        return _fill(CATALOGO_VAZIO), "catalogo_vazio", None
    if config and MONEY_RE.search(text):
        return _fill(FALLBACK), "fallback_preco", None
    # Saude do pet: nunca deixa o modelo improvisar conduta ou remedio.
    if SAUDE_RE.search(text):
        texto_saude = str(config.get("saude") or "").strip() or SAUDE_TEXT
        return _fill(texto_saude), "saude", None
    # Alimentacao (dose, frequencia, "pode comer todo dia"): tambem e equipe.
    if NUTRICAO_RE.search(text):
        texto_conselho = str(config.get("conselho") or "").strip() or CONSELHO_TEXT
        return _fill(texto_conselho), "conselho", None
    # Cuidados gerais do pet: nao deixa o modelo improvisar.
    if CUIDADO_RE.search(text):
        texto_cuidado = str(config.get("cuidado") or "").strip() or CUIDADO_TEXT
        return _fill(texto_cuidado), "cuidado", None
    # Tema da loja sem dado cadastrado (ex.: "formas_pagamento" vazio): responde
    # "vou confirmar com a equipe" em vez de deixar a IA preencher o buraco.
    if TEMAS_ABERTOS_RE.search(text):
        return _fill(FALLBACK), "fallback_fato", "tema sem cadastro"
    # Cortesia curta ("bom dia", "obrigado"): resposta fixa, o modelo nao acrescenta nada.
    if len(text) <= 60 and SAUDACAO_RE.search(text):
        return _fill(str(config.get("saudacao") or "").strip() or SAUDACAO_TEXT), "saudacao", None
    if len(text) <= 60 and AGRADECIMENTO_RE.search(text):
        return (
            _fill(str(config.get("agradecimento") or "").strip() or AGRADECIMENTO_TEXT),
            "saudacao",
            None,
        )
    # Fora do escopo da loja: nao chama o modelo. E aqui que ele inventava produto e
    # servico que a loja nao tem. Mensagem que cita um pet continua valendo.
    if STRICT or (
        assuntos
        and not any(_casa_assunto(a, text) for a in assuntos)
        and not PET_RE.search(text)
    ):
        return _fill(_texto_fora(assuntos, fora_texto)), "fora_tema", None
    try:
        answer, _took = ask_model(jid, text)
    except urllib.error.HTTPError as e:
        return "", "erro_ollama", f"HTTP {e.code}"
    except Exception as e:
        return "", "erro_ollama", type(e).__name__
    if not answer:
        return "", "vazio", None
    if MONEY_RE.search(answer):
        # Preco so passa se for EXATAMENTE um valor do catalogo enviado ao modelo.
        permitidos = _numeros(_contexto_catalogo(text))
        citados = _numeros(answer)
        if not citados or not citados <= permitidos:
            return _fill(FALLBACK), "fallback_valor", None
    if META_RE.search(answer):
        return _fill(FALLBACK), "fallback_fato", "ia falou de sistema/acesso"
    # A IA inventou produto/servico que nao existe (foi assim que ela "vendeu" animais):
    # qualquer resposta que cite assunto bloqueado ou palavra proibida vira fallback.
    proibidos = [g for g in bloqueios if _casa_termo(g, answer)]
    proibidos += [t for t in nao_mencionar_config(config) if _casa_termo(t, answer)]
    if proibidos:
        return _fill(FALLBACK), "fallback_fato", f"ia citou {proibidos[0]}"
    if FACT_RE.search(answer) and (config or not EXTRA_INFO):
        return _fill(FALLBACK), "fallback_fato", None
    return answer, "modelo", None


def handle(jid, text, name):
    if is_globally_paused():
        log(f"bot pausado (global) — nao respondi {jid}")
        return
    if is_muted(jid):
        log(f"{jid} esta em pausa — nao respondi")
        return
    if not in_active_hours():
        log(f"fora da janela {ACTIVE_HOURS} — nao respondi {jid}")
        return
    if KEYWORDS and not any(k in text.lower() for k in KEYWORDS):
        log(f"sem palavra-chave — nao respondi {jid}")
        return
    if handoff_hit(text):
        record_question(jid, name, text, _fill(HANDOFF_TEXT), "handoff", "pedido de atendente")
        try:
            send(jid, _fill(HANDOFF_TEXT))
            log(f"transferido para humano {jid} ({name or 'sem nome'})")
        except Exception as e:
            log(f"falha ao transferir {jid}: {type(e).__name__}: {e}")
        mute_for(jid, HANDOFF_MUTE_MIN, "pedido de atendente")
        return
    if not within_rate(jid):
        log(f"rate-limit {jid} (>{MAX_REPLIES_HOUR}/h) — nao respondi")
        return
    answer, origem, detalhe = compose_reply(jid, text)
    record_question(jid, name, text, answer, origem, detalhe)
    if not answer:
        log(f"sem resposta para {jid} ({origem} {detalhe or ''})")
        return
    if INTRO and time.time() - last_intro.get(jid, 0) > 12 * 3600:
        answer = f"{_fill(INTRO)}\n\n{answer}"
        last_intro[jid] = time.time()
    try:
        send(jid, answer)
        replies[jid].append(time.time())
        marca = origem + (f"/{detalhe[:18]}" if detalhe else "")
        log(f"respondido {jid} ({name or 'sem nome'}) em [{marca}] | {len(answer)} chars")
    except urllib.error.HTTPError as e:
        log(f"sendText HTTP {e.code} para {jid}: {e.read()[:200]}")
    except Exception as e:
        log(f"sendText erro para {jid}: {type(e).__name__}: {e}")


def worker():
    while True:
        time.sleep(1)
        now = time.time()
        due = []
        with pending_lock:
            for jid in [j for j, v in pending.items() if now - v["at"] >= DEBOUNCE]:
                due.append((jid, pending.pop(jid)))
        for jid, item in due:
            try:
                handle(jid, item["text"], item["name"])
            except Exception as e:
                log(f"falha ao tratar {jid}: {type(e).__name__}: {e}")


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def _reply(self, code, body=b'{"ok":true}'):
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        # A versao web do app chama estas rotas de outra origem.
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Headers", "Content-Type, x-bot-token")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.end_headers()
        self.wfile.write(body)

    def do_OPTIONS(self):
        self._reply(204, b"")

    def do_GET(self):
        rota, _, consulta = self.path.partition("?")
        if rota == "/admin/perguntas":
            if not self._autorizado():
                return self._reply(401, b'{"error":"token invalido"}')
            params = {}
            for parte in consulta.split("&"):
                if "=" in parte:
                    chave, valor = parte.split("=", 1)
                    params[chave] = valor
            try:
                limite = int(params.get("limit") or 50)
            except ValueError:
                limite = 50
            limite = max(1, min(limite, 500))
            somente_falhas = (params.get("only") or "falhas") != "todas"
            entradas, contagem, total = load_questions(limite, somente_falhas)
            return self._reply(
                200,
                json.dumps(
                    {
                        "ok": True,
                        "filtro": "falhas" if somente_falhas else "todas",
                        "total_gravadas": total,
                        "counts": contagem,
                        "entradas": entradas,
                    },
                    ensure_ascii=False,
                ).encode("utf-8"),
            )
        if rota in ("/", "/health", "/webhook"):
            info = {
                "ok": True,
                "model": MODEL,
                "instance": INSTANCE,
                "active_hours": ACTIVE_HOURS or "24h",
                "mute_human_min": HUMAN_MUTE_MIN,
                "empresa": EMPRESA_NOME,
                "config_file": CONFIG_FILE,
                "config_facts": len(fact_answers(load_config())),
                "strict": STRICT,
                "foco_assuntos": len(foco_config(load_config())[0]),
                "foco_bloqueios": len(foco_config(load_config())[1]),
                "pedidos_consulta": bool(PEDIDOS_DSN),
                "catalogo_consulta": bool(CATALOGO_DSN),
                "catalogo_empresa": CATALOGO_EMPRESA or "(todas)",
                "catalogo_itens": len(_catalogo["itens"]),
                "catalogo_grupos": len(_catalogo["grupos"]),
                "catalogo_erro": _catalogo["erro"],
                "modelo_options": _model_options(),
                "warmup": WARMUP,
                "foco_nao_mencionar": len(nao_mencionar_config(load_config())),
                "prompt_source": "file" if PROMPT_FILE else ("env" if PROMPT_INLINE else "default"),
                "prompt_chars": len(load_prompt()),
                "keywords": KEYWORDS,
                "paused": is_globally_paused(),
                "paused_until": paused_until_global,
                "paused_contacts": len(muted_until),
                "state_file": STATE_FILE,
            }
            self._reply(200, json.dumps(info).encode())
        else:
            self._reply(404, b'{"ok":false}')

    def _json_body(self, raw):
        try:
            return json.loads(raw.decode("utf-8", "replace")) if raw.strip() else {}
        except json.JSONDecodeError:
            return {}

    def _autorizado(self):
        if not ADMIN_TOKEN:
            return True
        return (self.headers.get("x-bot-token") or "").strip() == ADMIN_TOKEN

    def do_POST(self):
        path = self.path.rstrip("/")
        length = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(length) if length else b"{}"
        body = self._json_body(raw)

        # --- rotas de administracao / teste pelo app ---
        if path in ("/chat", "/admin/pause", "/admin/resume"):
            if not self._autorizado():
                return self._reply(401, b'{"error":"token invalido"}')
            if path == "/admin/pause":
                try:
                    minutos = int(body.get("minutes") or 0)
                except (TypeError, ValueError):
                    minutos = 0
                set_global_pause(minutos)
                return self._reply(
                    200,
                    json.dumps({"paused": True, "minutes": minutos}).encode(),
                )
            if path == "/admin/resume":
                resume_bot()
                return self._reply(200, b'{"paused": false}')
            texto = str(body.get("text") or "").strip()[:MAX_INPUT]
            if not texto:
                return self._reply(400, b'{"error":"texto vazio"}')
            # Teste simulando um cliente: manda o telefone e a consulta de pedido roda de verdade.
            telefone = re.sub(r"\D", "", str(body.get("telefone") or ""))
            jid_teste = f"{telefone}@s.whatsapp.net" if len(telefone) >= 10 else "__app__"
            inicio = time.time()
            resposta, origem, detalhe = compose_reply(jid_teste, texto)
            ms = int((time.time() - inicio) * 1000)
            log(f"teste pelo app [{origem}] {texto[:60]}")
            return self._reply(
                200,
                json.dumps(
                    {
                        "reply": resposta,
                        "source": origem,
                        "rule": detalhe,
                        "ms": ms,
                        "paused": is_globally_paused(),
                    }
                ).encode(),
            )

        if path not in ("/webhook", ""):
            return self._reply(404, b'{"ok":false}')
        self._reply(200)  # Evolution nao espera processamento
        inst = (body.get("instance") or "").strip()
        if inst and inst != INSTANCE:
            return  # webhook de outra empresa: este bot so atende a sua instancia
        event = (body.get("event") or "").lower().replace(".", "_")
        data = body.get("data") or {}
        key = data.get("key") or {}
        jid = key.get("remoteJid") or ""
        if not jid.endswith("@s.whatsapp.net"):
            return
        # Loja respondeu pelo celular/app -> pausa o bot para esse contato.
        if key.get("fromMe") or "send_message" in event:
            if key.get("id") in bot_sent_set:
                return  # foi o proprio bot: nao pausa nada
            mute_for(jid, HUMAN_MUTE_MIN, "loja respondeu manualmente")
            return
        if "messages_upsert" not in event:
            return
        mid = key.get("id")
        if not mid or not mark_seen(mid):
            return
        text = (extract_text(data) or "").strip()
        if not text:
            log(f"sem texto de {jid} — ignorado (audio/imagem)")
            return
        if len(text) > MAX_INPUT:
            text = text[:MAX_INPUT]
        name = (data.get("pushName") or "").strip()
        with pending_lock:
            pending[jid] = {"text": text, "name": name, "at": time.time()}
        log(f"recebido de {jid} ({name or 'sem nome'}): {text[:80]}")

    def log_message(self, fmt, *args):
        return


if __name__ == "__main__":
    if not INSTANCE:
        log("ERRO: defina BOT_INSTANCE no .env (nome da instancia na Evolution)")
        sys.exit(1)
    log(
        f"bot iniciado | empresa={EMPRESA_NOME} modelo={MODEL} instancia={INSTANCE} "
        f"ollama={OLLAMA_URL} "
        f"janela={ACTIVE_HOURS or '24h'} pausa_humano={HUMAN_MUTE_MIN}min "
        f"palavras_chave={KEYWORDS or 'todas'} estado={STATE_FILE} "
        f"catalogo={'sim' if CATALOGO_DSN else 'nao'} pedidos={'sim' if PEDIDOS_DSN else 'nao'}"
    )
    load_state()
    if CATALOGO_DSN:
        threading.Thread(target=_catalogo_carregar, kwargs={"forcar": True}, daemon=True).start()
    if WARMUP:
        threading.Thread(target=warmup_loop, daemon=True).start()
    threading.Thread(target=worker, daemon=True).start()
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
