# 🚀 Guia Completo - Emitir NFC-e do Zero

## ✅ Processo Simplificado em 7 Passos

---

## 📋 PASSO 1: Instalar Python (se não tiver)

### Windows:
1. Baixe em: https://www.python.org/downloads/
2. **IMPORTANTE:** Marque "Add Python to PATH" ✅
3. Instale normalmente

### Verificar se já tem:
Abra o PowerShell ou CMD e digite:
```bash
python --version
```

**Se aparecer a versão (ex: Python 3.10.0), está OK!**
**Se der erro, instale o Python primeiro.**

---

## 📋 PASSO 2: Executar Script Automático

### Opção A: Script Completo (Recomendado)
Duplo clique em:
```
EXECUTAR_PRIMEIRO.bat
```

Este script vai:
- ✅ Verificar Python
- ✅ Instalar dependências
- ✅ Iniciar o servidor

### Opção B: Manual
Abra o PowerShell/CMD na pasta do projeto e execute:

```bash
cd backend_pynfe
python -m pip install flask flask-cors python-dotenv requests lxml signxml cryptography
python app.py
```

---

## 📋 PASSO 3: Verificar se o Backend Está Rodando

Abra no navegador:
```
http://localhost:5000/health
```

**Deve aparecer:**
```json
{
  "status": "ok",
  "message": "Backend NFC-e está funcionando"
}
```

**✅ Se aparecer isso, o backend está funcionando!**

**❌ Se não abrir ou der erro:**
- Verifique se o servidor está rodando (veja o terminal onde executou `python app.py`)
- Verifique se não há erro no terminal

---

## 📋 PASSO 4: Configurar Empresa no Sistema Flutter

1. Abra o sistema Flutter
2. Vá em **"Empresas"** → **"Nova Empresa"** ou **"Editar"**

### Preencha os dados:

#### Dados Obrigatórios:
- **CNPJ**: Digite o CNPJ (ex: 12345678000190)
- **Razão Social**: Nome da empresa
- **Inscrição Estadual**: Número da IE
- **UF**: Estado (ex: SP, RJ, MG)
- **Código IBGE**: Código do município
  - Exemplo: São Paulo = 3550308
  - Busque em: https://www.ibge.gov.br/explica/codigos-dos-municipios.php

#### Certificado Digital:
- **Certificado Digital**: Faça upload do arquivo `.pfx` ou `.p12`
- **Senha do Certificado**: Digite a senha do certificado

#### Configurações Importantes:
- ✅ **Ambiente Homologação**: Marque esta opção para testes
- **Série NFC-e**: Geralmente "1"

### Salvar:
Clique em **"Salvar"**

---

## 📋 PASSO 5: Configurar Produtos (se necessário)

1. Vá em **"Produtos"**
2. Crie produtos com:
   - Código
   - Nome
   - Preço
   - NCM (código de classificação fiscal)
   - CFOP (geralmente 5102 para venda)

---

## 📋 PASSO 6: Criar Venda e Emitir NFC-e

1. Vá em **"Venda Direta"** ou **"PDV"**
2. Adicione produtos ao carrinho
3. Clique em **"Finalizar Venda"**
4. Clique em **"Emitir NFC-e"**

### O que vai acontecer:
1. Sistema envia dados para `http://localhost:5000/api/nfce/emitir`
2. Backend processa e emite na SEFAZ (homologação)
3. Se autorizada, aparece:
   - ✅ Chave de acesso
   - ✅ QR Code
   - ✅ Protocolo

---

## 📋 PASSO 7: Verificar Resultado

### ✅ Sucesso:
- NFC-e autorizada
- QR Code exibido
- Chave de acesso mostrada

### ❌ Erro:
Verifique os logs:
- **Terminal do Backend**: Veja as mensagens de erro
- **Console do Flutter**: Pressione F12 → Console

---

## 🐛 Problemas Comuns e Soluções

### ❌ Erro: "Python não encontrado"
**Solução:**
1. Instale Python de: https://www.python.org/downloads/
2. Marque "Add Python to PATH"
3. Reinicie o terminal

### ❌ Erro: "Failed to fetch" ou "Connection refused"
**Solução:**
1. Verifique se o backend está rodando: http://localhost:5000/health
2. Se não estiver, execute: `python app.py` na pasta `backend_pynfe`
3. Se estiver em dispositivo físico, use o IP da máquina no Flutter

### ❌ Erro: "Certificado não encontrado"
**Solução:**
1. Verifique se fez upload do certificado na empresa
2. Verifique se a senha está correta
3. Certificado deve ser válido e não expirado

### ❌ Erro: "NFC-e rejeitada"
**Solução:**
1. Verifique se está em ambiente de HOMOLOGAÇÃO
2. Verifique se os dados da empresa estão corretos
3. Verifique se o código IBGE está correto
4. Veja o código de erro retornado pela SEFAZ

---

## ✅ Checklist Final

Antes de tentar emitir, verifique:

- [ ] Python instalado (`python --version` funciona)
- [ ] Dependências instaladas
- [ ] Backend rodando (http://localhost:5000/health retorna OK)
- [ ] Empresa criada com todos os dados
- [ ] Certificado digital carregado
- [ ] Ambiente = HOMOLOGAÇÃO
- [ ] Produtos cadastrados
- [ ] Venda criada

---

## 🎯 Teste Rápido

### 1. Testar Backend:
```
http://localhost:5000/health
```

### 2. Emitir NFC-e:
Venda Direta → Adicionar Produto → Finalizar → Emitir NFC-e

---

## 📚 Arquivos Importantes

- `EXECUTAR_PRIMEIRO.bat` - Script automático
- `backend_pynfe/app.py` - Servidor backend
- `backend_pynfe/INICIAR_AGORA.bat` - Iniciar backend
- `PROCESSO_COMPLETO_NFCE.md` - Guia detalhado
- `TESTE_RAPIDO_NFCE.md` - Teste em 5 minutos

---

## 🆘 Ainda com Problemas?

1. Verifique se o backend está rodando
2. Veja os logs do terminal onde rodou `python app.py`
3. Veja o console do Flutter (F12)
4. Consulte `PROCESSO_COMPLETO_NFCE.md` para mais detalhes

---

## ✅ Pronto!

Seguindo esses passos, você conseguirá emitir NFC-e com sucesso!

**Lembre-se:**
- Use **HOMOLOGAÇÃO** para testes
- Para produção, desmarque "Ambiente Homologação"
- Certificado deve ser válido











