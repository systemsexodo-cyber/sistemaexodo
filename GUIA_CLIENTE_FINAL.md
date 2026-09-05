# 📋 Guia do Cliente Final - Emissão NFC-e 100% Local

## 🎯 O que mudou?
Seu sistema agora emite NFC-e **100% localmente** no computador, sem depender de internet ou servidores externos.

---

## 🔧 Instalação do Emissor Local

### 1️⃣ Download do Bridge NFC-e
- **Arquivo**: `ExodoNfceBridge.exe`
- **Tamanho**: ~15MB
- **Requisitos**: Windows 10+ com .NET Framework 4.8

### 2️⃣ Instalação
```
1. Crie a pasta: C:\ExodoNFCe\
2. Copie ExodoNfceBridge.exe para esta pasta
3. Dê duplo clique no arquivo para executar
```

### 3️⃣ Configuração de Firewall (se necessário)
- Permita acesso na rede privada para `ExodoNfceBridge.exe`
- Porta utilizada: 8000 (padrão)

---

## 🚀 Como Usar

### Passo 1: Iniciar o Emissor
1. Abra o `ExodoNfceBridge.exe`
2. Mantenha o programa **sempre aberto** enquanto emite NFC-e
3. Você verá uma janela de console com "Servidor rodando na porta 8000"

### Passo 2: Usar o Sistema
1. Abra o aplicativo do sistema
2. O sistema detectará **automaticamente** o emissor local
3. Realize vendas normalmente
4. Ao emitir NFC-e, o sistema usará o emissor local

---

## ✅ Verificação de Status

O sistema mostra automaticamente o status do emissor:

### 🟢 Emissor Online
```
✅ Emissor NFC-e Online
URL: http://localhost:8000
```
**Significado**: Tudo pronto para emitir NFC-e

### 🟡 Emissor Parado
```
⚠️ Emissor NFC-e Parado
Caminho: C:\ExodoNFCe\ExodoNfceBridge.exe
```
**Solução**: Clique em "Iniciar Emissor" ou abra manualmente

### 🔴 Emissor Não Instalado
```
❌ Emissor NFC-e Não Instalado
```
**Solução**: Siga as instruções de instalação abaixo

---

## 📱 Salvamento dos Dados

Seus dados são salvos **automaticamente** em dois locais:

### 💾 Local (Offline)
- **Onde**: SQLite no computador
- **Quando**: Sempre, mesmo sem internet
- **Vantagem**: Nunca perde dados

### ☁️ Nuvem (Online)
- **Onde**: Supabase (servidor)
- **Quando**: Quando tiver internet
- **Vantagem**: Backup e acesso remoto

---

## 🛠️ Solução de Problemas

### Problema: "Não foi possível conectar ao Emissor"
**Causas**: Bridge não está rodando
**Solução**:
1. Verifique se `ExodoNfceBridge.exe` está aberto
2. Reinicie o bridge
3. Verifique firewall

### Problema: "Bridge não encontrado"
**Causas**: Bridge não está instalado
**Solução**:
1. Verifique se está em `C:\ExodoNFCe\`
2. Faça download novamente
3. Reinstale na pasta correta

### Problema: Porta 8000 em uso
**Solução**:
1. Feche outros programas usando a porta 8000
2. Ou use porta diferente (configurar no sistema)

---

## 📋 Estrutura de Pastas Recomendada

```
C:\ExodoNFCe\
├── ExodoNfceBridge.exe          ← Emissor NFC-e
├── certificados\                ← Certificados digitais
│   ├── certificado.pfx
│   └── senha.txt
└── logs\                       ← Logs do emissor
    └── bridge.log
```

---

## 🔐 Certificado Digital

O certificado digital deve estar:
- **Formato**: .pfx ou .p12
- **Local**: Configurado no cadastro da empresa
- **Validade**: Dentro do prazo de validade

---

## 📞 Suporte

### Problemas Comuns:
| Problema | Solução Rápida |
|----------|----------------|
| Bridge não inicia | Verifique .NET Framework 4.8 |
| Erro de certificado | Verifique senha e validade |
| Falha na emissão | Verifique conexão com SEFAZ |
| Dados não salvos | Verifique espaço em disco |

### Contato:
- 📧 Email: suporte@exodo.com.br
- 📱 WhatsApp: (11) 99999-9999
- 🌐 Help Desk: https://ajuda.exodo.com.br

---

## ✅ Checklist de Instalação

- [ ] Baixar `ExodoNfceBridge.exe`
- [ ] Criar pasta `C:\ExodoNFCe\`
- [ ] Copiar bridge para a pasta
- [ ] Configurar firewall (se necessário)
- [ ] Testar execução do bridge
- [ ] Verificar detecção no sistema
- [ ] Configurar certificado digital
- [ ] Realizar teste de emissão

---

## 🎉 Benefícios da Migração

✅ **Funciona Offline** - Emite mesmo sem internet  
✅ **Mais Rápido** - Comunicação local é mais rápida  
✅ **100% Seguro** - Dados ficam no seu computador  
✅ **Sem Dependências** - Não depende de servidores externos  
✅ **Backup Automático** - Dados salvos em nuvem quando online  

---

**Pronto!** Seu sistema agora está totalmente independente e pronto para uso 100% local.
