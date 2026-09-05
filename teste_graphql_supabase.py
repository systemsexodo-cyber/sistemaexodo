#!/usr/bin/env python3
"""Teste via GraphQL - pode funcionar melhor que REST"""
import urllib.request
import json
import os
from dotenv import load_dotenv

load_dotenv()

url = os.getenv('SUPABASE_URL')
key = os.getenv('SUPABASE_ANON_KEY')

graphql_url = f"{url}/graphql/v1"

# Query GraphQL simples
query = """
{
  empresasCollection(first: 1) {
    edges {
      node {
        id
      }
    }
    pageInfo {
      hasNextPage
    }
  }
}
"""

headers = {
    'Content-Type': 'application/json',
    'apikey': key,
    'Authorization': f'Bearer {key}'
}

data = json.dumps({'query': query})

print(f"URL: {graphql_url}")
print(f"Query: {query}\n")

req = urllib.request.Request(
    graphql_url,
    data=data.encode('utf-8'),
    headers=headers,
    method='POST'
)

try:
    with urllib.request.urlopen(req, timeout=10) as r:
        response = json.loads(r.read().decode())
        print(f"Status: {r.status}")
        print(f"Response: {json.dumps(response, indent=2)}")
except Exception as e:
    print(f"Erro: {type(e).__name__}")
    print(f"Mensagem: {e}")
    
    # Se GraphQL não funcionar, tentar um acesso direto mais simples
    print("\n" + "="*60)
    print("Tentando REST API novamente com curl simulation...")
    
    rest_url = f"{url}/rest/v1/empresas?select=id"
    req2 = urllib.request.Request(rest_url, headers=headers)
    try:
        with urllib.request.urlopen(req2, timeout=10) as r2:
            data = r2.read().decode()
            print(f"Raw response: {data}")
            print(f"Headers: {dict(r2.headers)}")
    except Exception as e2:
        print(f"Erro no REST: {e2}")
