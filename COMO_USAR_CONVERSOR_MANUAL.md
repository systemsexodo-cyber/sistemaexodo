# 📖 Como Usar o Conversor Manual de Certificado

## 🚀 Uso Rápido:

### Opção 1: Modo Interativo (Recomendado)

1. Abra o PowerShell
2. Navegue até a pasta do projeto:
   ```powershell
   cd "C:\Users\USER\Downloads\Sistema Exodo\sistema_exodo_01-12"
   ```
3. Execute o script:
   ```powershell
   .\converter_certificado_manual.ps1
   ```
4. O script vai pedir:
   - Caminho do certificado PFX
   - Senha do certificado (oculta)

### Opção 2: Com Parâmetros

Execute diretamente com o caminho e senha:

```powershell
.\converter_certificado_manual.ps1 -CaminhoCertificado "C:\caminho\certificado.pfx" -Senha "sua_senha"
```

## 📋 Exemplo Completo:

```powershell
# Navegar até a pasta
cd "C:\Users\USER\Downloads\Sistema Exodo\sistema_exodo_01-12"

# Executar o script
.\converter_certificado_manual.ps1 -CaminhoCertificado "C:\Users\USER\Downloads\certificado.pfx" -Senha "minhasenha123"
```

## ✅ O que o script faz:

1. **Verifica se o arquivo existe**
2. **Procura OpenSSL** automaticamente
3. **Extrai o certificado público** (.crt)
4. **Extrai a chave privada** (.pem)
5. **Combina em um arquivo PEM** completo
6. **Limpa arquivos intermediários**
7. **Mostra o caminho do arquivo gerado**

## 📁 Arquivos Gerados:

- `certificado.pem` - Arquivo final combinado (use este no sistema)

## 🔍 Se der erro:

### Erro: "OpenSSL não encontrado"
**Solução:** Execute `.\instalar_openssl.ps1` primeiro

### Erro: "Senha incorreta"
**Solução:** Verifique a senha do certificado

### Erro: "Certificado corrompido"
**Solução:** Re-exporte o certificado do e-CPF/e-CNPJ Manager

## 💡 Dica:

Se você não souber o caminho exato do certificado, use o modo interativo e cole o caminho quando solicitado.

## 🎯 Após a conversão:

1. Vá em "Empresas" → Edite a empresa
2. Remova o certificado antigo (PFX)
3. Selecione o arquivo `.pem` gerado
4. Salve e tente emitir NFC-e novamente




