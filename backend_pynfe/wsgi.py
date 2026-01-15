"""
WSGI entry point para servidor de produção
Este arquivo é usado por servidores WSGI como Waitress, Gunicorn, etc.
"""

import os
from dotenv import load_dotenv

# Carregar variáveis de ambiente de produção
env_file = os.path.join(os.path.dirname(__file__), '.env.production')
if os.path.exists(env_file):
    load_dotenv(env_file)
else:
    # Fallback para .env normal
    load_dotenv()

from app import app
from config_production import ProductionConfig

# Aplicar configurações de produção
app.config.from_object(ProductionConfig)
ProductionConfig.init_app(app)

# Esta variável é obrigatória para servidores WSGI
application = app

if __name__ == "__main__":
    # Verificar se está no Cloud Run (usa PORT do ambiente)
    port = int(os.getenv('PORT', 5000))
    
    # Cloud Run sempre usa PORT, então se PORT != 5000, provavelmente é Cloud Run
    # Cloud Run também usa gunicorn via Dockerfile, então este código só roda localmente
    if port == 5000:
        # Modo local - usar Waitress
        from waitress import serve
        
        host = os.getenv('HOST', '0.0.0.0')
        threads = int(os.getenv('WAITRESS_THREADS', '8'))
        timeout = int(os.getenv('WAITRESS_CHANNEL_TIMEOUT', '120'))
        
        print('=' * 50)
        print('[PRODUCAO] Backend NFC-e - Modo Local')
        print('=' * 50)
        print(f'Porta: {port}')
        print(f'Host: {host}')
        print(f'Servidor: Waitress (WSGI)')
        print(f'Threads: {threads}')
        print(f'Timeout: {timeout}s')
        print(f'URL: http://{host}:{port}')
        print(f'Health: http://{host}:{port}/health')
        print('=' * 50)
        print('')
        print('Pressione Ctrl+C para parar')
        print('')
        
        # Iniciar servidor Waitress com configurações de produção
        serve(
            application, 
            host=host, 
            port=port, 
            threads=threads,
            channel_timeout=timeout
        )
    else:
        # Cloud Run - gunicorn já está configurado no Dockerfile
        print(f'[CLOUD RUN] Porta configurada: {port}')
        print('[CLOUD RUN] Use gunicorn conforme Dockerfile')

