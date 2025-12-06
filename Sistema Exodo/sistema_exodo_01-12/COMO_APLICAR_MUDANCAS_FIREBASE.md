# Como Aplicar Novas Mudanças no Firebase Hosting

## 📋 Passo a Passo para Aplicar Mudanças no Firebase

### 1️⃣ Verificar se o Deploy foi Feito

O deploy já foi feito via linha de comando. Para verificar no console:

1. Acesse: https://console.firebase.google.com/project/exodosystems-1541d/hosting
2. Clique em "Hosting" no menu lateral
3. Veja a seção "Deploy history" - deve mostrar o deploy mais recente

### 2️⃣ Limpar Cache do Navegador

**IMPORTANTE**: O navegador pode estar usando cache da versão antiga!

**No Chrome/Edge:**
- Pressione `Ctrl + Shift + Delete`
- Selecione "Cookies e outros dados do site" e "Imagens e arquivos em cache"
- Clique em "Limpar dados"
- Ou pressione `Ctrl + Shift + R` para hard refresh

**Ou use Modo Anônimo:**
- Pressione `Ctrl + Shift + N` (Chrome) ou `Ctrl + Shift + P` (Edge)
- Acesse: https://exodosystems-1541d.web.app

### 3️⃣ Verificar no Console do Firebase

1. Acesse: https://console.firebase.google.com/project/exodosystems-1541d/hosting
2. Clique na aba "Deploy history"
3. Verifique se o deploy mais recente está listado
4. Clique no deploy para ver os detalhes

### 4️⃣ Aguardar Propagação do CDN

O Firebase usa CDN (Content Delivery Network) que pode levar:
- **2-5 minutos** para propagação inicial
- **Até 10 minutos** para propagação global completa

### 5️⃣ Verificar Versão no Site

Para confirmar que está vendo a versão nova:
1. Abra: https://exodosystems-1541d.web.app
2. Pressione `F12` para abrir o console do navegador
3. Vá na aba "Network"
4. Recarregue a página (`Ctrl + R`)
5. Veja o arquivo `main.dart.js` - verifique a data/hora do arquivo

### 6️⃣ Forçar Nova Versão (se necessário)

Se ainda não aparecer, você pode:

1. **Fazer novo deploy via Console:**
   - Acesse: https://console.firebase.google.com/project/exodosystems-1541d/hosting
   - Clique em "Add another site" ou use a interface para fazer upload

2. **Ou fazer novo deploy via linha de comando:**
   ```powershell
   cd sistema_exodo_01-12
   flutter build web --release
   firebase deploy --only hosting --project exodosystems-1541d
   ```

## ⚠️ Problemas Comuns

### Problema: Site mostra versão antiga
**Solução**: Limpar cache do navegador + Aguardar 5-10 minutos

### Problema: Deploy não aparece no console
**Solução**: Verificar se está usando o projeto correto (`exodosystems-1541d`)

### Problema: Alterações não compilam
**Solução**: Verificar se o código está na branch `modo-dev` e fazer rebuild completo

## ✅ Checklist Final

- [ ] Código está na branch `modo-dev`
- [ ] Build foi feito com sucesso
- [ ] Deploy foi concluído
- [ ] Cache do navegador foi limpo
- [ ] Aguardou 5-10 minutos após deploy
- [ ] Testou em modo anônimo/privado

## 🔗 Links Úteis

- Console Firebase: https://console.firebase.google.com/project/exodosystems-1541d/hosting
- Site: https://exodosystems-1541d.web.app
- Documentação Firebase Hosting: https://firebase.google.com/docs/hosting



