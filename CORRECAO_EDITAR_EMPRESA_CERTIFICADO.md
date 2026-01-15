# ✅ CORREÇÃO: Certificado do Windows ao Editar Empresa

## 🔧 O QUE FOI CORRIGIDO:

1. **Carregamento do thumbprint** - Agora carrega o thumbprint do Windows quando edita empresa
2. **Salvamento do thumbprint** - Salva o thumbprint e subject do certificado nas configurações
3. **Nome do certificado** - Mostra nome correto quando certificado vem do Windows
4. **Limpeza ao remover** - Remove todos os dados do certificado (incluindo thumbprint) ao clicar em remover

## 📋 COMO FUNCIONA AGORA:

### Ao Editar Empresa:
- Se a empresa já tem certificado do Windows, o thumbprint é carregado
- O nome do certificado é exibido corretamente
- Você pode trocar o certificado selecionando um novo

### Ao Selecionar Certificado do Windows:
1. Lista todos os certificados disponíveis
2. Você seleciona um certificado
3. Digita a senha
4. O sistema exporta e salva:
   - Thumbprint (para identificar o certificado)
   - Subject (nome do certificado)
   - Conteúdo PEM ou caminho do PFX

### Ao Salvar:
- Thumbprint é salvo em `configuracoes['certificadoWindowsThumbprint']`
- Subject é salvo em `configuracoes['certificadoWindowsSubject']`
- Conteúdo PEM é salvo em `configuracoes['certificadoDigitalBytes']`

## 🚀 TESTE AGORA:

1. **Edite uma empresa existente**
2. **Clique em "Selecionar Certificado do Windows"**
3. **Selecione um certificado da lista**
4. **Digite a senha**
5. **Salve a empresa**
6. **Edite novamente** - O certificado deve aparecer corretamente!

## ✅ PRONTO!

Agora você pode adicionar/editar certificado do Windows em empresas existentes sem problemas!




