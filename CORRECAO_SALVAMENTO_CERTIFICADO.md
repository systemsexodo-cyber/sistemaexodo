# ✅ CORREÇÃO: Certificado sempre salvo em base64

## 🔧 PROBLEMA IDENTIFICADO:

Quando o certificado era salvo como arquivo temporário, o `certificadoDigitalBytes` (base64) não estava sendo salvo. Isso fazia com que:

1. **Ao emitir NFC-e:** O sistema tentava ler do arquivo temporário
2. **Arquivo temporário deletado:** O arquivo pode ter sido deletado entre salvar e emitir
3. **Erro:** "Arquivo de certificado não encontrado"

## ✅ SOLUÇÃO IMPLEMENTADA:

### 1. **Certificado PFX:**
   - **SEMPRE** salva em base64, mesmo quando salva arquivo temporário
   - Garante que será carregado depois, mesmo se arquivo for deletado

### 2. **Certificado PEM (convertido):**
   - **SEMPRE** salva em base64
   - Usa prefixo `base64:pem:` na URL para identificação
   - Garante que será detectado como PEM na hora de carregar

### 3. **Certificado do Windows:**
   - Já estava salvando em base64 corretamente
   - Usa prefixo `windows:pem:` na URL

## 🧪 TESTE AGORA:

1. **Selecione um certificado PFX:**
   - Vá em "Empresas" → "Adicionar/Editar Empresa"
   - Selecione arquivo `.pfx`
   - Preencha senha
   - **Verifique os logs:**
     ```
     >>> [AdicionarEmpresa] Certificado salvo em base64: XXXX caracteres
     ```

2. **Salve a empresa:**
   - Clique em "Salvar"
   - **Verifique os logs:**
     ```
     >>> [AdicionarEmpresa] Carregando certificado da empresa:
     >>> [AdicionarEmpresa]   certificadoDigitalBytes: presente (XXXX chars)
     ```

3. **Emita NFC-e:**
   - Vá em "Venda Direta"
   - Adicione produtos
   - Clique em "Emitir NFC-e"
   - **Verifique os logs:**
     ```
     >>> [NFCe] certificadoDigitalBytes: presente (XXXX chars)
     >>> [Certificado] Certificado em base64 detectado
     >>> [Certificado] ✓✓✓ Detectado PEM em base64 (texto)
     >>> [NFCe] ✓✓✓ Certificado carregado com sucesso
     ```

## ✅ PRONTO!

Agora o certificado **SEMPRE** será salvo em base64, garantindo que será carregado corretamente na hora de emitir NFC-e!




