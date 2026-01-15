# 🔄 Alternativas ao PyNFe para NFC-e

## ⚠️ Problema Atual
O PyNFe está gerando XML com SOAP, prefixos `ns0:`, e problemas de schema que causam rejeição `cStat 225` pela SEFAZ.

## ✅ Melhores Alternativas

### 1. **nfelib** ⭐ (RECOMENDADO - Mais Confiável)

**Por que usar:**
- ✅ Gera bindings automaticamente a partir dos XSDs oficiais da SEFAZ
- ✅ Garante conformidade total com o schema
- ✅ Validação automática de XML
- ✅ Sem problemas de SOAP ou prefixos
- ✅ Mantido ativamente

**Instalação:**
```bash
pip install nfelib
```

**Exemplo de uso:**
```python
from nfelib.nfe.bindings.v4_0 import nfe_v4_00 as nfe
from nfelib.nfe.bindings.v4_0 import envi_nfe_v4_00 as envi_nfe
from lxml import etree

# Criar estrutura NFe
nfe_obj = nfe.TNfeProc()
nfe_obj.nfe = nfe.TNfe()
nfe_obj.nfe.inf_nfe = nfe.TInfNfe()
nfe_obj.nfe.inf_nfe.versao = "4.00"
nfe_obj.nfe.inf_nfe.ide = nfe.TIde()
nfe_obj.nfe.inf_nfe.ide.c_uf = 35  # SP
nfe_obj.nfe.inf_nfe.ide.c_nf = "12345678"
# ... preencher todos os campos

# Gerar XML
xml_str = nfe_obj.to_xml(pretty_print=False)
```

**Documentação:** https://github.com/akretion/nfelib

---

### 2. **PySIGNFe**

**Por que usar:**
- ✅ Biblioteca completa para NF-e, NFC-e, NFS-e, CT-e
- ✅ Suporta assinatura digital
- ✅ Comunicação com SEFAZ
- ✅ Impressão de DANFE

**Instalação:**
```bash
pip install pysignfe
```

**Documentação:** https://github.com/thiagopena/PySIGNFe

---

### 3. **PyTrustNFe**

**Por que usar:**
- ✅ Focada em NFC-e
- ✅ Comunicação com SEFAZ
- ✅ Suporte a múltiplos provedores

**Instalação:**
```bash
pip install PyTrustNFe
```

**Documentação:** https://pypi.org/project/PyTrustNFe/

---

### 4. **API Pronta (Focus NFe)** ⭐ (Mais Rápido)

**Por que usar:**
- ✅ API REST simples (não precisa lidar com XML/SOAP)
- ✅ Toda validação feita pela API
- ✅ Ambiente de homologação gratuito
- ✅ Documentação completa
- ✅ Suporte técnico

**Como usar:**
```python
import requests

def emitir_nfce_focusnfe(dados):
    url = "https://api.focusnfe.com.br/v2/nfce"
    headers = {
        "Authorization": "Token SEU_TOKEN",
        "Content-Type": "application/json"
    }
    
    payload = {
        "ref": "REF123",
        "cnpj_emitente": "12345678000190",
        "natureza_operacao": "VENDA",
        "data_emissao": "2025-12-09T18:00:00",
        "tipo_documento": "1",
        "local_destino": "1",
        "finalidade": "1",
        "consumidor_final": "1",
        "presenca_comprador": "1",
        "itens": [
            {
                "codigo_produto": "COD-1",
                "descricao": "PRODUTO TESTE",
                "cfop": "5405",
                "ncm": "2201100",
                "unidade_comercial": "UN",
                "quantidade_comercial": "3.00",
                "valor_unitario_comercial": "2.00",
                "valor_total": "6.00",
                "icms_origem": "0",
                "icms_situacao_tributaria": "00",
                "icms_aliquota": "18.00"
            }
        ],
        "valor_total": "6.00",
        "forma_pagamento": [
            {
                "tipo": "01",
                "valor": "6.00"
            }
        ]
    }
    
    response = requests.post(url, json=payload, headers=headers)
    return response.json()
```

**Site:** https://focusnfe.com.br
**Documentação:** https://doc.focusnfe.com.br
**Preço:** Pago (mas tem plano gratuito para testes)

---

## 🎯 Recomendação

### Para resolver RÁPIDO:
**Use Focus NFe API** - Você não precisa lidar com XML, SOAP, ou validação. A API faz tudo.

### Para solução DEFINITIVA:
**Use nfelib** - Gera XML correto automaticamente a partir dos XSDs oficiais, garantindo conformidade total.

---

## 📝 Como Migrar para nfelib

### Passo 1: Instalar
```bash
cd sistema_exodo_01-12/backend_pynfe
pip install nfelib
```

### Passo 2: Criar novo serviço
Criar arquivo: `backend_pynfe/services/nfce_service_nfelib.py`

```python
from nfelib.nfe.bindings.v4_0 import nfe_v4_00 as nfe
from nfelib.nfe.bindings.v4_0 import envi_nfe_v4_00 as envi_nfe
from lxml import etree
import requests
from datetime import datetime

class NFCeServiceNfelib:
    def emitir_nfce(self, data):
        """
        Emite NFC-e usando nfelib (gera XML correto automaticamente)
        """
        try:
            # 1. Criar estrutura enviNFe
            envi_nfe_obj = envi_nfe.TEnviNfe()
            envi_nfe_obj.versao = "4.00"
            envi_nfe_obj.id_lote = "000000000000001"  # 15 dígitos
            envi_nfe_obj.ind_sinc = 1  # Síncrono
            
            # 2. Criar NFe
            nfe_obj = nfe.TNfe()
            nfe_obj.inf_nfe = nfe.TInfNfe()
            nfe_obj.inf_nfe.versao = "4.00"
            
            # 3. Preencher ide
            nfe_obj.inf_nfe.ide = nfe.TIde()
            nfe_obj.inf_nfe.ide.c_uf = int(data.get('uf', '35'))
            nfe_obj.inf_nfe.ide.c_nf = data.get('c_nf', '12345678')
            nfe_obj.inf_nfe.ide.nat_op = data.get('natureza_operacao', 'VENDA')
            nfe_obj.inf_nfe.ide.mod = 65  # NFC-e
            nfe_obj.inf_nfe.ide.serie = int(data.get('serie', '1'))
            nfe_obj.inf_nfe.ide.n_nf = int(data.get('numero', '1'))
            nfe_obj.inf_nfe.ide.dh_emi = datetime.now()
            nfe_obj.inf_nfe.ide.tp_nf = 1
            nfe_obj.inf_nfe.ide.id_dest = 1
            nfe_obj.inf_nfe.ide.c_mun_fg = int(data.get('codigo_ibge', '3549904'))
            nfe_obj.inf_nfe.ide.tp_imp = 4
            nfe_obj.inf_nfe.ide.tp_emis = 1
            nfe_obj.inf_nfe.ide.tp_amb = 2 if data.get('ambiente_homologacao', True) else 1
            nfe_obj.inf_nfe.ide.fin_nfe = 1
            nfe_obj.inf_nfe.ide.ind_final = 1
            nfe_obj.inf_nfe.ide.ind_pres = 1
            nfe_obj.inf_nfe.ide.proc_emi = 0
            nfe_obj.inf_nfe.ide.ver_proc = "Sistema Exodo"
            
            # 4. Preencher emitente
            nfe_obj.inf_nfe.emit = nfe.TEmit()
            nfe_obj.inf_nfe.emit.cnpj = data.get('cnpj', '').replace('.', '').replace('/', '').replace('-', '')
            nfe_obj.inf_nfe.emit.x_nome = data.get('razao_social', '')
            nfe_obj.inf_nfe.emit.x_fant = data.get('nome_fantasia', '')
            # ... preencher endereço, IE, CRT, etc.
            
            # 5. Preencher produtos
            nfe_obj.inf_nfe.det = []
            for item in data.get('produtos', []):
                det = nfe.TDet()
                det.n_item = len(nfe_obj.inf_nfe.det) + 1
                det.prod = nfe.TProd()
                det.prod.c_prod = item.get('codigo', '')
                det.prod.x_prod = item.get('descricao', '')
                det.prod.ncm = item.get('ncm', '')
                det.prod.cfop = item.get('cfop', '5405')
                det.prod.u_com = item.get('unidade', 'UN')
                det.prod.q_com = float(item.get('quantidade', 1))
                det.prod.v_un_com = float(item.get('valor_unitario', 0))
                det.prod.v_prod = float(item.get('valor_total', 0))
                # ... preencher impostos, etc.
                nfe_obj.inf_nfe.det.append(det)
            
            # 6. Preencher totais, pagamento, etc.
            # ...
            
            # 7. Adicionar NFe ao enviNFe
            envi_nfe_obj.nfe = [nfe_obj]
            
            # 8. Gerar XML (já está correto, sem SOAP, sem prefixos)
            xml_str = envi_nfe_obj.to_xml(pretty_print=False)
            
            # 9. Assinar XML (usar biblioteca de assinatura)
            xml_assinado = self._assinar_xml(xml_str, certificado)
            
            # 10. Enviar para SEFAZ
            resposta = self._enviar_para_sefaz(xml_assinado, ambiente_homologacao)
            
            return resposta
            
        except Exception as e:
            return {
                'success': False,
                'error': str(e)
            }
```

---

## 🔄 Comparação

| Biblioteca | XML Correto | Validação | Facilidade | Manutenção |
|------------|-------------|-----------|------------|------------|
| **nfelib** | ✅✅✅ | ✅✅✅ | ⭐⭐⭐ | ✅✅✅ |
| **PySIGNFe** | ✅✅ | ✅✅ | ⭐⭐ | ✅✅ |
| **PyTrustNFe** | ✅✅ | ✅ | ⭐⭐ | ✅ |
| **Focus NFe API** | ✅✅✅ | ✅✅✅ | ✅✅✅ | ✅✅✅ |
| **PyNFe (atual)** | ❌ | ❌ | ⭐ | ⚠️ |

---

## 🚀 Próximos Passos

1. **Testar nfelib** em ambiente de homologação
2. **Ou migrar para Focus NFe API** para solução rápida
3. **Manter PyNFe apenas como fallback** se necessário


























