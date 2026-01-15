# 🚀 COMECE AQUI - Processo Completo para Emitir NFC-e

## ✅ Python Detectado!

Seu sistema já tem Python instalado (versão 3.12.10). ✅

---

## 🎯 Processo em 3 Passos Simples

### PASSO 1: Iniciar o Backend (2 minutos)

Duplo clique no arquivo:
```
INICIAR_TUDO.bat
```

Ou manualmente:
```bash
cd backend_pynfe
python -m pip install flask flask-cors python-dotenv requests lxml signxml cryptography
python app.py
```

**Verificar:** Abra http://localhost:5000/health no navegador
**Deve aparecer:** `{"status": "ok", ...}`

---

### PASSO 2: Configurar Empresa no Flutter (3 minutos)

1. Abra o sistema Flutter
2. Vá em **"Empresas"** → **"Nova Empresa"** ou **"Editar"**
3. Preencha:
   - ✅ CNPJ
   - ✅ Razão Social
   - ✅ Inscrição Estadual
   - ✅ UF (ex: SP)
   - ✅ Código IBGE (ex: 3550308 para São Paulo)
   - ✅ Certificado Digital (upload do arquivo .pfx)
   - ✅ Senha do Certificado
   - ✅ **Ambiente Homologação** (marque para testes)

---

### PASSO 3: Emitir NFC-e (1 minuto)

1. Vá em **"Venda Direta"**
2. Adicione produtos
3. Finalize a venda
4. Clique em **"Emitir NFC-e"**

**Pronto!** Se tudo estiver OK, a NFC-e será autorizada e você verá o QR Code.

---

## 🐛 Se Der Erro

### Backend não inicia:
```bash
cd backend_pynfe
python -m pip install flask flask-cors python-dotenv requests lxml signxml cryptography
python app.py
```

### "Failed to fetch":
- Backend está rodando? → http://localhost:5000/health
- Verifique se a URL no Flutter está correta

### Certificado inválido:
- Use certificado válido
- Verifique senha
- Certificado deve ser .pfx ou .p12

---

## 📚 Mais Informações

- **Guia Completo**: `GUIA_COMPLETO_NFCE.md`
- **Teste Rápido**: `TESTE_RAPIDO_NFCE.md`
- **Processo Detalhado**: `PROCESSO_COMPLETO_NFCE.md`

---

## ✅ Checklist Rápido

- [ ] Backend rodando (http://localhost:5000/health)
- [ ] Empresa configurada
- [ ] Certificado carregado
- [ ] Ambiente = HOMOLOGAÇÃO
- [ ] Venda criada
- [ ] Clicou em "Emitir NFC-e"

---

## 🎉 Pronto!

Siga esses 3 passos e você conseguirá emitir NFC-e!

**Lembre-se:** Use ambiente de HOMOLOGAÇÃO para testes.











