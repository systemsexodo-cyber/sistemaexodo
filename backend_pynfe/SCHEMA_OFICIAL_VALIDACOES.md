# 📋 Validações Baseadas no Schema Oficial XSD

## 📚 Fonte dos Schemas

Schemas consultados:
- `tiposBasico_v3.10.xsd` - Tipos básicos da NF-e/NFC-e
- `eventoEPEC_v0.01.xsd` - Evento EPEC (referência para idLote)

## ✅ Validações Implementadas

### 1. **TDec_1302 - Tipo Decimal (13 dígitos + 2 decimais)**

**Schema oficial:**
```xml
<xs:simpleType name="TDec_1302">
    <xs:annotation>
        <xs:documentation>Tipo Decimal com 15 dígitos, sendo 13 de corpo e 2 decimais</xs:documentation>
    </xs:annotation>
    <xs:restriction base="xs:string">
        <xs:whiteSpace value="preserve"/>
        <xs:pattern value="0|0\.[0-9]{2}|[1-9]{1}[0-9]{0,12}(\.[0-9]{2})?"/>
    </xs:restriction>
</xs:simpleType>
```

**Padrão Regex:** `^(0|0\.[0-9]{2}|[1-9]{1}[0-9]{0,12}(\.[0-9]{2})?)$`

**Valores Válidos:**
- ✅ `0` (zero inteiro)
- ✅ `0.00`, `0.01`, `0.99` (zero com 2 casas decimais)
- ✅ `1`, `12`, `123` (números inteiros)
- ✅ `1.00`, `12.50`, `123.99` (números com 2 casas decimais)
- ✅ `1234567890123.45` (máximo: 13 dígitos antes + 2 após)

**Valores Inválidos:**
- ❌ `0.000` (3 casas decimais)
- ❌ `1.5` (1 casa decimal)
- ❌ `0.1` (1 casa decimal)
- ❌ `12345678901234.45` (14 dígitos antes da vírgula - excede limite)

**Campos que usam TDec_1302:**
- `vProd`, `vUnCom`, `vUnTrib`
- `vFrete`, `vSeg`, `vDesc`, `vOutro`
- `vBC`, `vICMS`, `vICMSDeson`, `vFCP`
- `vBCST`, `vST`, `vFCPST`, `vFCPSTRet`
- `vIPI`, `vIPIDevol`, `vPIS`, `vCOFINS`
- `vNF`, `vTotTrib`
- `vICMSUFDest`, `vFCPUFDest`, `vICMSUFRemet`
- `vPag`, `vTroco`, `vLiq`

### 2. **TRec - Tipo Número do Recibo do Lote**

**Schema oficial:**
```xml
<xs:simpleType name="TRec">
    <xs:annotation>
        <xs:documentation>Tipo Número do Recibo do envio de lote de NF-e</xs:documentation>
    </xs:annotation>
    <xs:restriction base="xs:string">
        <xs:whiteSpace value="preserve"/>
        <xs:maxLength value="15"/>
        <xs:pattern value="[0-9]{15}"/>
    </xs:restriction>
</xs:simpleType>
```

**Padrão:** Exatamente 15 dígitos numéricos

**Valores Válidos:**
- ✅ `000000000000001` (15 dígitos)
- ✅ `123456789012345` (15 dígitos)

**Valores Inválidos:**
- ❌ `1` (1 dígito)
- ❌ `123` (3 dígitos)
- ❌ `0000000000000001` (16 dígitos)

**Aplicação:** Campo `idLote` no `enviNFe`

### 3. **idLote no Evento EPEC (Referência)**

**Schema oficial:**
```xml
<xs:element name="idLote">
    <xs:annotation>
        <xs:documentation>Identificador de controle do Lote de envio do Evento.</xs:documentation>
    </xs:annotation>
    <xs:simpleType>
        <xs:restriction base="xs:string">
            <xs:whiteSpace value="preserve" />
            <xs:pattern value="[0-9]{1,15}" />
        </xs:restriction>
    </xs:simpleType>
</xs:element>
```

**Nota:** Para eventos, aceita de 1 a 15 dígitos, mas para `enviNFe` deve ser exatamente 15 dígitos (padrão TRec).

## 🔧 Implementação no Código

### **Função: `_validar_valores_decimais_xml()`**

Valida e corrige valores decimais conforme padrão TDec_1302:

```python
# Pattern do schema oficial
pattern_tdec_1302 = re.compile(r'^(0|0\.[0-9]{2}|[1-9]{1}[0-9]{0,12}(\.[0-9]{2})?)$')

# Validação e correção:
# - 0.000 → 0.00
# - 1.5 → 1.50
# - 0.1 → 0.10
# - Valida máximo de 13 dígitos antes da vírgula
```

### **Função: `_validar_caracteres_proibidos()`**

Remove caracteres proibidos em campos de texto:
- `*`, `/`, `?`, `!`, `<`, `>`, `&`
- Remove quebras de linha e espaços extras

### **Validação de idLote**

Garantido que tenha exatamente 15 dígitos:
```python
id_lote.text = '000000000000001'  # 15 dígitos
```

## 📝 Exemplos de Correção

### **Exemplo 1: Valor Decimal Inválido**
```xml
<!-- ANTES (ERRADO) -->
<vCOFINS>0.000</vCOFINS>
<vPIS>1.5</vPIS>
<vICMS>0.1</vICMS>

<!-- DEPOIS (CORRETO) -->
<vCOFINS>0.00</vCOFINS>
<vPIS>1.50</vPIS>
<vICMS>0.10</vICMS>
```

### **Exemplo 2: idLote Inválido**
```xml
<!-- ANTES (ERRADO) -->
<idLote>1</idLote>

<!-- DEPOIS (CORRETO) -->
<idLote>000000000000001</idLote>
```

### **Exemplo 3: Caracteres Proibidos**
```xml
<!-- ANTES (ERRADO) -->
<xProd>Produto * Especial / Teste?</xProd>

<!-- DEPOIS (CORRETO) -->
<xProd>Produto Especial Teste</xProd>
```

## ⚠️ Importante

1. **Valores decimais** devem seguir exatamente o padrão TDec_1302
2. **idLote** deve ter exatamente 15 dígitos
3. **Caracteres proibidos** são removidos automaticamente
4. **Validações** são aplicadas antes de enviar para SEFAZ

## 🔗 Referências

- Schema oficial: `tiposBasico_v3.10.xsd`
- Artigo Tecnospeed: https://blog.tecnospeed.com.br/como-resolver-falha-no-schema-xml-da-nf-e-nfc-e/
- Manual de Orientação ao Contribuinte (MOC)


























