# 🔄 Como Converter Certificado PFX para PEM

## ⚡ Método Rápido (Windows)

### **Opção 1: Usar o Script Automático**

1. **Execute o arquivo:**
   ```
   converter_certificado.bat
   ```

2. **Siga as instruções:**
   - Digite o caminho completo do arquivo PFX
   - Digite a senha do certificado
   - Aguarde a conversão

3. **Arquivos gerados:**
   - `certificado.crt` (certificado público)
   - `certificado_chave_privada.pem` (chave privada)

---

### **Opção 2: Usar Git Bash (se tiver Git instalado)**

1. **Abra Git Bash**
2. **Navegue até a pasta do certificado:**
   ```bash
   cd "C:\caminho\para\certificado"
   ```
3. **Execute os comandos:**
   ```bash
   openssl pkcs12 -in certificado.pfx -clcerts -nokeys -out certificado.crt
   openssl pkcs12 -in certificado.pfx -nocerts -nodes -out chave_privada.pem
   ```
4. **Digite a senha quando solicitado**

---

### **Opção 3: Usar PowerShell (se OpenSSL estiver instalado)**

1. **Abra PowerShell**
2. **Execute os comandos:**
   ```powershell
   openssl pkcs12 -in certificado.pfx -clcerts -nokeys -out certificado.crt
   openssl pkcs12 -in certificado.pfx -nocerts -nodes -out chave_privada.pem
   ```

---

## 🐧 Método Linux/Mac

### **Usar o Script Automático:**

1. **Dê permissão de execução:**
   ```bash
   chmod +x converter_certificado.sh
   ```

2. **Execute:**
   ```bash
   ./converter_certificado.sh
   ```

3. **Siga as instruções**

---

## 📋 O Que Você Precisa

- **Arquivo PFX** (.pfx ou .p12)
- **Senha do certificado**
- **OpenSSL instalado** (já vem com Git Bash ou WSL)

---

## ✅ Após a Conversão

Você terá dois arquivos:

1. **certificado.crt** - Certificado público (pode ser usado no Flutter)
2. **chave_privada.pem** - Chave privada (pode ser usada no Flutter)

**NOTA:** A chave privada não terá senha (flag `-nodes`). Mantenha os arquivos seguros!

---

## 🔍 Verificar se Funcionou

1. **Verifique se os arquivos foram criados**
2. **Abra o arquivo .crt em um editor de texto:**
   - Deve começar com `-----BEGIN CERTIFICATE-----`
   - Deve terminar com `-----END CERTIFICATE-----`

3. **Abra o arquivo .pem em um editor de texto:**
   - Deve começar com `-----BEGIN PRIVATE KEY-----` ou `-----BEGIN RSA PRIVATE KEY-----`
   - Deve terminar com `-----END PRIVATE KEY-----` ou `-----END RSA PRIVATE KEY-----`

---

## ❓ Problemas Comuns

### **"OpenSSL não encontrado"**
- **Windows:** Instale em https://slproweb.com/products/Win32OpenSSL.html
- **Ou use Git Bash** (já vem com OpenSSL)
- **Ou use WSL** (Windows Subsystem for Linux)

### **"Senha incorreta"**
- Verifique se digitou a senha correta
- Tente abrir o certificado em outro software para confirmar

### **"Arquivo não encontrado"**
- Use o caminho completo do arquivo
- Verifique se o arquivo existe
- No Windows, use aspas se o caminho tiver espaços

---

## 💡 Dica

Se você não tem OpenSSL instalado, a forma mais fácil é usar **Git Bash** (se tiver Git instalado), pois ele já vem com OpenSSL.

---

**Pronto!** Após converter, você pode usar os arquivos PEM no Flutter.




