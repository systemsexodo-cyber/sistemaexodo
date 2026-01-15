# 🔍 TESTE DIRETO DO CERTIFICADO DO WINDOWS

## ✅ O QUE FOI CORRIGIDO:

1. **Detecção de Windows melhorada** - Agora tenta múltiplas formas de detectar
2. **Fallback para Windows** - Se não conseguir detectar, assume Windows
3. **Logs detalhados** - Para identificar exatamente onde está falhando
4. **Sempre tenta executar** - Mesmo se não detectar Windows, tenta executar PowerShell

## 🧪 TESTE DIRETO:

Execute este comando no PowerShell para testar se o script funciona:

```powershell
cd "C:\Users\USER\Downloads\Sistema Exodo\sistema_exodo_01-12"
powershell -ExecutionPolicy Bypass -File testar_certificados_windows.ps1
```

Se funcionar, você verá a lista de certificados.

## 📋 LOGS PARA VERIFICAR:

Quando clicar no botão, procure no console por:

1. `>>> [AdicionarEmpresa] _buildCertificadoUpload - isWindows:`
2. `>>> [AdicionarEmpresa] Platform.isWindows =`
3. `>>> [AdicionarEmpresa] Platform.operatingSystem =`
4. `>>> [AdicionarEmpresa] _selecionarCertificadoWindows chamado`
5. `>>> [WindowsCert] Listando certificados do Windows...`
6. `>>> [WindowsCert] Executando PowerShell...`

## 🔧 SE AINDA NÃO FUNCIONAR:

Me envie TODOS os logs que começam com:
- `>>> [AdicionarEmpresa]`
- `>>> [WindowsCert]`

Com esses logs, posso identificar exatamente onde está falhando!




