# ✅ Checklist: O Que Falta para Emitir NFC-e

## 🔴 BLOQUEADOR PRINCIPAL

### 1. Certificado Digital
- ❌ **PROBLEMA ATUAL**: Certificado não está carregando/processando
- ✅ **O QUE FAZER**: 
  - Edite a empresa
  - Selecione o certificado novamente
  - Certifique-se de que aparece "✓ Certificado processado"
  - Salve a empresa
  - Selecione a empresa novamente no PDV

---

## ✅ DADOS OBRIGATÓRIOS DA EMPRESA

### 2. CNPJ
- ✅ **Status**: Validado em `_validarDados`
- ✅ **Onde configurar**: Cadastro da Empresa → CNPJ
- ⚠️ **Verificar**: Se está preenchido e válido

### 3. Inscrição Estadual (IE)
- ✅ **Status**: Validado em `_validarDados`
- ✅ **Onde configurar**: Cadastro da Empresa → Inscrição Estadual
- ⚠️ **Verificar**: Se está preenchida

### 4. CRT (Regime Tributário)
- ✅ **Status**: Validado em `_validarDados`
- ✅ **Onde configurar**: Cadastro da Empresa → CRT
- ⚠️ **Valores aceitos**: 1 (Simples Nacional), 2 (Simples Nacional - Excesso), 3 (Regime Normal)

### 5. Senha do Certificado
- ✅ **Status**: Validado em `_validarDados`
- ✅ **Onde configurar**: Cadastro da Empresa → Senha do Certificado
- ⚠️ **Verificar**: Se está preenchida e correta

### 6. Endereço Completo
- ✅ **Status**: Necessário para gerar XML
- ✅ **Onde configurar**: Cadastro da Empresa → Endereço
- ⚠️ **Campos necessários**:
  - Estado (UF) - **OBRIGATÓRIO** para gerar chave de acesso
  - Cidade
  - CEP
  - Código IBGE (7 dígitos) - **RECOMENDADO**

### 7. Série NFC-e
- ✅ **Status**: Usa padrão "1" se não informado
- ✅ **Onde configurar**: Cadastro da Empresa → Série NFC-e
- ⚠️ **Valor padrão**: "1" (se não informado)

### 8. Ambiente (Homologação/Produção)
- ✅ **Status**: Configurável
- ✅ **Onde configurar**: Cadastro da Empresa → Ambiente
- ⚠️ **Padrão**: Homologação (true)

---

## 📋 DADOS PARA QR CODE (Opcional mas Recomendado)

### 9. CSC (Código de Segurança do Contribuinte)
- ⚠️ **Status**: **OPCIONAL** - necessário apenas para gerar QR Code
- ✅ **Onde configurar**: Cadastro da Empresa → CSC
- ⚠️ **Onde obter**: Fornecido pela SEFAZ do seu estado
- ⚠️ **Nota**: Se não tiver, o QR Code não será gerado, mas a NFC-e pode ser emitida

### 10. CSC ID Token
- ⚠️ **Status**: **OPCIONAL** - necessário apenas para gerar QR Code
- ✅ **Onde configurar**: Cadastro da Empresa → CSC ID Token
- ⚠️ **Onde obter**: Fornecido pela SEFAZ junto com o CSC
- ⚠️ **Nota**: Se não tiver, o QR Code não será gerado, mas a NFC-e pode ser emitida

---

## 📦 DADOS DOS PRODUTOS

### 11. NCM (Nomenclatura Comum do Mercosul)
- ✅ **Status**: Validado em `_validarDados`
- ✅ **Onde configurar**: Cadastro de Produto → NCM
- ⚠️ **Formato**: 8 dígitos (ex: 01012100)
- ⚠️ **Verificar**: Todos os produtos devem ter NCM

### 12. CFOP (Código Fiscal de Operações)
- ✅ **Status**: Validado em `_validarDados`
- ✅ **Onde configurar**: Cadastro de Produto → CFOP
- ⚠️ **Formato**: 4 dígitos (ex: 5102 para venda)
- ⚠️ **Verificar**: Todos os produtos devem ter CFOP

### 13. Origem
- ✅ **Status**: Validado em `_validarDados`
- ✅ **Onde configurar**: Cadastro de Produto → Origem
- ⚠️ **Valores aceitos**: 
  - 0 = Nacional
  - 1 = Estrangeira - Importação direta
  - 2 = Estrangeira - Adquirida no mercado interno
  - etc.
- ⚠️ **Verificar**: Todos os produtos devem ter Origem

---

## 🔧 FUNCIONALIDADES IMPLEMENTADAS

### ✅ Já Implementado:
1. ✅ Validação de dados obrigatórios
2. ✅ Geração de número sequencial da NFC-e
3. ✅ Geração de chave de acesso (44 dígitos)
4. ✅ Cálculo de dígito verificador
5. ✅ Montagem do XML da NFC-e
6. ✅ Assinatura digital do XML (quando certificado funcionar)
7. ✅ Comunicação com SEFAZ via SOAP
8. ✅ Processamento de retorno da SEFAZ
9. ✅ Geração de QR Code (quando CSC estiver configurado)
10. ✅ Geração de DANFE (Documento Auxiliar)

---

## 🚧 O QUE ESTÁ FALTANDO (Além do Certificado)

### 1. **CSC e CSC ID Token** (Para QR Code)
- ⚠️ **Status**: Opcional, mas recomendado
- 📝 **Como obter**: 
  - Acesse o portal da SEFAZ do seu estado
  - Solicite o CSC (Código de Segurança do Contribuinte)
  - Você receberá o CSC e o CSC ID Token
  - Configure na empresa

### 2. **Código IBGE do Município** (Recomendado)
- ⚠️ **Status**: Recomendado para validação
- 📝 **Como obter**: 
  - Busque no site do IBGE
  - Ou use o código de 7 dígitos do seu município
  - Configure na empresa

### 3. **Produtos com NCM, CFOP e Origem**
- ⚠️ **Status**: Obrigatório
- 📝 **Como configurar**: 
  - Edite cada produto
  - Preencha NCM (8 dígitos)
  - Preencha CFOP (4 dígitos)
  - Preencha Origem (0, 1, 2, etc.)
  - Salve o produto

---

## 📊 RESUMO DO QUE FALTA

### 🔴 BLOQUEADOR CRÍTICO:
1. ❌ **Certificado Digital** - Não está carregando/processando

### ⚠️ OBRIGATÓRIO (mas pode estar faltando):
2. ⚠️ **NCM** em todos os produtos
3. ⚠️ **CFOP** em todos os produtos
4. ⚠️ **Origem** em todos os produtos
5. ⚠️ **Estado (UF)** da empresa (para gerar chave de acesso)

### 📋 RECOMENDADO (mas não bloqueia):
6. 📋 **CSC** e **CSC ID Token** (para QR Code)
7. 📋 **Código IBGE** do município

---

## 🎯 PRÓXIMOS PASSOS

### Passo 1: Resolver Certificado
1. Edite a empresa
2. Selecione o certificado novamente
3. Salve a empresa
4. Selecione a empresa novamente no PDV

### Passo 2: Verificar Dados da Empresa
1. CNPJ ✓
2. Inscrição Estadual ✓
3. CRT ✓
4. Senha do Certificado ✓
5. Estado (UF) ✓
6. Endereço completo ✓

### Passo 3: Verificar Produtos
1. Todos têm NCM? ✓
2. Todos têm CFOP? ✓
3. Todos têm Origem? ✓

### Passo 4: Configurar CSC (Opcional)
1. Obter CSC da SEFAZ
2. Configurar na empresa
3. Configurar CSC ID Token

### Passo 5: Testar Emissão
1. Vá para o PDV
2. Adicione produtos ao carrinho
3. Finalize a venda
4. Tente emitir NFC-e
5. Verifique os logs no console

---

## 📝 NOTAS IMPORTANTES

1. **Ambiente de Homologação**: Por padrão, o sistema usa ambiente de homologação. Para produção, configure `ambienteHomologacao: false` na empresa.

2. **Série NFC-e**: Se não informado, usa "1" por padrão.

3. **QR Code**: Só será gerado se CSC e CSC ID Token estiverem configurados.

4. **Validação**: O sistema valida todos os dados obrigatórios antes de tentar emitir.

5. **Logs**: Sempre verifique os logs no console para ver exatamente onde está falhando.




