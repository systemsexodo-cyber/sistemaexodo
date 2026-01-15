# Qual Arquivo Python Executar para Emissão de NFC-e

## 🎯 Arquivo Principal: `app.py`

O arquivo **`app.py`** é o arquivo principal que contém **TUDO** da emissão de NFC-e.

### ✅ Por que usar `app.py`?

1. **Tem tudo integrado:**
   - ✅ Implementação PyNFe (se disponível)
   - ✅ Implementação Manual (fallback automático)
   - ✅ Processamento de certificado (base64 ou arquivo PFX)
   - ✅ Geração de XML
   - ✅ Assinatura digital
   - ✅ Envio para SEFAZ
   - ✅ Processamento de resposta
   - ✅ Salvamento de XMLs organizados por empresa

2. **API REST completa:**
   - Recebe requisições HTTP do Flutter
   - Endpoint: `POST /api/nfce/emitir`
   - Retorna JSON com resultado

3. **Fallback automático:**
   - Tenta usar PyNFe primeiro
   - Se PyNFe não estiver disponível, usa implementação manual automaticamente
   - Você não precisa escolher manualmente

## 🚀 Como Executar

### Opção 1: Executar Diretamente (Recomendado)

```bash
cd sistema_exodo_01-12/backend_pynfe
python app.py
```

O servidor iniciará em: `http://localhost:5000`

### Opção 2: Usar Script Batch (Windows)

```bash
# Duplo clique em:
iniciar_app.bat
```

### Opção 3: Usar Script Shell (Linux/Mac)

```bash
chmod +x start_local.sh
./start_local.sh
```

## 📋 O que o `app.py` faz?

1. **Carrega serviços:**
   - CertificadoService (para processar certificados)
   - NFCeService (nfelib, se disponível)
   - PyNFe (se disponível)

2. **Decide automaticamente qual implementação usar:**
   - Tenta PyNFe primeiro
   - Se falhar, usa implementação manual (`nfce_manual_completo.py`)

3. **Processa requisições:**
   - Recebe dados da empresa, produtos, pagamentos
   - Processa certificado (base64 ou arquivo PFX)
   - Emite NFC-e
   - Retorna resultado

## 🔍 Estrutura do Código

```
app.py (ARQUIVO PRINCIPAL)
├── Carrega serviços
├── Define rotas Flask
├── POST /api/nfce/emitir
│   ├── Valida dados
│   ├── Tenta PyNFe (nfce_pynfe_completo.py)
│   │   └── Se falhar → Usa Manual (nfce_manual_completo.py)
│   ├── Processa certificado
│   ├── Emite NFC-e
│   └── Retorna resultado
└── Inicia servidor Flask
```

## 📁 Arquivos Relacionados

### Arquivos Principais:

- **`app.py`** ⭐ - **EXECUTE ESTE** - Servidor Flask completo
- `nfce_pynfe_completo.py` - Implementação usando PyNFe (usado automaticamente pelo app.py)
- `nfce_manual_completo.py` - Implementação manual (fallback automático)

### Arquivos de Teste (não use para produção):

- `testar_emissao_nfce.py` - Script de teste
- `exemplo_nfce_manual.py` - Exemplo de uso manual
- `exemplo_rodar_pynfe.py` - Exemplo de uso PyNFe

## ⚙️ Configuração

O `app.py` usa variáveis de ambiente (opcional):

```bash
# .env (opcional)
PORT=5000
DEBUG=True
CORS_ORIGINS=*
```

Se não criar `.env`, usa valores padrão:
- Porta: 5000
- Debug: True
- CORS: Permite todas as origens

## 🎯 Resumo

**Execute apenas:**
```bash
python app.py
```

Este arquivo tem **TUDO** que você precisa:
- ✅ Emissão completa de NFC-e
- ✅ Suporte a certificado base64 e arquivo PFX
- ✅ Fallback automático entre PyNFe e Manual
- ✅ API REST pronta para usar
- ✅ Salvamento de XMLs organizados
- ✅ Processamento completo de respostas da SEFAZ

## 📝 Exemplo de Uso

Após executar `app.py`, o servidor estará rodando e você pode:

1. **Testar health check:**
   ```bash
   curl http://localhost:5000/health
   ```

2. **Emitir NFC-e (via Flutter ou Postman):**
   ```bash
   POST http://localhost:5000/api/nfce/emitir
   Content-Type: application/json
   
   {
     "empresa": {
       "cnpj": "12345678000190",
       "certificado_path": "C:/certificados/cert.pfx",
       "senhaCertificado": "senha123",
       ...
     },
     "produtos": [...],
     "pagamentos": [...]
   }
   ```

## ⚠️ Importante

- **NÃO execute** `nfce_pynfe_completo.py` ou `nfce_manual_completo.py` diretamente
- **Execute apenas** `app.py` - ele já usa esses arquivos internamente
- O `app.py` decide automaticamente qual usar baseado na disponibilidade

## 🔧 Troubleshooting

### Se o servidor não iniciar:

1. Verifique se as dependências estão instaladas:
   ```bash
   pip install Flask Flask-CORS python-dotenv
   ```

2. Para emissão completa, instale também:
   ```bash
   pip install nfelib signxml cryptography lxml requests
   ```

3. Se PyNFe não estiver disponível, o sistema usa automaticamente a implementação manual

### Logs importantes:

O `app.py` mostra no console:
- ✅ Qual implementação está sendo usada (PyNFe ou Manual)
- ✅ Status do certificado
- ✅ Processo de emissão passo a passo
- ✅ Resultado da SEFAZ












