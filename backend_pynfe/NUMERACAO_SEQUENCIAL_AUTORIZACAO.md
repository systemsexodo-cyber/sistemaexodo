# 📋 Numeração Sequencial e Verificação de Autorização - NFC-e

## ✅ Implementações Realizadas

### 1. **Sistema de Numeração Sequencial Persistente**

#### **Arquivo:** `sistema_exodo_01-12/backend_pynfe/services/nfce_service.py`

#### **Funcionalidades Implementadas:**

1. **`_obter_arquivo_numeracao(empresa_data, serie)`**
   - Obtém o caminho do arquivo JSON que armazena a numeração sequencial
   - Localização: `logs/empresas/{CNPJ_ou_ID}/numeracao_serie_{serie}.json`
   - Cada empresa/série tem seu próprio arquivo de numeração

2. **`_obter_proximo_numero(empresa_data, serie)`**
   - Obtém o próximo número sequencial da NFC-e para a empresa/série
   - Carrega o número atual do arquivo JSON
   - Retorna o número atual (será incrementado apenas quando autorizado)
   - Se o arquivo não existir, inicia com número 1

3. **`_salvar_numero_atual(empresa_data, serie, numero)`**
   - Salva o número atual da numeração sequencial no arquivo JSON
   - Cria o diretório se não existir
   - Armazena também a série e a data da última atualização

4. **`_incrementar_numero_apos_autorizacao(empresa_data, serie, numero_atual)`**
   - Incrementa o número sequencial apenas após autorização da SEFAZ
   - Converte o número para int, incrementa e salva
   - **IMPORTANTE:** Só é chamado quando a nota é autorizada (cStat 100 ou 150)

### 2. **Modificação na Função `emitir_nfce`**

#### **Antes:**
- Gerava número baseado em timestamp se não fornecido
- Não havia controle sequencial persistente
- Número podia ser perdido entre execuções

#### **Agora:**
- Usa `_obter_proximo_numero()` para obter número sequencial persistente
- Número é salvo por empresa/série
- Número só é incrementado quando a nota é **autorizada** pela SEFAZ

### 3. **Verificação Clara de Autorização**

#### **Status de Autorização:**

1. **✅ AUTORIZADA (cStat 100 ou 150)**
   - Status: `'autorizada'`
   - Flag: `'autorizada': True`
   - Número é **incrementado** automaticamente
   - Retorno inclui:
     - `'status': 'autorizada'`
     - `'autorizada': True`
     - `'cstat': '100'` ou `'150'`
     - `'protocolo'`: Número do protocolo de autorização
     - `'chave_acesso'`: Chave de acesso da NFC-e
     - `'qr_code'`: QR Code para consulta

2. **❌ NÃO AUTORIZADA (rejeitada, denegada, etc)**
   - Status: `'rejeitada'`, `'denegada'` ou `'processando'`
   - Flag: `'autorizada': False`
   - Número **NÃO é incrementado** (pode ser reutilizado)
   - Retorno inclui:
     - `'status'`: Status da nota
     - `'autorizada': False`
     - `'cstat'`: Código da SEFAZ
     - `'motivo'`: Motivo da rejeição/denegação
     - `'xml_resposta'`: XML completo da resposta da SEFAZ

### 4. **Estrutura do Arquivo de Numeração**

```json
{
  "numero_atual": 123,
  "serie": "001",
  "ultima_atualizacao": "2024-01-15T10:30:00.123456"
}
```

### 5. **Fluxo de Numeração**

```
1. Usuário solicita emissão de NFC-e
   ↓
2. Sistema obtém próximo número sequencial (ex: 123)
   ↓
3. NFC-e é criada com número 123
   ↓
4. XML é gerado e assinado
   ↓
5. XML é enviado para SEFAZ
   ↓
6. SEFAZ responde:
   ├─ ✅ AUTORIZADA (cStat 100/150)
   │   └─ Número é incrementado para 124
   │   └─ Retorna success: true, autorizada: true
   │
   └─ ❌ NÃO AUTORIZADA (cStat diferente)
       └─ Número NÃO é incrementado (continua 123)
       └─ Retorna success: false, autorizada: false
       └─ Número pode ser reutilizado na próxima tentativa
```

## 📝 Exemplos de Uso

### **Exemplo 1: Nota Autorizada**

```python
resultado = nfce_service.emitir_nfce(data)

if resultado['success'] and resultado.get('data', {}).get('autorizada'):
    print(f"✅ NFC-e autorizada!")
    print(f"Número: {resultado['data']['numero']}")
    print(f"Protocolo: {resultado['data']['protocolo']}")
    print(f"Chave: {resultado['data']['chave_acesso']}")
else:
    print(f"❌ NFC-e não autorizada")
    print(f"Status: {resultado.get('status')}")
    print(f"Motivo: {resultado.get('motivo')}")
```

### **Exemplo 2: Verificar Status de Autorização**

```python
resultado = nfce_service.emitir_nfce(data)

# Verificar se foi autorizada
if resultado.get('data', {}).get('autorizada') == True:
    # Nota autorizada - número foi incrementado
    print("✅ Nota autorizada pela SEFAZ")
elif resultado.get('autorizada') == False:
    # Nota não autorizada - número não foi incrementado
    print("❌ Nota não autorizada")
    print(f"Código SEFAZ: {resultado.get('cstat')}")
    print(f"Motivo: {resultado.get('motivo')}")
```

## 🔍 Verificação de Autorização

### **Códigos SEFAZ:**

- **100**: Autorizada
- **150**: Autorizada (fora do prazo)
- **110**: Denegada
- **301**: Denegada (Uso Denegado)
- **302**: Denegada (Uso Denegado para o destinatário)
- **2xx**: Rejeitada (vários códigos)
- **3xx**: Denegada (vários códigos)

### **Função `_processar_resposta_sefaz`:**

A função processa a resposta da SEFAZ e determina o status:

```python
if status_code == '100' or status_code == '150':
    status = 'autorizada'
elif status_code in ['110', '301', '302']:
    status = 'denegada'
elif status_code:
    status = 'rejeitada'
else:
    status = 'processando'
```

## ⚠️ Importante

1. **Numeração só incrementa quando autorizada**
   - Se a nota for rejeitada, o número não é incrementado
   - O mesmo número pode ser reutilizado na próxima tentativa

2. **Arquivo de numeração por empresa/série**
   - Cada empresa tem seu próprio arquivo de numeração
   - Cada série tem seu próprio contador
   - Localização: `logs/empresas/{CNPJ}/numeracao_serie_{serie}.json`

3. **Verificação explícita de autorização**
   - Todos os retornos incluem flag `'autorizada'` (True/False)
   - Status da SEFAZ é sempre incluído (`'cstat'`)
   - Motivo da rejeição/denegação é sempre incluído (`'motivo'`)

## 📂 Estrutura de Arquivos

```
backend_pynfe/
├── services/
│   └── nfce_service.py (modificado)
└── logs/
    └── empresas/
        └── {CNPJ_ou_ID}/
            ├── numeracao_serie_001.json
            ├── numeracao_serie_002.json
            ├── xml_enviado/
            ├── xml_assinado/
            └── xml_resposta/
```

## ✅ Benefícios

1. **Numeração sequencial garantida**
   - Não há perda de números entre execuções
   - Cada empresa/série mantém sua própria sequência

2. **Economia de números**
   - Números rejeitados não são perdidos
   - Podem ser reutilizados após correção

3. **Rastreabilidade**
   - Arquivo JSON armazena histórico
   - Data da última atualização é registrada

4. **Clareza na verificação**
   - Flag explícita `'autorizada'` em todos os retornos
   - Status da SEFAZ sempre incluído
   - Motivo da rejeição sempre disponível


























