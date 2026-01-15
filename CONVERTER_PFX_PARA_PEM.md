# 🔄 Converter Certificado PFX para PEM (Solução Alternativa)

## ⚠️ Problema

O certificado está em formato PFX, mas o Flutter não consegue processar devido ao erro `_Namespace` da biblioteca `asn1lib`.

## ✅ Solução: Converter PFX para PEM

Converter o certificado PFX para formato PEM resolve o problema, pois o PEM é mais fácil de processar no Flutter.

---

## 📋 Passo a Passo

### **Pré-requisito: Instalar OpenSSL**

1. **Windows:**
   - Baixe: https://slproweb.com/products/Win32OpenSSL.html
   - Ou use Git Bash (já vem com OpenSSL)
   - Ou use WSL (Windows Subsystem for Linux)

2. **Linux/Mac:**
   - Já vem instalado na maioria dos sistemas
   - Verifique: `openssl version`

---

### **Conversão do Certificado**

#### **1. Extrair Certificado Público (.crt)**

```bash
openssl pkcs12 -in certificado.pfx -clcerts -nokeys -out certificado.crt
```

- Será solicitada a senha do PFX
- Gera o arquivo `certificado.crt`

#### **2. Extrair Chave Privada (.pem)**

```bash
openssl pkcs12 -in certificado.pfx -nocerts -nodes -out chave_privada.pem
```

- Será solicitada a senha do PFX
- A flag `-nodes` remove a senha da chave privada (opcional)
- Gera o arquivo `chave_privada.pem`

#### **3. (Opcional) Converter Chave Privada para Formato RSA**

```bash
openssl rsa -in chave_privada.pem -out chave_privada_rsa.pem
```

---

## 🔧 Usar no Flutter

Após converter, você terá:
- `certificado.crt` - Certificado público
- `chave_privada.pem` - Chave privada

Você pode processar esses arquivos PEM no Flutter usando bibliotecas como `pointycastle`.

---

## ⚡ Solução Rápida (Script)

Crie um arquivo `converter_certificado.bat` (Windows) ou `converter_certificado.sh` (Linux/Mac):

### **Windows (converter_certificado.bat):**
```batch
@echo off
echo Convertendo certificado PFX para PEM...
echo.

set /p arquivo_pfx="Digite o nome do arquivo PFX: "
set /p senha="Digite a senha do certificado: "

echo.
echo Extraindo certificado público...
openssl pkcs12 -in %arquivo_pfx% -clcerts -nokeys -out certificado.crt -passin pass:%senha%

echo.
echo Extraindo chave privada...
openssl pkcs12 -in %arquivo_pfx% -nocerts -nodes -out chave_privada.pem -passin pass:%senha%

echo.
echo Conversão concluída!
echo Arquivos gerados:
echo   - certificado.crt
echo   - chave_privada.pem
pause
```

### **Linux/Mac (converter_certificado.sh):**
```bash
#!/bin/bash
echo "Convertendo certificado PFX para PEM..."
echo

read -p "Digite o nome do arquivo PFX: " arquivo_pfx
read -sp "Digite a senha do certificado: " senha
echo

echo "Extraindo certificado público..."
openssl pkcs12 -in "$arquivo_pfx" -clcerts -nokeys -out certificado.crt -passin pass:"$senha"

echo
echo "Extraindo chave privada..."
openssl pkcs12 -in "$arquivo_pfx" -nocerts -nodes -out chave_privada.pem -passin pass:"$senha"

echo
echo "Conversão concluída!"
echo "Arquivos gerados:"
echo "  - certificado.crt"
echo "  - chave_privada.pem"
```

---

## 📝 Notas Importantes

- **Segurança:** Mantenha os arquivos PEM seguros (não commite no Git)
- **Senha:** Se usar `-nodes`, a chave privada não terá senha (menos seguro, mas mais fácil)
- **Formato:** PEM é texto base64, mais fácil de processar que binário PFX

---

## 🔄 Alternativa: Re-exportar PFX

Se não quiser converter, você pode re-exportar o PFX no software original:
1. Abra e-CPF/e-CNPJ Manager
2. Exporte novamente como PKCS#12
3. Use senha simples (só letras e números)
4. Não marque opções avançadas

---

**Nota:** A conversão para PEM é uma solução alternativa quando o PFX não pode ser processado diretamente pelo Flutter.




