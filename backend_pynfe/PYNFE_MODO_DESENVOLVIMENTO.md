# ✅ PyNFe Instalado em Modo Desenvolvimento

## 📦 Status da Instalação

- ✅ **PyNFe versão:** 0.6.0
- ✅ **Modo:** Desenvolvimento (editable)
- ✅ **Localização:** `pynfe_dev/pynfe/`
- ✅ **Status:** Funcionando

## 🎯 O que é Modo Desenvolvimento?

Instalação em modo **editable** (`pip install -e`) significa que:

- ✅ Qualquer alteração no código do PyNFe é refletida **automaticamente**
- ✅ Não precisa reinstalar após fazer mudanças
- ✅ Pode editar o código diretamente na pasta `pynfe_dev/`
- ✅ Ideal para desenvolvimento e debugging

## 📁 Estrutura

```
backend_pynfe/
├── pynfe_dev/          # Código fonte do PyNFe (editável)
│   ├── pynfe/          # Módulo principal
│   ├── tests/          # Testes
│   └── requirements.txt
└── ...
```

## 🔧 Como Usar

### Importar PyNFe

```python
from pynfe import NotaFiscal, Emitente, Cliente, Produto
# ou
import pynfe
```

### Fazer Alterações

1. Edite os arquivos em `pynfe_dev/pynfe/`
2. As mudanças são aplicadas **automaticamente**
3. Não precisa reinstalar

### Verificar Versão

```python
import pynfe
print(pynfe.__version__)  # 0.6.0
print(pynfe.__file__)     # Caminho para pynfe_dev/pynfe/__init__.py
```

## 🛠️ Comandos Úteis

### Reinstalar (se necessário)

```bash
cd pynfe_dev
pip install -e .
```

### Atualizar do GitHub

```bash
cd pynfe_dev
git pull origin main
pip install -e .
```

### Verificar Instalação

```bash
python -c "import pynfe; print(pynfe.__version__)"
```

## 📝 Notas Importantes

### ⚠️ Sobre NFC-e SP

Lembre-se que o PyNFe **não funciona bem para NFC-e SP** porque:
- SP não usa WSDL para NFC-e
- SP usa SVRS
- PyNFe depende de WSDL

**Solução:** Use a implementação manual (`nfce_manual_completo.py`) que criamos.

### ✅ Quando Usar PyNFe

- NF-e (modelo 55) - funciona bem
- NFC-e de outros estados (que usam WSDL)
- Desenvolvimento e testes

### ❌ Quando NÃO Usar PyNFe

- NFC-e São Paulo (SP)
- Quando precisa de controle total
- Quando quer evitar dependências complexas

## 🔄 Alternativas

Se precisar fazer alterações no PyNFe para SP:

1. **Editar código em `pynfe_dev/pynfe/`**
2. **Testar as mudanças**
3. **Se funcionar, fazer commit/pull request**

Ou usar a **implementação manual** que já criamos:
- `nfce_manual_completo.py` - 100% funcional para SP
- Não depende de PyNFe
- Totalmente editável

## ✅ Status Atual

- ✅ PyNFe instalado em modo desenvolvimento
- ✅ Pronto para edição e testes
- ✅ Implementação manual também disponível
- ✅ Pode usar qualquer uma das duas soluções

---

**Instalação concluída com sucesso!** 🎉


















