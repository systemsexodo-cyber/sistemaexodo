# Requisitos para Emissão de NFC-e (Nota Fiscal de Consumidor Eletrônica)

## 📋 Resumo dos Requisitos Legais e Técnicos

### ✅ **O que já temos no sistema:**

#### **Dados da Empresa (Cadastro):**
- ✅ Razão Social
- ✅ Nome Fantasia
- ✅ CNPJ
- ✅ Inscrição Estadual
- ✅ Inscrição Municipal
- ✅ Regime Tributário (recém adicionado)
- ✅ Endereço completo (rua, número, complemento, bairro, cidade, estado, CEP)
- ✅ Contatos (email, telefone, celular)

#### **Dados dos Produtos:**
- ✅ NCM (Nomenclatura Comum do Mercosul) - **OBRIGATÓRIO**
- ✅ Código de Barras (GTIN/EAN)
- ✅ Origem da Mercadoria (0-Nacional, 1-Estrangeira, etc) - **OBRIGATÓRIO**
- ✅ CFOP (Código Fiscal de Operações) - **OBRIGATÓRIO**
- ✅ CEST (quando aplicável)
- ✅ ICMS (Alíquota e CST) - **OBRIGATÓRIO**
- ✅ IPI (Alíquota e CST)
- ✅ PIS (Alíquota e CST)
- ✅ COFINS (Alíquota e CST)
- ✅ CSOSN (Simples Nacional) - **OBRIGATÓRIO para Simples Nacional**
- ✅ Alíquota Simples Nacional

---

## ❌ **O que ainda falta implementar:**

### **1. Dados da Empresa (Faltantes):**
- ❌ **Código IBGE do Município** (obrigatório)
- ❌ **Código IBGE do Estado** (obrigatório)
- ❌ **Código de Regime Tributário (CRT)** - numérico:
  - 1 = Simples Nacional
  - 2 = Simples Nacional - Excesso de Sublimite
  - 3 = Regime Normal
- ❌ **Certificado Digital** (A1 ou A3) - arquivo .pfx ou token
- ❌ **Senha do Certificado Digital**
- ❌ **Ambiente** (1=Produção, 2=Homologação)
- ❌ **CSC (Código de Segurança do Contribuinte)** - fornecido pela SEFAZ
- ❌ **ID Token CSC** - fornecido pela SEFAZ

### **2. Configurações de Emissão:**
- ❌ **Série da NFC-e** (geralmente 1)
- ❌ **Numeração sequencial** (controle de numeração)
- ❌ **Modelo da NFC-e** (65 para NFC-e)
- ❌ **Versão do XML** (4.00)
- ❌ **URL da SEFAZ** (varia por estado)
- ❌ **Configuração de impressora** (para DANFE-NFC-e)

### **3. Dados do Cliente (para NFC-e):**
- ❌ **CPF/CNPJ do consumidor** (opcional, mas recomendado)
- ❌ **Nome do consumidor** (opcional)
- ❌ **Email do consumidor** (para envio da NFC-e)

### **4. Dados Adicionais dos Produtos:**
- ❌ **Unidade Comercial (uCom)** - código da unidade de medida (UN, KG, etc)
- ❌ **Unidade Tributável (uTrib)** - código da unidade tributável
- ❌ **Valor Unitário de Comercialização**
- ❌ **Valor Unitário de Tributação**
- ❌ **Valor Total dos Tributos** (quando aplicável)
- ❌ **Informações Adicionais do Produto** (observações)

### **5. Dados da Venda:**
- ❌ **Forma de Pagamento** (dinheiro, cartão, etc) - já temos parcialmente
- ❌ **Troco** (quando aplicável)
- ❌ **Informações Adicionais da Venda**
- ❌ **Data/Hora de Emissão** (timestamp preciso)

### **6. Integração Técnica:**
- ❌ **Biblioteca de comunicação com SEFAZ** (ex: NFePHP, Focus NFe, etc)
- ❌ **Geração de XML** conforme layout da NFC-e
- ❌ **Assinatura digital do XML** (usando certificado A1/A3)
- ❌ **Envio para SEFAZ** (WebService SOAP)
- ❌ **Tratamento de retorno** (autorização, rejeição, denegação)
- ❌ **Geração do QR Code** (para consulta pública)
- ❌ **Geração do DANFE-NFC-e** (impressão)
- ❌ **Contingência offline** (quando SEFAZ estiver indisponível)

---

## 🔧 **Requisitos Técnicos Externos:**

### **1. Certificado Digital ICP-Brasil:**
- Tipo A1 (arquivo) ou A3 (token/cartão)
- Válido e vinculado ao CNPJ da empresa
- Renovação antes do vencimento

### **2. Credenciamento na SEFAZ:**
- Cadastro no portal da SEFAZ do estado
- Obtenção do CSC (Código de Segurança do Contribuinte)
- Obtenção do ID Token CSC

### **3. Infraestrutura:**
- ✅ Conexão com internet (já temos)
- ❌ Impressora térmica ou laser (para DANFE-NFC-e)
- ❌ Software emissor de NFC-e (a implementar)

---

## 📝 **Campos Obrigatórios por Tipo:**

### **Empresa (Emitente):**
1. CNPJ ✅
2. Razão Social ✅
3. Nome Fantasia ✅
4. Inscrição Estadual ✅
5. Endereço completo ✅
6. Código IBGE do Município ❌
7. Código IBGE do Estado ❌
8. CRT (Código de Regime Tributário) ❌

### **Produto:**
1. NCM ✅
2. Código de Barras (GTIN) ✅
3. Descrição ✅
4. CFOP ✅
5. Origem ✅
6. Unidade Comercial ❌
7. Valor Unitário ✅
8. Quantidade ✅
9. ICMS (CST/CSOSN) ✅
10. Alíquota ICMS ✅

### **Venda:**
1. Número da NFC-e ❌
2. Série ❌
3. Data/Hora de Emissão ✅ (parcial)
4. Valor Total ✅
5. Forma de Pagamento ✅ (parcial)

---

## 🚀 **Próximos Passos para Implementação:**

### **Fase 1: Completar Dados Cadastrais**
1. Adicionar campos faltantes no cadastro da empresa:
   - Código IBGE Município
   - Código IBGE Estado
   - CRT (Código de Regime Tributário)
   - Certificado Digital (upload)
   - Senha do Certificado
   - Ambiente (Produção/Homologação)
   - CSC e ID Token

### **Fase 2: Configurações de Emissão**
1. Criar tela de configurações de NFC-e
2. Configurar série, numeração, modelo
3. Configurar URL da SEFAZ por estado

### **Fase 3: Integração com SEFAZ**
1. Escolher biblioteca/API para comunicação
2. Implementar geração de XML
3. Implementar assinatura digital
4. Implementar envio e tratamento de retorno

### **Fase 4: Interface de Emissão**
1. Botão "Emitir NFC-e" na finalização de venda
2. Tela de confirmação de dados
3. Exibição do QR Code
4. Opção de impressão do DANFE-NFC-e
5. Opção de envio por email

### **Fase 5: Contingência**
1. Implementar modo offline
2. Armazenar NFC-e pendentes
3. Reenvio automático quando SEFAZ voltar

---

## 📚 **Recursos e Documentação:**

- **Layout da NFC-e:** Manual de Integração do Contribuinte (disponível na SEFAZ de cada estado)
- **WebServices:** Endpoints específicos por estado
- **Bibliotecas:** NFePHP, Focus NFe API, etc
- **Validações:** Schemas XSD fornecidos pela SEFAZ

---

## ⚠️ **Observações Importantes:**

1. **Cada estado tem suas particularidades** - verificar documentação específica
2. **Ambiente de Homologação** - testar antes de ir para produção
3. **Backup do Certificado Digital** - essencial para não perder acesso
4. **Contingência** - ter plano B quando SEFAZ estiver offline
5. **Armazenamento** - manter XMLs por 5 anos (obrigatório)

---

**Última atualização:** Dezembro 2024

