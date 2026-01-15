# 🔐 Converter Certificado Digital para Base64

## 🚀 Forma Rápida (Script)

```bash
# Opção 1: Passar caminho como argumento
python converter_certificado.py "C:\caminho\para\certificado.pfx"

# Opção 2: Executar e digitar o caminho
python converter_certificado.py
```

## 📝 Forma Manual (Uma Linha)

```bash
# Windows PowerShell
python -c "import base64; print(base64.b64encode(open('certificado.pfx', 'rb').read()).decode('utf-8'))"

# Com caminho completo
python -c "import base64; print(base64.b64encode(open(r'C:\caminho\certificado.pfx', 'rb').read()).decode('utf-8'))"
```

## 💡 Exemplo de Uso

### 1. Executar o script:
```bash
python converter_certificado.py
```

### 2. Quando pedir, digite o caminho:
```
Digite o caminho do certificado (.pfx ou .p12): C:\Users\SeuUsuario\certificado.pfx
```

### 3. Resultado:
- ✅ Certificado em Base64 exibido no terminal
- ✅ Salvo em `certificado_base64.txt`

### 4. Copiar e colar no código:
```python
CERTIFICADO_BASE64 = "MIIKpAIBAzCCCl4GCSqGSIb3DQEHAaCCCk8EggpLMIIKRzCCBX..."
```

## ⚠️ Dicas

- Use caminho absoluto se o arquivo não estiver na pasta atual
- Pode usar `.pfx` ou `.p12` (ambos funcionam)
- O script salva o resultado em `certificado_base64.txt` também
- Certifique-se de que o certificado não está protegido por senha adicional no sistema

## 🔒 Segurança

⚠️ **IMPORTANTE:** 
- Não compartilhe o certificado Base64 publicamente
- Não commite no Git sem criptografia
- Use variáveis de ambiente em produção

---

**Pronto para usar!** 🎉

















