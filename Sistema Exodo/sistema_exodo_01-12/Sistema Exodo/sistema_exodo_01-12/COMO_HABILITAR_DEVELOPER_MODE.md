# 🔧 Como Habilitar Developer Mode no Windows

## ⚠️ Problema

Se você recebeu a mensagem:
```
Building with plugins requires symlink support.
Please enable Developer Mode in your system settings.
```

Isso significa que o Flutter precisa de suporte a symlinks, que requer o Developer Mode.

## 🚀 Solução Rápida

### Método 1: Script Automático (Recomendado)

1. **Execute o script:**
   ```powershell
   .\habilitar_developer_mode.ps1
   ```

2. **Se pedir permissão de administrador:**
   - Clique com botão direito no PowerShell
   - Selecione "Executar como Administrador"
   - Execute o script novamente

3. **Nas configurações que abrirem:**
   - Vá em "Para desenvolvedores"
   - Ative "Modo de desenvolvedor"
   - Feche as configurações

### Método 2: Manual

1. **Abra as Configurações do Windows:**
   - Pressione `Windows + I`
   - Ou execute: `start ms-settings:developers`

2. **Navegue até:**
   - "Privacidade e segurança" → "Para desenvolvedores"
   - Ou procure por "Modo de desenvolvedor"

3. **Ative:**
   - Marque a opção "Modo de desenvolvedor"
   - Aceite os avisos se aparecerem

4. **Reinicie o terminal:**
   - Feche e abra novamente o PowerShell/CMD
   - Tente compilar novamente

## ✅ Verificar se Está Ativado

Execute no PowerShell:
```powershell
Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock" -Name "AllowDevelopmentWithoutDevLicense"
```

Se retornar `1`, está ativado!

## 🔄 Após Habilitar

1. **Reinicie o terminal** (importante!)
2. **Tente compilar novamente:**
   ```powershell
   flutter build windows
   ```

## 💡 Dica

O Developer Mode é necessário apenas uma vez. Depois de ativado, você não precisará fazer isso novamente.

---

**Nota:** O Developer Mode é seguro e não afeta o uso normal do Windows. Ele apenas permite recursos de desenvolvimento como symlinks.


