# 🔧 Como Instalar OpenSSL para Conversão Automática de Certificados

## 🪟 Windows

### Opção 1: Instalador Oficial (RECOMENDADO)

1. **Baixar OpenSSL:**
   - Acesse: https://slproweb.com/products/Win32OpenSSL.html
   - Baixe a versão **Win64 OpenSSL** (recomendado) ou Win32
   - Escolha a versão **LIGHT** (menor tamanho) ou **FULL**

2. **Instalar:**
   - Execute o instalador `.exe`
   - **IMPORTANTE:** Durante a instalação, escolha:
     - ✅ "Copy OpenSSL DLLs to: The OpenSSL binaries (/bin) directory"
     - ✅ Marque "Add OpenSSL to the system PATH for all users" (ou "for current user")
   - Instale em: `C:\Program Files\OpenSSL-Win64\` (padrão)

3. **Verificar Instalação:**
   - Abra PowerShell ou CMD
   - Execute: `openssl version`
   - Deve mostrar a versão do OpenSSL

### Opção 2: Chocolatey (Se já tiver instalado)

```powershell
choco install openssl
```

### Opção 3: Scoop (Se já tiver instalado)

```powershell
scoop install openssl
```

### Opção 4: Git Bash (Já vem com OpenSSL)

Se você tem Git instalado, o OpenSSL já está disponível em:
- `C:\Program Files\Git\usr\bin\openssl.exe`

O sistema detecta automaticamente!

## 🐧 Linux

### Ubuntu/Debian:

```bash
sudo apt-get update
sudo apt-get install openssl
```

### Fedora/CentOS/RHEL:

```bash
sudo dnf install openssl
# ou
sudo yum install openssl
```

### Arch Linux:

```bash
sudo pacman -S openssl
```

### Verificar:

```bash
openssl version
```

## 🍎 macOS

### Opção 1: Homebrew (RECOMENDADO)

```bash
brew install openssl
```

### Opção 2: MacPorts

```bash
sudo port install openssl
```

### Verificar:

```bash
openssl version
```

## ✅ Verificar se Está Funcionando

### Windows:
```powershell
openssl version
```

### Linux/macOS:
```bash
openssl version
```

**Deve mostrar algo como:**
```
OpenSSL 3.0.x or 1.1.x
```

## 🔍 O Sistema Detecta Automaticamente

O código já procura OpenSSL em vários lugares:

### Windows:
- ✅ PATH do sistema
- ✅ `C:\Program Files\Git\usr\bin\openssl.exe`
- ✅ `C:\Program Files\OpenSSL-Win64\bin\openssl.exe`
- ✅ `C:\Program Files (x86)\OpenSSL-Win32\bin\openssl.exe`
- ✅ Chocolatey e Scoop

### Linux/macOS:
- ✅ `/usr/bin/openssl`
- ✅ `/usr/local/bin/openssl`
- ✅ `/opt/homebrew/bin/openssl` (macOS Homebrew)

## 🚀 Depois de Instalar

1. **Reinicie o aplicativo Flutter** (se estiver rodando)
2. **Teste a conversão:**
   - Selecione um arquivo `.pfx`
   - O sistema tentará converter automaticamente
   - Se funcionar, você verá: "✓ Certificado convertido para PEM automaticamente!"

## ❌ Se Não Funcionar

### Windows - Adicionar ao PATH Manualmente:

1. Abra "Variáveis de Ambiente"
2. Edite a variável `Path`
3. Adicione: `C:\Program Files\OpenSSL-Win64\bin`
4. Reinicie o terminal/aplicativo

### Verificar Caminho:

```powershell
# Windows
where.exe openssl

# Linux/macOS
which openssl
```

## 📝 Notas Importantes

- **Windows:** Pode precisar reiniciar o terminal após instalar
- **Linux/macOS:** Geralmente já vem instalado
- **Git Bash:** Se tiver Git, OpenSSL já está disponível
- **PATH:** Certifique-se de que OpenSSL está no PATH do sistema

## 🎯 Próximos Passos

Após instalar, o sistema:
1. ✅ Detecta automaticamente o OpenSSL
2. ✅ Converte PFX → PEM automaticamente
3. ✅ Processa o certificado sem erros

**Não precisa fazer mais nada! O código já está preparado!**




