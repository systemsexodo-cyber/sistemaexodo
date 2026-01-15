# 🚨 INSTRUÇÕES MANUAIS: Configurar CORS no Firebase Storage

## ❌ Se o script falhou, siga estes passos MANUAIS:

### Passo 1: Acessar Google Cloud Console

1. Abra seu navegador
2. Acesse: **https://console.cloud.google.com/storage/browser**
3. Faça login com sua conta Google (a mesma do Firebase)

### Passo 2: Selecionar o Bucket

1. Na lista de buckets, procure por: **exodo-system.firebasestorage.app**
2. Clique no nome do bucket para abrir

### Passo 3: Abrir Configurações de CORS

1. No topo da página, clique no ícone de **⚙️ Configurações** (engrenagem)
2. Vá na aba **CORS**
3. Clique em **Editar** ou **Adicionar configuração CORS**

### Passo 4: Colar a Configuração

Cole **EXATAMENTE** este conteúdo no campo de texto:

```json
[
  {
    "origin": ["*"],
    "method": ["GET", "HEAD", "PUT", "POST", "DELETE", "OPTIONS"],
    "responseHeader": ["Content-Type", "Authorization", "Content-Length", "User-Agent", "X-Goog-Upload-Protocol", "X-Goog-Upload-Command", "X-Goog-Upload-Offset", "X-Goog-Upload-Status"],
    "maxAgeSeconds": 3600
  }
]
```

### Passo 5: Salvar

1. Clique em **Salvar** ou **Confirmar**
2. Aguarde a confirmação de que foi salvo

### Passo 6: Aguardar Propagação

- **Aguarde 1-2 minutos** para o CORS ser propagado
- O Firebase precisa atualizar os servidores

### Passo 7: Testar

1. **Limpe o cache do navegador:**
   - Pressione `Ctrl + Shift + Delete`
   - Selecione "Imagens e arquivos em cache"
   - Clique em "Limpar dados"

2. **Recarregue a página:**
   - Pressione `Ctrl + Shift + R` (hard refresh)

3. **Teste o upload de imagens novamente**

## ✅ Como Verificar se Funcionou

1. Abra o console do navegador (F12)
2. Vá na aba **Console**
3. Tente fazer upload de uma imagem
4. **NÃO deve aparecer mais erros de CORS**

Se ainda aparecer erro de CORS:
- Aguarde mais 2-3 minutos
- Verifique se colou a configuração corretamente
- Verifique se salvou as alterações

## 📸 Screenshots de Referência

Se precisar de ajuda visual:
1. O bucket aparece na lista como: `exodo-system.firebasestorage.app`
2. O ícone de configurações fica no topo direito
3. A aba CORS fica ao lado de "Visão geral", "Permissões", etc.

## 🔗 Links Úteis

- **Google Cloud Console:** https://console.cloud.google.com/storage/browser
- **Firebase Console:** https://console.firebase.google.com
- **Documentação CORS:** https://cloud.google.com/storage/docs/configuring-cors

