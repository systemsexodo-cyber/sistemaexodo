# 🔍 DEBUG: Seleção de Certificado do Windows

## ✅ TESTE REALIZADO:

O script PowerShell está funcionando e encontrou **11 certificados** com chave privada!

## 🔧 MELHORIAS IMPLEMENTADAS:

1. **Adicionado `runInShell: true`** - Importante para Windows
2. **Logs detalhados** - Para identificar onde está falhando
3. **Tratamento de erro melhorado** - Mensagens mais claras
4. **Validação de JSON** - Trata diferentes formatos de resposta

## 📋 PARA TESTAR:

1. **Reinicie o app completamente:**
   ```powershell
   flutter run
   ```

2. **Vá em "Empresas" → "Adicionar Empresa"**

3. **Clique em "Selecionar Certificado do Windows"**

4. **Verifique os logs no console:**
   - Procure por `>>> [WindowsCert]`
   - Procure por `>>> [AdicionarEmpresa]`

5. **Se não funcionar, me envie:**
   - Todos os logs que começam com `>>> [WindowsCert]`
   - Todos os logs que começam com `>>> [AdicionarEmpresa]`
   - Qualquer mensagem de erro que aparecer

## 🔍 POSSÍVEIS PROBLEMAS:

1. **PowerShell não encontrado:**
   - Verifique se PowerShell está no PATH
   - Tente executar `powershell` no terminal

2. **Permissões:**
   - O app precisa de permissão para executar PowerShell
   - Verifique se não há bloqueio de antivírus

3. **Encoding:**
   - O JSON pode ter problemas de encoding
   - Os logs vão mostrar o JSON recebido

## ✅ PRÓXIMOS PASSOS:

Teste agora e me envie os logs se não funcionar!




