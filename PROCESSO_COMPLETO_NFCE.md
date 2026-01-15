# 🚀 Processo Completo para Emitir NFC-e

## ✅ Passo a Passo Completo - Do Zero ao Funcionando

Este guia vai te levar do início até conseguir emitir uma NFC-e com sucesso.

---

## 📋 PASSO 1: Escolher o Backend

### Opção A: Backend Python (Recomendado - Mais Simples)
- ✅ Já está implementado
- ✅ Funciona localmente
- ✅ Pode fazer deploy no Firebase

### Opção B: Backend PHP (Alternativa)
- ⚠️ Precisa instalar PHP e Composer
- ⚠️ Mais complexo

**Vamos usar o Backend Python (Opção A)**

---

## 📋 PASSO 2: Instalar Python (se não tiver)

### Windows:
1. Baixe Python 3.10+ de: https://www.python.org/downloads/
2. **IMPORTANTE:** Marque "Add Python to PATH" durante instalação
3. Verifique:
   ```bash
   python --version
   ```

### Verificar se já tem:
```bash
python --version
# ou
python3 --version
```

---

## 📋 PASSO 3: Instalar Dependências do Backend Python

```bash
cd backend_pynfe
pip install -r requirements.txt
```

Se der erro, tente:
```bash
python -m pip install -r requirements.txt
```

**Dependências principais:**
- Flask (servidor web)
- flask-cors (CORS)
- python-dotenv (variáveis de ambiente)

---

## 📋 PASSO 4: Configurar Certificado Digital

### O que você precisa:
1. **Certificado digital A1** (arquivo .pfx ou .p12)
2. **Senha do certificado**

### Onde colocar:
No Flutter, quando criar/editar uma empresa:
- Campo: "Certificado Digital" (upload do arquivo PFX)
- Campo: "Senha do Certificado"

O sistema vai converter automaticamente para base64 e salvar.

---

## 📋 PASSO 5: Iniciar o Backend Python

### Opção A: Script Batch (Windows)
```bash
cd backend_pynfe
iniciar_app.bat
```

### Opção B: Manual
```bash
cd backend_pynfe
python app.py
```

### Opção C: Script Shell (Linux/Mac)
```bash
cd backend_pynfe
./start_local.sh
```

**O servidor vai iniciar em:** `http://localhost:5000`

### Verificar se está funcionando:
Abra no navegador:
```
http://localhost:5000/health
```

Deve retornar:
```json
{
  "status": "ok",
  "message": "Backend NFC-e está funcionando"
}
```

---

## 📋 PASSO 6: Configurar Flutter para Usar o Backend

### Verificar URL no código:
Arquivo: `lib/services/nfce_backend_service.dart`

Linha ~51, deve estar:
```dart
return 'http://localhost:5000';
```

### Se estiver em dispositivo físico:
Altere para o IP da sua máquina:
```dart
return 'http://192.168.1.XXX:5000';  // Substitua XXX pelo seu IP
```

Para descobrir seu IP (Windows):
```bash
ipconfig
# Procure por "IPv4" (ex: 192.168.1.100)
```

---

## 📋 PASSO 7: Configurar Empresa no Sistema

### No Flutter:
1. Vá em "Empresas"
2. Crie ou edite uma empresa
3. Preencha:
   - ✅ CNPJ
   - ✅ Razão Social
   - ✅ Inscrição Estadual
   - ✅ UF
   - ✅ Código IBGE do Município
   - ✅ Certificado Digital (upload do arquivo .pfx)
   - ✅ Senha do Certificado
   - ✅ Ambiente: **HOMOLOGAÇÃO** (para testes)

### Campos Importantes:
- **UF**: Estado da empresa (ex: SP, RJ, MG)
- **Código IBGE**: Código do município (ex: 3550308 para São Paulo)
- **Série NFC-e**: Geralmente "1"
- **Ambiente Homologação**: ✅ Marque para testes

---

## 📋 PASSO 8: Fazer Uma Venda de Teste

1. Vá em "Venda Direta" ou "PDV"
2. Adicione produtos ao carrinho
3. Finalize a venda
4. Clique em "Emitir NFC-e"

### O que vai acontecer:
1. Sistema envia dados para `http://localhost:5000/api/nfce/emitir`
2. Backend Python processa
3. Emite NFC-e na SEFAZ (homologação)
4. Retorna resultado
5. Mostra QR Code se autorizada

---

## 📋 PASSO 9: Verificar Logs (Se Der Erro)

### Logs do Backend Python:
No terminal onde rodou `python app.py`, você verá:
```
>>> [NFCe] Iniciando emissão de NFC-e...
>>> [NFCe] Ambiente: Homologação
>>> [NFCe] Empresa: ...
```

### Logs do Flutter:
Abra o DevTools (F12) ou console do navegador.

---

## 🐛 Problemas Comuns e Soluções

### ❌ Erro: "Failed to fetch"
**Causa:** Backend não está rodando ou URL incorreta

**Solução:**
1. Verifique se o backend está rodando: `http://localhost:5000/health`
2. Verifique a URL no Flutter
3. Se estiver em dispositivo físico, use o IP da máquina

### ❌ Erro: "Certificado não encontrado"
**Causa:** Certificado não foi enviado ou formato incorreto

**Solução:**
1. Verifique se fez upload do certificado PFX
2. Verifique se a senha está correta
3. Certificado deve ser válido e não expirado

### ❌ Erro: "Código IBGE inválido"
**Causa:** Código IBGE incorreto

**Solução:**
1. Busque o código IBGE correto do município
2. Exemplo: São Paulo = 3550308
3. Use o código completo (7 ou 8 dígitos)

### ❌ Erro: "NFC-e rejeitada pela SEFAZ"
**Causa:** Dados incorretos ou certificado inválido

**Solução:**
1. Verifique se está em homologação
2. Verifique se o certificado é válido
3. Verifique se os dados da empresa estão corretos
4. Verifique o código de erro retornado

---

## ✅ Checklist Final

Antes de tentar emitir, verifique:

- [ ] Python instalado e no PATH
- [ ] Dependências instaladas (`pip install -r requirements.txt`)
- [ ] Backend rodando (`http://localhost:5000/health` retorna OK)
- [ ] URL configurada no Flutter (`localhost:5000` ou IP da máquina)
- [ ] Empresa criada com todos os dados
- [ ] Certificado digital carregado
- [ ] Ambiente configurado como HOMOLOGAÇÃO
- [ ] Produtos cadastrados
- [ ] Venda criada com produtos

---

## 🎯 Teste Rápido

### 1. Testar Backend:
```bash
curl http://localhost:5000/health
```

### 2. Testar Emissão (via código de teste):
Veja o arquivo `backend_pynfe/testar_emissao_nfce.py`

### 3. Emitir pelo Flutter:
1. Venda Direta → Adicionar Produto → Finalizar Venda → Emitir NFC-e

---

## 📚 Arquivos Úteis

- `backend_pynfe/app.py` - Servidor principal
- `backend_pynfe/README.md` - Documentação do backend
- `lib/services/nfce_backend_service.dart` - Serviço Flutter
- `lib/pages/venda_direta_page.dart` - Tela de venda

---

## 🆘 Ainda com Problemas?

1. Verifique os logs do backend Python
2. Verifique os logs do Flutter (DevTools)
3. Teste o endpoint `/health` no navegador
4. Verifique se o certificado está válido
5. Certifique-se de que está em ambiente de HOMOLOGAÇÃO

---

## ✅ Pronto!

Seguindo esses passos, você conseguirá emitir NFC-e com sucesso!

**Lembre-se:** Use ambiente de HOMOLOGAÇÃO para testes. Para produção, desmarque "Ambiente Homologação" e use certificado de produção.











