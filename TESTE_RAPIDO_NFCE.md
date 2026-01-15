# ⚡ Teste Rápido - NFC-e em 5 Minutos

## 🎯 Objetivo: Emitir uma NFC-e de teste em 5 minutos

---

## ✅ Passo 1: Iniciar Backend (30 segundos)

### Windows:
```bash
cd backend_pynfe
INICIAR_AGORA.bat
```

### Ou manualmente:
```bash
cd backend_pynfe
python app.py
```

**Verificar:** Abra http://localhost:5000/health no navegador
**Deve aparecer:** `{"status": "ok", ...}`

---

## ✅ Passo 2: Verificar Configuração Flutter (1 minuto)

Arquivo: `lib/services/nfce_backend_service.dart`

Linha ~51 deve ter:
```dart
return 'http://localhost:5000';
```

Se estiver usando dispositivo físico, use o IP:
```dart
return 'http://192.168.1.XXX:5000';  // Seu IP
```

---

## ✅ Passo 3: Configurar Empresa Mínima (2 minutos)

No Flutter:
1. **Empresas** → **Nova Empresa** ou **Editar**
2. Preencha o MÍNIMO:
   - CNPJ: `12345678000190` (teste)
   - Razão Social: `Empresa Teste`
   - Inscrição Estadual: `123456789`
   - UF: `SP`
   - Código IBGE: `3550308` (São Paulo)
   - **Ambiente Homologação:** ✅ Marque
   - Certificado Digital: (upload do .pfx)
   - Senha do Certificado: (sua senha)

**IMPORTANTE:** Para teste, você pode usar um certificado de homologação válido.

---

## ✅ Passo 4: Criar Venda e Emitir (1 minuto)

1. Vá em **Venda Direta**
2. Adicione 1 produto qualquer
3. Finalize a venda
4. Clique em **Emitir NFC-e**

---

## 🎉 Resultado Esperado

Se tudo estiver OK:
- ✅ NFC-e será autorizada
- ✅ QR Code será exibido
- ✅ Chave de acesso será mostrada

Se der erro:
- ❌ Verifique os logs do backend Python
- ❌ Verifique os logs do Flutter (F12 → Console)
- ❌ Verifique se o certificado está válido

---

## 🐛 Problemas Rápidos

### Backend não inicia:
```bash
pip install -r requirements.txt
```

### "Failed to fetch":
- Backend rodando? → http://localhost:5000/health
- URL correta no Flutter?

### Certificado inválido:
- Use certificado válido
- Verifique senha
- Certificado deve estar no formato .pfx

---

## ✅ Checklist Ultra-Rápido

- [ ] Backend rodando (http://localhost:5000/health)
- [ ] URL configurada no Flutter
- [ ] Empresa com dados mínimos
- [ ] Certificado carregado
- [ ] Ambiente = HOMOLOGAÇÃO
- [ ] Venda criada
- [ ] Clicou em "Emitir NFC-e"

---

## 🎯 Se Funcionou:

✅ Parabéns! Você conseguiu emitir NFC-e!

**Próximos passos:**
1. Configure empresa real
2. Use certificado de produção (quando pronto)
3. Desmarque "Ambiente Homologação" para produção

---

## 🆘 Se Não Funcionou:

1. Veja logs do backend Python (terminal)
2. Veja logs do Flutter (F12 → Console)
3. Teste endpoint /health
4. Verifique certificado
5. Consulte `PROCESSO_COMPLETO_NFCE.md` para guia detalhado











