"""
Exemplo de configuração de banco de dados com PostgreSQL + SQLAlchemy
Use este arquivo como base para migrar o app.py existente

Instalação:
    pip install flask-sqlalchemy flask-migrate psycopg2-binary
"""

import os
from datetime import datetime
from flask import Flask
from flask_sqlalchemy import SQLAlchemy
from flask_migrate import Migrate
from dotenv import load_dotenv

# Carregar variáveis de ambiente
load_dotenv()

# Inicializar Flask e banco de dados
app = Flask(__name__)

# ============================================================================
# CONFIGURAÇÃO DO BANCO DE DADOS POSTGRESQL
# ============================================================================

DATABASE_URL = os.getenv(
    'DATABASE_URL',
    'postgresql://exodo_user:senha@localhost:5432/exodo_db'
)

# Garantir que está usando PostgreSQL (não SQLite)
if 'sqlite' in DATABASE_URL:
    print("⚠️  AVISO: Ainda está usando SQLite!")
    print("   Altere a variável DATABASE_URL no arquivo .env")

app.config['SQLALCHEMY_DATABASE_URI'] = DATABASE_URL
app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False
app.config['SQLALCHEMY_ENGINE_OPTIONS'] = {
    'pool_size': 10,
    'pool_recycle': 3600,
    'pool_pre_ping': True,
}

# Inicializar extensões
db = SQLAlchemy(app)
migrate = Migrate(app, db)

# ============================================================================
# MODELOS DO BANCO DE DADOS
# ============================================================================

class Empresa(db.Model):
    """Modelo de Empresa"""
    __tablename__ = 'empresas'
    
    id = db.Column(db.Integer, primary_key=True)
    cnpj = db.Column(db.String(14), unique=True, nullable=False)
    razao_social = db.Column(db.String(255), nullable=False)
    inscricao_estadual = db.Column(db.String(20))
    uf = db.Column(db.String(2), nullable=False)
    codigo_municipio_ibge = db.Column(db.Integer)
    certificado_thumbprint = db.Column(db.String(255))
    
    # Relacionamentos
    vendas = db.relationship('Venda', back_populates='empresa', cascade='all, delete-orphan')
    
    # Metadados
    criado_em = db.Column(db.DateTime, default=datetime.utcnow)
    atualizado_em = db.Column(db.DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
    
    def __repr__(self):
        return f'<Empresa {self.razao_social}>'
    
    def to_dict(self):
        return {
            'id': self.id,
            'cnpj': self.cnpj,
            'razao_social': self.razao_social,
            'inscricao_estadual': self.inscricao_estadual,
            'uf': self.uf,
            'codigo_municipio_ibge': self.codigo_municipio_ibge,
            'criado_em': self.criado_em.isoformat() if self.criado_em else None,
        }


class Venda(db.Model):
    """Modelo de Venda/NFC-e"""
    __tablename__ = 'vendas'
    
    id = db.Column(db.Integer, primary_key=True)
    empresa_id = db.Column(db.Integer, db.ForeignKey('empresas.id'), nullable=False)
    numero_nfe = db.Column(db.String(50), unique=True, nullable=False)
    serie_nfe = db.Column(db.Integer, nullable=False, default=1)
    numero_sequencial = db.Column(db.Integer, nullable=False)
    
    # Valores
    valor_subtotal = db.Column(db.Numeric(12, 2), nullable=False)
    valor_desconto = db.Column(db.Numeric(12, 2), default=0)
    valor_total = db.Column(db.Numeric(12, 2), nullable=False)
    
    # Status
    status = db.Column(db.String(20), default='rascunho')  # rascunho, emitida, autorizada, cancelada
    motivo_cancelamento = db.Column(db.Text)
    
    # XML armazenado
    xml_enviado = db.Column(db.Text)
    xml_retorno = db.Column(db.Text)
    
    # Relacionamentos
    empresa = db.relationship('Empresa', back_populates='vendas')
    itens = db.relationship('ItemVenda', back_populates='venda', cascade='all, delete-orphan')
    
    # Metadados
    criado_em = db.Column(db.DateTime, default=datetime.utcnow)
    atualizado_em = db.Column(db.DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
    emitida_em = db.Column(db.DateTime)
    
    def __repr__(self):
        return f'<Venda {self.numero_nfe}>'
    
    def to_dict(self):
        return {
            'id': self.id,
            'numero_nfe': self.numero_nfe,
            'empresa_id': self.empresa_id,
            'valor_total': float(self.valor_total) if self.valor_total else 0,
            'status': self.status,
            'criado_em': self.criado_em.isoformat() if self.criado_em else None,
        }


class ItemVenda(db.Model):
    """Modelo de Item de Venda"""
    __tablename__ = 'itens_venda'
    
    id = db.Column(db.Integer, primary_key=True)
    venda_id = db.Column(db.Integer, db.ForeignKey('vendas.id'), nullable=False)
    
    numero_item = db.Column(db.Integer, nullable=False)
    codigo_produto = db.Column(db.String(60), nullable=False)
    descricao = db.Column(db.String(255), nullable=False)
    ncm = db.Column(db.String(8))
    cfop = db.Column(db.String(4))
    unidade = db.Column(db.String(6), nullable=False)
    
    quantidade = db.Column(db.Numeric(12, 4), nullable=False)
    valor_unitario = db.Column(db.Numeric(12, 2), nullable=False)
    valor_desconto = db.Column(db.Numeric(12, 2), default=0)
    valor_total = db.Column(db.Numeric(12, 2), nullable=False)
    
    # Relacionamentos
    venda = db.relationship('Venda', back_populates='itens')
    
    # Metadados
    criado_em = db.Column(db.DateTime, default=datetime.utcnow)
    
    def __repr__(self):
        return f'<ItemVenda {self.numero_item} - {self.descricao}>'
    
    def to_dict(self):
        return {
            'id': self.id,
            'numero_item': self.numero_item,
            'codigo_produto': self.codigo_produto,
            'descricao': self.descricao,
            'quantidade': float(self.quantidade),
            'valor_unitario': float(self.valor_unitario),
            'valor_total': float(self.valor_total),
        }


# ============================================================================
# EXEMPLO DE USO
# ============================================================================

if __name__ == '__main__':
    # Criar tabelas (na primeira execução)
    with app.app_context():
        db.create_all()
        print("✅ Tabelas criadas/verificadas")
        
        # Exemplo: criar empresa
        empresa = Empresa(
            cnpj='12345678000190',
            razao_social='Empresa Teste',
            inscricao_estadual='123456789',
            uf='SP',
            codigo_municipio_ibge=3550308
        )
        
        try:
            db.session.add(empresa)
            db.session.commit()
            print("✅ Empresa criada com sucesso!")
        except Exception as e:
            db.session.rollback()
            print(f"❌ Erro ao criar empresa: {e}")
