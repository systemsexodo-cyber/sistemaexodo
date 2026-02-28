# 🚀 Emissor NFC-e Exodo (Serviço Automático)

O sistema de emissão grátis agora funciona como um serviço inteligente que roda em segundo plano no Windows.

### ✅ O que foi instalado:
- **ExodoNfceBridge.exe**: Um aplicativo silencioso que fica ouvindo as requisições do PDV.
- **Início Automático**: Ele liga sozinho sempre que você liga o computador (registrado no Registro do Windows).
- **Sem Configuração Manual**: Você não precisa mais de arquivos `.json` ou pastas de certificados locais.

### 🛠️ Como usar:
1. **No seu App (PDV)**:
   - Vá em **Configurações da Empresa** -> **Certificado Digital**.
   - Faça o upload do arquivo `.pfx` e digite a senha.
   - O App enviará esses dados de forma segura para o emissor local em cada nota.
2. **Status**:
   - O emissor roda na porta `8000`. 
   - Se precisar reiniciar, o arquivo está em: `sistema_exodo_01-12\dist\ExodoNfceBridge.exe`.

### 🌐 Uso no Firebase (Produção)
Para que o site (HTTPS) fale com o seu computador local (HTTP):
1. Use um túnel como o **Zrok**: `zrok share public http://localhost:8000`.
2. Pegue o link gerado e coloque nas configurações do sistema no App.

### 📄 Manutenção:
Se quiser remover o início automático, execute este comando no PowerShell:
`REG DELETE "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" /V "ExodoNfceBridge" /F`
