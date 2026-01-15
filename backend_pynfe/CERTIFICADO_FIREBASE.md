# 🔐 Certificado Digital - Local e Firebase

## 📋 Visão Geral

O sistema suporta **3 formas** de armazenar certificados:

1. **Local (Base64 direto)** - Para desenvolvimento/teste
2. **Firebase Storage** - Arquivo .pfx no Storage
3. **Firebase Firestore** - Base64 armazenado no Firestore

## 🏗️ Arquitetura

```
┌─────────────────────────────────────────┐
│         CertificadoService              │
│  (certificado_service.py)                │
│                                         │
│  Prioridade:                            │
│  1. certificado_base64 (direto)         │
│  2. Firebase Storage (.pfx)            │
│  3. Firebase Firestore (campo base64)   │
└─────────────────────────────────────────┘
```

## 🔧 Configuração

### 1. Variáveis de Ambiente (.env)

```env
# Firebase (opcional)
FIREBASE_CREDENTIALS_PATH=./firebase-credentials.json
FIREBASE_STORAGE_BUCKET=seu-projeto.appspot.com
```

### 2. Instalar Dependências

```bash
pip install firebase-admin
```

## 📝 Formas de Uso

### Opção 1: Base64 Direto (Local/Teste)

```json
{
  "empresa": {
    "cnpj": "12345678000190",
    "certificado_base64": "MIIKpAIBAzCCCl4GCSqGSIb3...",
    "senhaCertificado": "senha123"
  }
}
```

### Opção 2: Firebase Storage

```json
{
  "empresa": {
    "cnpj": "12345678000190",
    "certificado_firebase_path": "certificados/empresa123.pfx",
    "senhaCertificado": "senha123"
  }
}
```

**Estrutura no Storage:**
```
gs://seu-projeto.appspot.com/
  └── certificados/
      ├── empresa123.pfx
      └── empresa456.pfx
```

### Opção 3: Firebase Firestore

```json
{
  "empresa": {
    "cnpj": "12345678000190",
    "certificado_firestore_collection": "empresas",
    "certificado_firestore_doc": "empresa123",
    "certificado_firestore_field": "certificado_base64",
    "senhaCertificado": "senha123"
  }
}
```

**Estrutura no Firestore:**
```
empresas/
  └── empresa123/
      ├── cnpj: "12345678000190"
      ├── razao_social: "EMPRESA LTDA"
      └── certificado_base64: "MIIKpAIBAzCCCl4GCSqGSIb3..."
```

## 🚀 Migração: Local → Firebase

### Passo 1: Converter Certificado para Base64

```bash
python converter_certificado.py "C:\caminho\certificado.pfx"
```

### Passo 2: Escolher Método de Armazenamento

#### Opção A: Firebase Storage (Recomendado)

```python
# Upload do arquivo .pfx para Storage
from firebase_admin import storage

bucket = storage.bucket()
blob = bucket.blob('certificados/empresa123.pfx')
blob.upload_from_filename('certificado.pfx')
```

#### Opção B: Firebase Firestore

```python
# Salvar Base64 no Firestore
from firebase_admin import firestore

db = firestore.client()
doc_ref = db.collection('empresas').document('empresa123')
doc_ref.set({
    'cnpj': '12345678000190',
    'certificado_base64': 'MIIKpAIBAzCCCl4GCSqGSIb3...',
    # ... outros campos
})
```

### Passo 3: Atualizar Requisições

**Antes (Local):**
```json
{
  "empresa": {
    "certificado_base64": "MIIKpAIBAzCCCl4GCSqGSIb3..."
  }
}
```

**Depois (Firebase Storage):**
```json
{
  "empresa": {
    "certificado_firebase_path": "certificados/empresa123.pfx"
  }
}
```

**Depois (Firebase Firestore):**
```json
{
  "empresa": {
    "certificado_firestore_collection": "empresas",
    "certificado_firestore_doc": "empresa123",
    "certificado_firestore_field": "certificado_base64"
  }
}
```

## 🔒 Segurança

### ✅ Boas Práticas

1. **Firebase Storage:**
   - Use regras de segurança para proteger arquivos
   - Limite acesso por autenticação
   - Criptografe arquivos sensíveis

2. **Firebase Firestore:**
   - Use regras de segurança
   - Não exponha certificados publicamente
   - Use campos separados para senha

3. **Variáveis de Ambiente:**
   - Nunca commite `firebase-credentials.json`
   - Use secrets no Cloud Run/Firebase Functions

### ⚠️ Regras de Segurança Firebase

**Storage (storage.rules):**
```javascript
rules_version = '2';
service firebase.storage {
  match /b/{bucket}/o {
    match /certificados/{certId} {
      // Apenas usuários autenticados podem ler
      allow read: if request.auth != null;
      // Apenas admins podem escrever
      allow write: if request.auth != null && 
                      get(/databases/$(database)/documents/users/$(request.auth.uid)).data.admin == true;
    }
  }
}
```

**Firestore (firestore.rules):**
```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /empresas/{empresaId} {
      // Apenas o próprio usuário pode ler
      allow read: if request.auth != null && 
                     request.auth.uid == empresaId;
      // Apenas admins podem escrever
      allow write: if request.auth != null && 
                      get(/databases/$(database)/documents/users/$(request.auth.uid)).data.admin == true;
    }
  }
}
```

## 📊 Comparação

| Método | Vantagens | Desvantagens |
|--------|-----------|--------------|
| **Base64 Direto** | ✅ Simples<br>✅ Sem dependências | ❌ Não escalável<br>❌ Expõe certificado |
| **Firebase Storage** | ✅ Arquivo original<br>✅ Fácil gerenciar | ❌ Precisa upload<br>❌ Mais complexo |
| **Firebase Firestore** | ✅ Integrado com dados<br>✅ Fácil consulta | ❌ Limite de tamanho<br>❌ Mais caro |

## 🧪 Testando

### Teste Local (Base64)

```bash
python exemplo_rodar_pynfe.py
```

### Teste Firebase Storage

```python
# Configurar
empresa_data = {
    'certificado_firebase_path': 'certificados/teste.pfx',
    'senhaCertificado': 'senha123'
}

# Usar
resultado = nfce.emitir(empresa_data=empresa_data, ...)
```

### Teste Firebase Firestore

```python
# Configurar
empresa_data = {
    'certificado_firestore_collection': 'empresas',
    'certificado_firestore_doc': 'teste',
    'certificado_firestore_field': 'certificado_base64',
    'senhaCertificado': 'senha123'
}

# Usar
resultado = nfce.emitir(empresa_data=empresa_data, ...)
```

## 🔄 Fallback Automático

O sistema tenta na seguinte ordem:

1. `certificado_base64` (se fornecido)
2. Firebase Storage (se `certificado_firebase_path` fornecido)
3. Firebase Firestore (se campos Firestore fornecidos)

Se nenhum funcionar, retorna erro.

## ✅ Checklist Migração

- [ ] Certificado convertido para Base64
- [ ] Firebase configurado (credentials.json)
- [ ] Certificado enviado para Storage OU Firestore
- [ ] Regras de segurança configuradas
- [ ] Variáveis de ambiente configuradas
- [ ] Testado localmente
- [ ] Testado no Firebase

---

**Pronto para migrar!** 🚀

















