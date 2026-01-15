# 📋 Informações sobre o Site de Downloads da SEFAZ-SP para NFC-e

## 🔗 Link Principal

**Página de Downloads**: https://portal.fazenda.sp.gov.br/servicos/nfce/Paginas/Downloads.aspx

## 📦 Recursos Disponíveis no Site

De acordo com a página de Downloads da SEFAZ-SP, você pode encontrar:

### 1. **Manuais de Orientação**
- Documentos detalhados sobre procedimentos para emissão e gestão da NFC-e
- Guias passo a passo para contribuintes

### 2. **Especificações Técnicas**
- Padrões e requisitos técnicos para integração
- Informações para desenvolvedores de sistemas
- Documentação sobre APIs e webservices

### 3. **Arquivos de Schema XML (XSD)**
- ⚠️ **IMPORTANTE**: Modelos estruturais que definem a organização e validação dos dados
- Schemas XSD para validação de XML
- Definições de tipos de dados (ex: `TDec_1302`, `idLote`, etc.)

### 4. **Notas Técnicas**
- Atualizações e esclarecimentos sobre mudanças
- Implementações no sistema da NFC-e
- Correções e melhorias

### 5. **Vídeos Explicativos**
- Credenciamento
- Certificação
- Contingência
- EPEC (Evento Prévio de Emissão em Contingência)
- Inutilização de notas
- Cancelamento
- Emissor gratuito
- Numeração
- REDF
- Token
- QR-Code
- EFD
- Impressão

## 🔍 O Que Procurar Especificamente

Para resolver o erro `cStat 225` (Falha no Schema XML do lote), procure por:

### **Schemas XSD Relevantes**

1. **Schema do Lote (enviNFe)**
   - Arquivo que define a estrutura do elemento `enviNFe`
   - Validação de `idLote` (15 dígitos)
   - Validação de `indSinc` (obrigatório para NFC-e, valor 1)
   - Ordem dos elementos dentro de `enviNFe`

2. **Schema de Tipos Básicos**
   - `tiposBasico_v3.10.xsd` ou similar
   - Define tipos como `TDec_1302` (decimal com 13 dígitos antes, 2 depois)
   - Validação de formatos de dados

3. **Schema da NFe (infNFe)**
   - Estrutura da nota fiscal
   - Validação de `cMunFG` (código IBGE de 7 dígitos)
   - Validação de `CRT` (Código de Regime Tributário)

4. **PL_009 ou PL_NFCE**
   - Especificações da versão atual (PL_009)
   - Versão 4.00 (`SP_NFCE_PL_009_V400`)

## 📞 Canais de Atendimento

Se não encontrar os arquivos no site:

### **Central de Atendimento**
- **Telefone**: 0800-0170110 (não atende dúvidas sobre interpretação da Legislação Tributária)
- **Telefone Móvel**: 11-2930-3750

### **E-mail para Indisponibilidade**
- **E-mail**: nfce_indisponibilidade@fazenda.sp.gov.br

### **Fale Conosco NFC-e**
- **Link**: https://portal.fazenda.sp.gov.br/servicos/nfce/Paginas/Fale-Conosco-NFCe.aspx

## ⚠️ Importante

- A emissão da NFC-e será **obrigatória a partir de 01/01/2026** para todo o varejo paulista
- Substituirá:
  - CF-e-SAT (modelo 59)
  - Nota Fiscal de Venda ao Consumidor (modelo 02)
  - Nota Fiscal de Venda a Consumidor online (modelo 56)

## 🔧 Como Usar os Schemas

Se você conseguir baixar os schemas XSD do site:

1. **Validar XML Localmente**
   - Use os schemas XSD para validar o XML antes de enviar para SEFAZ
   - Isso pode ajudar a identificar problemas antes do envio

2. **Verificar Estrutura**
   - Compare o XML gerado pelo PyNFe com o schema oficial
   - Identifique elementos faltantes ou incorretos

3. **Validar Tipos de Dados**
   - Verifique se os valores estão no formato correto (ex: `TDec_1302`)
   - Confirme que códigos IBGE têm 7 dígitos
   - Verifique que `idLote` tem 15 dígitos

## 📝 Notas

- O site pode estar em manutenção ou os conteúdos podem ter sido movidos
- Recomenda-se entrar em contato diretamente com a SEFAZ-SP para obter informações atualizadas
- Os schemas podem estar em diferentes locais ou com nomes diferentes

## 🔗 Links Úteis

- **Página Principal NFC-e**: https://portal.fazenda.sp.gov.br/servicos/nfce
- **Downloads**: https://portal.fazenda.sp.gov.br/servicos/nfce/Paginas/Downloads.aspx
- **Vídeos**: https://portal.fazenda.sp.gov.br/servicos/nfce/Paginas/V%C3%ADdeos.aspx
- **Fale Conosco**: https://portal.fazenda.sp.gov.br/servicos/nfce/Paginas/Fale-Conosco-NFCe.aspx

## 📅 Data da Consulta

2025-12-09


























