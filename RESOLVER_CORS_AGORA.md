# 🚨 RESOLVER CORS AGORA - Passo a Passo

## ❌ Erro que você está vendo:

```
Access to XMLHttpRequest at 'https://firebasestorage.googleapis.com/...' 
from origin 'http://localhost:54205' has been blocked by CORS policy
```

## ✅ SOLUÇÃO: Configure CORS Manualmente

### Passo 1: Abrir Google Cloud Console

1. Abra este link no navegador:
   **https://console.cloud.google.com/storage/browser?project=exodo-system**

2. Faça login com sua conta Google (mesma do Firebase)

### Passo 2: Encontrar o Bucket

1. Na lista de buckets, procure por:
   **exodo-system.firebasestorage.app**

2. **Clique no nome do bucket** para abrir

### Passo 3: Abrir Configurações

1. No topo da página, procure pelo ícone de **⚙️ Configurações** (engrenagem)
2. Clique nele
3. Vá na aba **CORS** (pode estar em "Configurações" ou "Permissions")

### Passo 4: Adicionar Configuração CORS

1. Se já houver uma configuração CORS, clique em **Editar**
2. Se não houver, clique em **Adicionar configuração CORS** ou **Edit CORS configuration**

3. **DELETE tudo** que estiver no campo de texto

4. **COLE EXATAMENTE** este conteúdo:

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

1. Clique em **Salvar** ou **Save**
2. Aguarde a confirmação de que foi salvo

### Passo 6: Aguardar Propagação

- **Aguarde 2-3 minutos** para o CORS ser propagado nos servidores do Google

### Passo 7: Limpar Cache e Testar

1. **Feche TODAS as abas** do navegador com o app
2. **Limpe o cache:**
   - Pressione `Ctrl + Shift + Delete`
   - Selecione "Imagens e arquivos em cache"
   - Marque "Desde sempre"
   - Clique em "Limpar dados"

3. **Abra o app novamente**

4. **Teste o upload de uma imagem**

## ✅ Como Saber se Funcionou

1. Abra o console do navegador (F12)
2. Vá na aba **Console**
3. Tente fazer upload de uma imagem
4. **NÃO deve aparecer mais o erro de CORS**

Se ainda aparecer:
- Aguarde mais 2-3 minutos
- Verifique se salvou corretamente no Google Cloud Console
- Verifique se colou o JSON completo

## 🔗 Link Direto

Se o link acima não funcionar, tente:
- https://console.cloud.google.com/storage/browser
- Depois selecione o projeto: **exodo-system**
- Depois selecione o bucket: **exodo-system.firebasestorage.app**

## 📝 Nota Importante

**CORS é diferente de Regras do Firebase Storage!**

- **Regras do Storage** = Permissões (quem pode ler/escrever)
- **CORS** = Permissões de origem (de onde pode fazer requisições)

Ambos precisam estar configurados corretamente!

