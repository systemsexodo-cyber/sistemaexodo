# 📍 Localização do Erro nas Linhas 1025-1026

## 🔍 Análise

A mensagem que você está vendo:
```
1025|[SEFAZRejection] Rejeicao:        
1026|Mensagem SOAP invalida
```

**NÃO está nas linhas 1025-1026 de um arquivo Python**, mas sim sendo **exibida no terminal/console** durante a execução.

## 📍 Onde a Mensagem é Gerada

### 1. **app.py** (linhas 230-237)
Este é o local principal onde o erro é formatado e exibido:

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

### 2. **nfce_manual_completo.py** (linhas 572-574)
Onde a rejeição é detectada e formatada:

```python
print(f"\n❌ REJEIÇÃO DA SEFAZ:")
print(f"   Código: {codigo}")
print(f"   Motivo: {motivo}")  # "Mensagem SOAP inválida" vem daqui
```

**Arquivo:** `nfce_manual_completo.py`  
**Linhas:** 572-574

### 3. **nfce_pynfe.py** (linhas 356-362)
Onde o erro é retornado:

```python
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

## 🔄 Fluxo do Erro

1. **SEFAZ retorna erro** → XML com `<xMotivo>Mensagem SOAP inválida</xMotivo>`
2. **nfce_manual_completo.py ou nfce_pynfe.py** → Extrai `xMotivo` e cria resultado com `error_type: 'SEFAZRejection'`
3. **app.py** → Recebe resultado e imprime no formato:
   ```
   Tipo: SEFAZRejection
   Erro: Mensagem SOAP inválida
   ```

## 🎯 Onde Corrigir

### Para corrigir o erro "Mensagem SOAP inválida", verifique:

1. **Envelope SOAP** em `nfce_manual_completo.py`:
   - Método: `montar_soap_envelope()` (linha ~420)
   - Verificar namespaces, estrutura XML

2. **Headers HTTP** em `enviar_sefaz()`:
   - Content-Type: `application/soap+xml; charset=utf-8`
   - SOAPAction correto

3. **XML da NFC-e** antes de enviar:
   - Validar com schemas XSD
   - Verificar encoding UTF-8

## 📝 Arquivos Relacionados

- `app.py` (linhas 230-237) - Exibe o erro
- `nfce_manual_completo.py` (linhas 572-574) - Detecta rejeição
- `nfce_pynfe.py` (linhas 356-362) - Retorna erro
- `nfce_manual_completo.py` - Método `montar_soap_envelope()` - Monta SOAP
- `nfce_manual_completo.py` - Método `enviar_sefaz()` - Envia para SEFAZ

---

**Nota:** As linhas 1025-1026 que você vê são do **output do terminal**, não de um arquivo específico. O erro está sendo gerado nos arquivos acima.

















