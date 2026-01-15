# 🔍 Onde está o erro "Mensagem SOAP inválida"

## 📍 Localização do Erro

O erro **"Mensagem SOAP inválida"** aparece quando a SEFAZ rejeita a requisição SOAP.

### Onde é exibido:

#### 1. **app.py** (linhas 230-237)
```python
# Log detalhado do erro
print("\n" + "=" * 60)
print("ERRO NA EMISSÃO NFC-e")
print("=" * 60)
print(f"Tipo: {error_type}")  # Mostra "SEFAZRejection"
print(f"Erro: {resultado.get('error', 'N/A')}")  # Mostra "Mensagem SOAP inválida"
if 'codigo_erro' in resultado:
    print(f"Código SEFAZ: {resultado['codigo_erro']}")
print("=" * 60)
```

**Arquivo:** `app.py`  
**Linhas:** 230-237

#### 2. **nfce_manual_completo.py** (linhas 572-574)
```python
print(f"\n❌ REJEIÇÃO DA SEFAZ:")
print(f"   Código: {codigo}")
print(f"   Motivo: {motivo}")  # Aqui aparece "Mensagem SOAP inválida"
```

**Arquivo:** `nfce_manual_completo.py`  
**Linhas:** 572-574

#### 3. **nfce_pynfe.py** (linhas 356-362)
```python
# Rejeição no protocolo
return {
    'success': False,
    'autorizada': False,
    'status': 'rejeitada',
    'error': x_motivo.text if x_motivo is not None else 'Erro desconhecido',
    'codigo_erro': c_stat.text if c_stat is not None else '',
    'error_type': 'SEFAZRejection'
}
```

**Arquivo:** `nfce_pynfe.py`  
**Linhas:** 356-362

---

## 🔍 Origem do Erro

A mensagem **"Mensagem SOAP inválida"** vem diretamente da **SEFAZ** no campo `<xMotivo>` da resposta XML:

```xml
<retEnviNFe>
    <cStat>XXX</cStat>
    <xMotivo>Mensagem SOAP inválida</xMotivo>
</retEnviNFe>
```

---

## 🛠️ Como Corrigir

### Possíveis Causas:

1. **Envelope SOAP malformado**
   - Namespaces incorretos
   - Estrutura XML inválida
   - Encoding incorreto

2. **Headers HTTP incorretos**
   - Content-Type errado
   - SOAPAction incorreto
   - Charset faltando

3. **XML dentro do SOAP inválido**
   - XML da NFC-e com erros
   - Schema XSD não validado
   - Caracteres especiais não escapados

### Verificações:

1. **Verificar envelope SOAP** em `nfce_manual_completo.py`:
   ```python
   def montar_soap_envelope(self, xml_assinado: str, id_lote: str, ind_sinc: str = '1') -> str:
   ```

2. **Verificar headers HTTP** em `enviar_sefaz`:
   ```python
   session.headers.update({
       'Content-Type': 'application/soap+xml; charset=utf-8',
       'SOAPAction': 'http://www.portalfiscal.inf.br/nfe/wsdl/NFeAutorizacao4/nfeAutorizacaoLote',
   })
   ```

3. **Validar XML antes de enviar**:
   - Usar schemas XSD
   - Verificar encoding UTF-8
   - Escapar caracteres especiais

---

## 📝 Arquivos Relacionados

- `app.py` - Exibe o erro (linhas 230-237)
- `nfce_manual_completo.py` - Processa resposta SEFAZ (linhas 572-574)
- `nfce_pynfe.py` - Processa resposta SEFAZ (linhas 356-362)
- `nfce_manual_completo.py` - Monta envelope SOAP (método `montar_soap_envelope`)

---

## 🔧 Debug

Para debugar, adicione logs antes de enviar:

```python
# Em nfce_manual_completo.py, método enviar_sefaz
print("SOAP Envelope:")
print(soap_envelope[:500])  # Primeiros 500 chars

print("Headers:")
print(session.headers)
```

















