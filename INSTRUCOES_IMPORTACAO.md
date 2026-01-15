# Instruções - Importar Produtos do Excel

## ✅ O Botão de Importação Está em 3 Locais:

### 1. **Card Grande no Topo da Lista** (Sempre Visível)
- Aparece como um card VERDE grande no topo da lista de empresas
- Texto: "Importar Produtos do Excel"
- Clique nele para importar

### 2. **Ícone no AppBar** (Canto Superior Direito)
- Ícone verde de upload (seta para cima)
- Está ao lado do botão "+" de adicionar empresa

### 3. **Menu da Empresa** (Quando Empresa Está Selecionada)
- Clique nos três pontinhos (⋮) ao lado da empresa
- Selecione "Importar Produtos Excel"

## 🔄 Se o Botão NÃO Aparecer:

1. **Pare o app completamente** (não apenas minimizar)
2. **Inicie novamente** o app
3. **Acesse a tela "Gerenciar Empresas"**

## 📋 Formato do Excel Esperado:

### Campos Básicos:
- **Código** (opcional) - Código interno do produto
- **Nome** (obrigatório) - Nome do produto
- **Descrição** (opcional) - Descrição detalhada
- **Unidade** (padrão: UN) - Unidade de medida (UN, KG, L, etc)
- **Grupo** (padrão: Sem Grupo) - Categoria/Grupo do produto
- **Preço** (obrigatório) - Preço de venda
- **Preço de Custo** (opcional) - Preço de compra/custo
- **Estoque** (padrão: 0) - Quantidade em estoque
- **Código de Barras** (opcional) - EAN/GTIN

### Campos de Impostos (Opcionais):
- **NCM** - Nomenclatura Comum do Mercosul (8 dígitos)
- **CFOP** - Código Fiscal de Operações e Prestações
- **ICMS Alíquota** - Alíquota ICMS (%)
- **ICMS CST** - Código de Situação Tributária ICMS
- **IPI Alíquota** - Alíquota IPI (%)
- **IPI CST** - Código de Situação Tributária IPI
- **PIS Alíquota** - Alíquota PIS (%)
- **PIS CST** - Código de Situação Tributária PIS
- **COFINS Alíquota** - Alíquota COFINS (%)
- **COFINS CST** - Código de Situação Tributária COFINS
- **ISS Alíquota** - Alíquota ISS (%) - para serviços
- **Origem** - Origem da mercadoria (0-Nacional, 1-Estrangeira, etc)
- **CEST** - Código Especificador da Substituição Tributária
- **CSOSN** - Código de Situação da Operação - Simples Nacional
- **Simples Nacional Alíquota** - Alíquota do Simples Nacional (%)

⚠️ **A primeira linha será ignorada (cabeçalho)**

💡 **Dica:** O sistema detecta automaticamente as colunas pelo nome do cabeçalho. Você pode usar qualquer ordem e o sistema encontrará as colunas corretas!

## 📝 Funcionalidades:

- ✅ Detecta produtos duplicados
- ✅ Atualiza produtos existentes
- ✅ Gera código automaticamente se não fornecido
- ✅ Valida dados antes de importar
- ✅ Mostra relatório detalhado após importação

