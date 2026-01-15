========================================
  COMO EXECUTAR O BACKEND NFC-e
========================================

METODO MAIS RAPIDO (Windows):
------------------------------
Duplo clique em:
  EXECUTAR_BACKEND_AGORA.bat

Isso vai fazer tudo automaticamente!


METODO MANUAL:
--------------
1. Abra PowerShell ou CMD
2. Navegue ate a pasta:
   cd backend_pynfe

3. Instale dependencias (primeira vez apenas):
   python -m pip install flask flask-cors python-dotenv requests lxml signxml cryptography

4. Inicie o servidor:
   python app.py


VERIFICAR SE ESTA FUNCIONANDO:
-------------------------------
Abra no navegador:
  http://localhost:5000/health

Deve aparecer:
  {"status": "ok", "message": "Backend NFC-e está funcionando"}


REQUISITOS:
-----------
- Python 3.10+ instalado
- Python no PATH do sistema
- Conexao com internet (para comunicar com SEFAZ)


PROBLEMAS COMUNS:
-----------------
- "Python nao encontrado": Instale Python e marque "Add Python to PATH"
- "ModuleNotFoundError": Execute: pip install flask flask-cors python-dotenv requests lxml signxml cryptography
- "Port 5000 already in use": Feche outro programa usando a porta 5000


PRONTO!
-------
Depois que o backend estiver rodando, use o sistema Flutter normalmente.
Mantenha o terminal aberto enquanto usa o sistema!

Para mais detalhes, veja: COMO_EXECUTAR_BACKEND.md











