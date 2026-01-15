"""
Configurações para ambiente de produção
"""

import os
from dotenv import load_dotenv

# Carregar variáveis de ambiente
load_dotenv()

class ProductionConfig:
    """Configurações de produção"""
    
    # Configurações do servidor
    HOST = os.getenv('HOST', '0.0.0.0')
    PORT = int(os.getenv('PORT', 5000))
    
    # Configurações do Flask
    DEBUG = False
    TESTING = False
    
    # Configurações de segurança
    SECRET_KEY = os.getenv('SECRET_KEY', 'change-this-in-production')
    
    # Configurações de CORS
    CORS_ORIGINS = os.getenv('CORS_ORIGINS', '*').split(',')
    
    # Configurações de logging
    LOG_LEVEL = os.getenv('LOG_LEVEL', 'INFO')
    LOG_FILE = os.getenv('LOG_FILE', 'logs/production.log')
    
    # Configurações do Waitress
    WAITRESS_THREADS = int(os.getenv('WAITRESS_THREADS', '8'))
    WAITRESS_CHANNEL_TIMEOUT = int(os.getenv('WAITRESS_CHANNEL_TIMEOUT', '120'))
    
    # Configurações de segurança
    MAX_CONTENT_LENGTH = int(os.getenv('MAX_CONTENT_LENGTH', '10485760'))  # 10MB
    
    @staticmethod
    def init_app(app):
        """Inicializar configurações no app Flask"""
        # Configurar logging
        import logging
        from logging.handlers import RotatingFileHandler
        
        if not os.path.exists('logs'):
            os.makedirs('logs')
        
        file_handler = RotatingFileHandler(
            ProductionConfig.LOG_FILE,
            maxBytes=10240000,  # 10MB
            backupCount=10
        )
        file_handler.setFormatter(logging.Formatter(
            '%(asctime)s %(levelname)s: %(message)s [in %(pathname)s:%(lineno)d]'
        ))
        file_handler.setLevel(logging.INFO)
        app.logger.addHandler(file_handler)
        app.logger.setLevel(logging.INFO)
        app.logger.info('Backend NFC-e iniciado em modo PRODUÇÃO')

