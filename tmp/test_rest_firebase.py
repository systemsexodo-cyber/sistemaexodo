import requests
import json
import time

# Teste via REST API do Firebase (sem gRPC)
def test_rest():
    try:
        # Nota: Isso nao usa as credenciais, apenas testa se o Google responde
        r = requests.get("https://firestore.googleapis.com/v1/projects/exodosystems-1541d/databases/(default)/documents/bridge_config/latest")
        print(f"REST Status: {r.status_code}")
        print(f"REST Response: {r.text[:200]}")
    except Exception as e:
        print(f"REST Error: {e}")

test_rest()
