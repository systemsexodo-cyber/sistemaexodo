# 🔗 Links Personalizados com Nome da Loja

## 📋 Visão Geral

O sistema agora gera links personalizados que incluem o nome da loja na URL, tornando-os mais amigáveis e profissionais.

## 🎯 Formatos de URL Suportados

### **Formato Novo (Recomendado)**
```
https://seusite.com/loja/nome-da-loja/ABC123
```

**Exemplo:**
- Empresa: "Pet Shop Exodo"
- Link gerado: `https://seusite.com/loja/pet-shop-exodo/ABC123`

### **Formato Antigo (Compatibilidade)**
```
https://seusite.com/loja?link=ABC123
```

O sistema ainda suporta o formato antigo para compatibilidade com links já criados.

## 🔧 Como Funciona

### **1. Geração do Slug (URL Amigável)**

O sistema converte o nome da empresa em um slug amigável:

```dart
// Exemplo de conversão:
"Pet Shop Exodo" → "pet-shop-exodo"
"Loja do João & Maria" → "loja-do-joao-maria"
"Café & Cia" → "cafe-cia"
```

**Regras de conversão:**
- ✅ Converte para minúsculas
- ✅ Remove acentos (á → a, é → e, etc.)
- ✅ Remove caracteres especiais
- ✅ Substitui espaços por hífens
- ✅ Limita a 50 caracteres
- ✅ Remove hífens duplicados

### **2. Criação do Link**

Quando você cria um novo link:

1. O sistema obtém o nome da empresa atual
2. Gera um slug a partir do nome
3. Cria a URL no formato: `/loja/{slug}/{codigo}`

**Exemplo:**
```dart
// Empresa: "Minha Loja"
// Código: "ABC123"
// URL gerada: "https://seusite.com/loja/minha-loja/ABC123"
```

### **3. Detecção na Loja Pública**

A loja pública detecta o código do link em dois formatos:

1. **Query Parameter**: `?link=ABC123`
2. **Path**: `/loja/nome-da-loja/ABC123`

Ambos os formatos funcionam perfeitamente!

## 📝 Exemplos Práticos

### **Exemplo 1: Loja com Nome Simples**
- **Empresa**: "Loja do Bairro"
- **Código**: "XYZ789"
- **URL Gerada**: `https://seusite.com/loja/loja-do-bairro/XYZ789`

### **Exemplo 2: Loja com Caracteres Especiais**
- **Empresa**: "Café & Cia - Pet Shop"
- **Código**: "DEF456"
- **URL Gerada**: `https://seusite.com/loja/cafe-cia-pet-shop/DEF456`

### **Exemplo 3: Loja com Acentos**
- **Empresa**: "Açúcar & Mel"
- **Código**: "GHI123"
- **URL Gerada**: `https://seusite.com/loja/acucar-mel/GHI123`

## 🚀 Como Usar

### **Criar um Novo Link**

1. Acesse: Menu Principal → "Links Vendedores"
2. Clique no botão "+" (criar novo link)
3. Selecione o vendedor
4. O código será gerado automaticamente
5. A URL será criada automaticamente com o nome da loja
6. Clique em "Criar"

### **Copiar o Link**

1. Na lista de links, clique no ícone de copiar
2. O link completo será copiado para a área de transferência
3. Compartilhe com seus clientes!

### **Compartilhar o Link**

1. Clique no ícone de compartilhar
2. O sistema tentará usar a API de compartilhamento do navegador
3. Se não disponível, copia automaticamente para a área de transferência

## 🔄 Atualização Automática

Se o nome da empresa mudar, os links existentes podem ser atualizados:

- Ao editar um link, a URL é recalculada com o nome atual da empresa
- Isso garante que os links sempre reflitam o nome correto da loja

## 📊 Vantagens dos Links Personalizados

✅ **Mais Profissional**: URLs com o nome da loja parecem mais confiáveis
✅ **SEO Friendly**: URLs amigáveis são melhores para mecanismos de busca
✅ **Fácil de Lembrar**: Clientes podem lembrar melhor do link
✅ **Branding**: Reforça a marca da empresa na URL
✅ **Compatibilidade**: Ainda funciona com o formato antigo

## 🔍 Detalhes Técnicos

### **Função de Geração de Slug**

```dart
String _gerarSlugNomeLoja(String nome) {
  // Converte para minúsculas
  String slug = nome.toLowerCase();
  
  // Remove acentos
  slug = slug
      .replaceAll(RegExp(r'[áàâãä]'), 'a')
      .replaceAll(RegExp(r'[éèêë]'), 'e')
      // ... outros acentos
  
  // Remove caracteres especiais
  slug = slug.replaceAll(RegExp(r'[^a-z0-9\s-]'), '');
  
  // Substitui espaços por hífens
  slug = slug.replaceAll(RegExp(r'[\s-]+'), '-');
  
  // Limita tamanho
  if (slug.length > 50) {
    slug = slug.substring(0, 50);
  }
  
  return slug;
}
```

### **Geração da URL**

```dart
String _gerarUrlCompleta(String codigoLink, String? nomeLoja) {
  final urlBase = kIsWeb 
      ? html.window.location.origin 
      : 'https://seusite.com';
  
  if (nomeLoja != null && nomeLoja.isNotEmpty) {
    final slug = _gerarSlugNomeLoja(nomeLoja);
    return '$urlBase/loja/$slug/$codigoLink';
  } else {
    // Fallback para formato antigo
    return '$urlBase/loja?link=$codigoLink';
  }
}
```

## ⚠️ Notas Importantes

1. **Slug Único**: O slug é gerado a partir do nome da empresa, não é único por link
2. **Múltiplos Links**: Vários vendedores podem ter links diferentes com o mesmo slug, mas códigos diferentes
3. **Compatibilidade**: Links antigos continuam funcionando normalmente
4. **Atualização**: Se mudar o nome da empresa, edite os links para atualizar as URLs

## 🎨 Personalização

Você pode personalizar ainda mais os links editando a função `_gerarUrlCompleta`:

- **Subdomínio**: `https://nome-da-loja.seusite.com/ABC123`
- **Domínio próprio**: `https://nomedaloja.com.br/ABC123`
- **Path customizado**: `https://seusite.com/vendedor/nome-da-loja/ABC123`













