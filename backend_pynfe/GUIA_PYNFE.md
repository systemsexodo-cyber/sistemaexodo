# 📘 Guia - NFC-e com PyNFe

## ✅ PyNFe Instalado em Modo Desenvolvimento

- ✅ **Versão:** 0.6.0
- ✅ **Modo:** Desenvolvimento (editable)
- ✅ **Localização:** `pynfe_dev/`
- ✅ **Status:** Pronto para uso

## 🎯 Quando Usar PyNFe

### ✅ Funciona Bem Para:

- **NF-e (modelo 55)** - Todos os estados
- **NFC-e de estados que usam WSDL** - RJ, MG, PR, RS, SC, etc.
- **Estados que não são SP**

### ❌ NÃO Funciona Bem Para:

- **NFC-e São Paulo (SP)** - SP não usa WSDL
- **Estados que usam SVRS sem WSDL**

## 🚀 Como Usar

### Opção 1: Automático (Recomendado)

O `app.py` já está configurado para usar PyNFe automaticamente quando:
- Estado não é SP
- PyNFe está disponível

```python
# O sistema escolhe automaticamente:
# - PyNFe para estados que não são SP
# - Implementação manual para SP
```

### Opção 2: Manual

```python
from nfce_pynfe import criar_servico_nfce_pynfe

# Criar serviço
nfce = criar_servico_nfce_pynfe()

if nfce:
    # Emitir NFC-e
    resultado = nfce.emitir(
        empresa_data={...},
        produtos=[...],
        pagamentos=[...],
        numero_nfce=1
    )
else:
    print("PyNFe não disponível")
```

## 📋 Estrutura do Código

### Arquivos Criados

1. **`nfce_pynfe.py`** - Implementação usando PyNFe
   - Cria objetos PyNFe (Emitente, Cliente, NotaFiscal)
   - Serializa XML
   - Assina com certificado
   - Envia para SEFAZ

2. **`exemplo_nfce_pynfe.py`** - Exemplo de uso

3. **`app.py`** - Atualizado para usar PyNFe automaticamente

## 🔄 Fluxo Automático

O `app.py` agora funciona assim:

1. **Recebe requisição** → `/api/nfce/emitir`
2. **Verifica estado:**
   - Se **não é SP** → Tenta usar PyNFe
   - Se **é SP** → Usa implementação manual
3. **Se PyNFe disponível** → Usa PyNFe
4. **Se PyNFe não disponível** → Usa implementação manual (fallback)

## ⚙️ Configuração

### Dados da Empresa

```python
empresa_data = {
    'cnpj': '12345678000190',
    'razao_social': 'Empresa LTDA',
    'uf': 'PR',  # ⚠️ Não use 'SP' se quiser PyNFe
    'certificado_base64': '...',
    'senhaCertificado': 'senha123',
    'ambienteHomologacao': True,
    # ... outros campos
}
```

### Produtos

```python
produtos = [
    {
        'codigo': '001',
        'descricao': 'Produto 1',
        'ncm': '21069090',
        'cfop': '5102',
        'quantidade': 1.0,
        'valor_unitario': 10.00,
        'valor_total': 10.00,
        'icms': {
            'origem': '0',
            'cst': '102',
            'aliquota': 18.0
        }
    }
]
```

## 🔍 Debug

### Verificar se PyNFe está sendo usado

No console do servidor, você verá:

```
✅ Usando PyNFe para emissão
```

ou

```
✅ Usando implementação manual para emissão
```

### Logs Detalhados

O PyNFe mostra logs de cada etapa:
- Preparando certificado
- Criando emitente
- Criando cliente
- Criando nota fiscal
- Serializando XML
- Assinando XML
- Enviando para SEFAZ

## ⚠️ Limitações Conhecidas

### SP (São Paulo)

PyNFe **não funciona bem para SP** porque:
- SP não usa WSDL para NFC-e
- SP usa SVRS sem WSDL completo
- PyNFe depende de WSDL

**Solução:** O sistema usa automaticamente a implementação manual para SP.

### Outros Estados

Para estados que usam WSDL (RJ, MG, PR, RS, etc.), PyNFe funciona perfeitamente.

## 📚 Referências

- **PyNFe GitHub:** https://github.com/TadaSoftware/PyNFe
- **Documentação:** Ver testes em `pynfe_dev/tests/`
- **Exemplos:** `test_nfce_serializacao.py`

## ✅ Status

- ✅ PyNFe instalado em modo desenvolvimento
- ✅ Implementação criada (`nfce_pynfe.py`)
- ✅ Integração com `app.py` (escolha automática)
- ✅ Fallback para implementação manual
- ✅ Funciona para estados que não são SP

---

**Pronto para uso!** O sistema escolhe automaticamente a melhor implementação. 🚀

