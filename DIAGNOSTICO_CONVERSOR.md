# 🔍 Diagnóstico: Conversor Não Funcionou

## ❓ Qual foi o erro específico?

Por favor, me diga qual desses erros apareceu:

### Erro 1: "OpenSSL não encontrado"
**Solução:** Execute primeiro:
```powershell
.\instalar_openssl.ps1
```

### Erro 2: "Senha incorreta" ou "mac verify failure"
**Solução:** Verifique se a senha está correta

### Erro 3: "Arquivo não encontrado"
**Solução:** Verifique se o caminho do certificado está correto

### Erro 4: Script não executa (erro de permissão)
**Solução:** Execute no PowerShell:
```powershell
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process
.\converter_certificado_simples.ps1
```

### Erro 5: Outro erro
**Solução:** Copie a mensagem de erro completa e me envie

## 🚀 Scripts Disponíveis:

### Script 1: PowerShell Simples (Recomendado)
```powershell
.\converter_certificado_simples.ps1
```

### Script 2: Batch (Mais Simples)
```cmd
.\converter_rapido.bat
```

### Script 3: Manual (Mais Controle)
```powershell
.\converter_certificado_manual.ps1
```

## 💡 Conversão Manual Direta:

Se os scripts não funcionarem, você pode converter diretamente:

```powershell
& "C:\Program Files\Git\usr\bin\openssl.exe" pkcs12 -in "CAMINHO_DO_CERTIFICADO.pfx" -out "certificado.pem" -nodes -passin pass:SUA_SENHA
```

Substitua:
- `CAMINHO_DO_CERTIFICADO.pfx` pelo caminho completo do seu certificado
- `SUA_SENHA` pela senha do certificado

## 📋 Me Envie:

1. Qual script você tentou usar?
2. Qual foi a mensagem de erro exata?
3. O caminho do certificado está correto?
4. A senha está correta?

Com essas informações, posso ajudar melhor!




