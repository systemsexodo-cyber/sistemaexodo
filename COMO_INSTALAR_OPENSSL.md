# 🚀 Instalação Rápida do OpenSSL

## ⚡ Instalação Automática (Windows)

### Execute o script:

```powershell
.\instalar_openssl.ps1
```

O script vai:
1. ✅ Verificar se já está instalado
2. ✅ Verificar se tem Chocolatey/Scoop
3. ✅ Oferecer opções de instalação
4. ✅ Instalar automaticamente se possível

## ⚡ Instalação Automática (Linux/macOS)

### Execute o script:

```bash
chmod +x instalar_openssl.sh
./instalar_openssl.sh
```

O script detecta automaticamente:
- ✅ Ubuntu/Debian → usa `apt-get`
- ✅ Fedora/CentOS → usa `dnf` ou `yum`
- ✅ Arch Linux → usa `pacman`
- ✅ macOS → usa `brew` (se instalado)

## 📋 Instalação Manual

### Windows:

1. **Baixar:**
   - https://slproweb.com/products/Win32OpenSSL.html
   - Escolha: **Win64 OpenSSL** (versão LIGHT)

2. **Instalar:**
   - Execute o `.exe`
   - ✅ Marque "Add OpenSSL to PATH"
   - Instale em: `C:\Program Files\OpenSSL-Win64\`

3. **Verificar:**
   ```powershell
   openssl version
   ```

### Linux:

```bash
# Ubuntu/Debian
sudo apt-get update && sudo apt-get install openssl

# Fedora/CentOS
sudo dnf install openssl

# Arch
sudo pacman -S openssl
```

### macOS:

```bash
# Com Homebrew
brew install openssl

# Ou com MacPorts
sudo port install openssl
```

## ✅ Verificar Instalação

```bash
# Windows
openssl version

# Linux/macOS
openssl version
```

**Deve mostrar:** `OpenSSL 3.0.x` ou `OpenSSL 1.1.x`

## 🎯 Depois de Instalar

1. **Reinicie o aplicativo Flutter**
2. **Teste:** Selecione um arquivo `.pfx`
3. **Resultado:** O sistema converterá automaticamente para PEM!

## 💡 Dica

Se você tem **Git instalado**, o OpenSSL já está disponível em:
- Windows: `C:\Program Files\Git\usr\bin\openssl.exe`
- O sistema detecta automaticamente!

## ❓ Problemas?

Veja o arquivo `INSTALAR_OPENSSL.md` para instruções detalhadas.




